defmodule GeoData.Ingest do
  @moduledoc """
  Orchestrates ingestion of source data into `GeoData.Storage`.

  Ingestion resolves the sources for the configured dataset tier, ensures
  their files are available locally through `GeoData.Fetch`, parses them into
  `GeoData.Place` records, merges records that share an id and writes the
  result to storage.

  Country and subdivision records are merged in memory by id; every other
  kind (cities, localities and features) is streamed to storage in batches and
  never loaded as a whole, so the `:all` tier can be ingested with bounded
  memory.

  ## Dataset tiers

    * `:base` - ISO 3166 countries and subdivisions (`iso-codes`)
    * `:cities` - `:base` plus GeoNames places with 1000+ inhabitants
    * `:all` - `:base` plus every GeoNames populated place

  ## Options

  Ingestion accepts the validated options from `GeoData.Options`, notably
  `:dataset`, `:sources`, `:storage`, `:source_path`, `:files`, `:force`,
  `:reset` and `:postal_countries`. When `:postal_countries` is set, the
  postal-code patterns are downloaded as part of ingestion; see
  `GeoData.Postal`.

  ## Examples

      GeoData.Ingest.run(dataset: :base, reset: true)
      #=> {:ok, %GeoData.Ingest.Report{total: 5295}}

  """

  alias GeoData.Attribution
  alias GeoData.Fetch
  alias GeoData.Ingest.Report
  alias GeoData.Options
  alias GeoData.Place
  alias GeoData.Source
  alias GeoData.Source.BoundaryData
  alias GeoData.Source.IsoCodes
  alias GeoData.Source.PostalData

  @identity_kinds [:country, :subdivision]
  @batch_size 1_000

  @doc """
  Runs ingestion with the given options.

  Returns `{:ok, report}` or `{:error, exception}`.
  """
  def run(opts \\ []) do
    with {:ok, opts} <- config(opts),
         {:ok, sources} <- Source.resolve(opts),
         {:ok, resolved} <- Fetch.ensure(sources, opts),
         {:ok, stream} <- parse(sources, resolved, opts),
         :ok <- reset(opts),
         {:ok, stats} <- store(stream, opts, withdrawn_codes(resolved)),
         {:ok, attribution} <- Attribution.write(sources ++ extra_sources(opts), opts),
         :ok <- fetch_postal(opts),
         :ok <- fetch_boundaries(opts) do
      {:ok, Report.new(sources, resolved, stats, attribution)}
    end
  end

  defp extra_sources(opts) do
    []
    |> maybe_source(BoundaryData, Keyword.get(opts, :boundaries, []) != [])
    |> maybe_source(PostalData, Keyword.get(opts, :postal_countries, []) != [])
  end

  defp maybe_source(sources, _module, false), do: sources
  defp maybe_source(sources, module, true), do: sources ++ [module]

  defp fetch_boundaries(opts) do
    if BoundaryData.levels(Keyword.get(opts, :boundaries, [])) == [] do
      :ok
    else
      case GeoData.Boundary.build(opts) do
        {:ok, _info} -> :ok
        {:error, error} -> {:error, error}
      end
    end
  end

  defp fetch_postal(opts) do
    case Keyword.get(opts, :postal_countries, []) do
      [] ->
        :ok

      _countries ->
        case GeoData.Postal.fetch(opts) do
          {:ok, _info} -> :ok
          {:error, error} -> {:error, error}
        end
    end
  end

  defp config(opts) do
    {downloader, opts} = Keyword.pop(opts, :downloader)

    case Options.validate(opts) do
      {:ok, opts} ->
        {:ok, if(downloader, do: Keyword.put(opts, :downloader, downloader), else: opts)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp reset(opts) do
    if opts[:reset], do: opts[:storage].reset(), else: :ok
  end

  defp parse(sources, resolved, opts) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, acc} ->
      paths = paths_for(resolved[source.source()])

      case source.parse(paths, opts) do
        {:ok, places} -> {:cont, {:ok, [places | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, streams} -> {:ok, streams |> Enum.reverse() |> Stream.flat_map(& &1)}
      {:error, error} -> {:error, error}
    end
  end

  defp paths_for(files), do: Map.new(files, fn {key, %{path: path}} -> {key, path} end)

  defp store(stream, opts, withdrawn) do
    storage = opts[:storage]

    {index, stats} =
      stream
      |> Stream.chunk_every(@batch_size)
      |> Enum.reduce({%{}, empty_stats()}, fn chunk, {index, stats} ->
        {identity, bulk} = Enum.split_with(chunk, &identity_kind?/1)

        index = Enum.reduce(identity, index, &put_identity/2)

        if bulk != [], do: storage.put_many(bulk)

        {index, stats |> count(bulk) |> tally_sources(bulk)}
      end)

    identity =
      index
      |> Map.values()
      |> Enum.reject(&withdrawn?(&1, withdrawn))

    if identity != [], do: storage.put_many(identity)

    stats = stats |> count(identity) |> tally_sources(identity)

    {:ok, stats}
  end

  # GeoNames' `countryInfo` still lists countries ISO has withdrawn (e.g. `AN`,
  # `CS`). Drop a country that GeoNames alone provides when ISO 3166-3 lists its
  # code as withdrawn; the `:iso_codes` guard keeps a code ISO reassigned.
  defp withdrawn?(%Place{kind: :country, iso_3166_1: code, sources: sources}, withdrawn),
    do: code in withdrawn and :iso_codes not in sources

  defp withdrawn?(_place, _withdrawn), do: false

  defp withdrawn_codes(resolved) do
    case resolved[:iso_codes] do
      %{iso_3166_3: %{path: path}} -> IsoCodes.former_country_codes(path)
      _ -> MapSet.new()
    end
  end

  defp identity_kind?(%Place{kind: kind}), do: kind in @identity_kinds

  defp put_identity(place, index) do
    case Map.fetch(index, place.id) do
      {:ok, existing} -> Map.put(index, place.id, Place.merge(existing, place))
      :error -> Map.put(index, place.id, place)
    end
  end

  defp empty_stats, do: %{total: 0, by_kind: %{}, by_source: %{}}

  defp count(stats, places) do
    by_kind = Enum.reduce(places, stats.by_kind, fn place, acc -> bump(acc, place.kind) end)
    %{stats | total: stats.total + length(places), by_kind: by_kind}
  end

  defp tally_sources(stats, places) do
    by_source =
      Enum.reduce(places, stats.by_source, fn place, acc ->
        Enum.reduce(place.sources, acc, &bump(&2, &1))
      end)

    %{stats | by_source: by_source}
  end

  defp bump(map, key), do: Map.update(map, key, 1, &(&1 + 1))
end
