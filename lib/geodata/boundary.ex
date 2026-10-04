defmodule GeoData.Boundary do
  @moduledoc """
  Boundary polygons and coordinate containment.

  Natural Earth country (`admin_0`) and subdivision (`admin_1`) polygons are
  fetched and cached through `GeoData.Fetch`, then matched against coordinates
  with [`topo`](https://hexdocs.pm/topo). The geometry is kept as
  [`geo`](https://hexdocs.pm/geo) structs, so it interoperates with the wider
  Elixir geo ecosystem.

  Nothing is downloaded unless you opt in with the `:boundaries` option:

      config :geodata, boundaries: [:country, :subdivision]

  or `:all`. `:boundary_detail` selects the Natural Earth scale for countries:
  `:low` (the default, 1:50m) or `:high` (1:10m, larger but more accurate).
  Subdivisions always use 1:10m. Boundary files are downloaded alongside
  ingestion, or on demand with `fetch/1`, `build/1` or `mix geodata.boundaries`.

  The simplified 1:50m coastline can drop a coastal or estuarine point into the
  water — downtown Lisbon (`38.72, -9.13`) falls in the carved-out Tagus
  estuary — so use `:high` when coastal accuracy matters.

  Until boundaries are loaded, `GeoData.containing/3` returns `{:ok, []}`.

  ## Containment

      GeoData.Boundary.containing(40.20, -8.42)
      #=> {:ok, [%GeoData.Place{kind: :country, iso_3166_1: "PT"},
      #          %GeoData.Place{kind: :subdivision, iso_3166_2: "PT-06"}]}

  Areas that contain a point are matched from coarse to fine. A point on a
  border (which a polygon does not strictly contain) still matches through
  `Topo.intersects?/2`.

  ## Geometry

  Each boundary carries its `%Geo.Polygon{}` or `%Geo.MultiPolygon{}` and its
  bounding box, and can be tested directly:

      {:ok, boundary} = GeoData.boundary("ISO:PT")
      GeoData.Boundary.contains?(boundary, {40.20, -8.42})
      GeoData.Boundary.bbox(boundary)

  Predicates take a `{latitude, longitude}` tuple, matching the rest of
  GeoData.
  """

  alias GeoData.Fetch
  alias GeoData.ID
  alias GeoData.Place
  alias GeoData.Source.BoundaryData
  alias GeoData.Storage
  alias GeoData.ValidationError

  @cache {__MODULE__, :index}

  @default_source_path Application.compile_env(
                         :geodata,
                         :source_path,
                         "priv/geodata/sources"
                       )

  @levels [:country, :subdivision]
  @kind_rank %{country: 0, subdivision: 1}

  defstruct [
    :id,
    :place_id,
    :kind,
    :iso_3166_1,
    :iso_3166_2,
    :name,
    :geometry,
    :bbox,
    :detail,
    sources: []
  ]

  @doc """
  Downloads the configured boundary files.

  Reads `:boundaries` and `:boundary_detail` from the given options, falling
  back to the application environment. Existing files are reused unless
  `:force` is set.

  Returns `{:ok, info}` with the requested `:levels` and the resolved `:files`,
  or `{:error, exception}`.
  """
  def fetch(opts \\ []) do
    opts = defaults(opts)

    with {:ok, %{levels: levels, resolved: resolved}} <- ensure(opts) do
      {:ok, %{levels: levels, files: files(resolved)}}
    end
  end

  @doc """
  Downloads the configured boundaries and rebuilds the in-memory index.

  Returns `{:ok, info}` with the loaded `:levels`, resolved `:files` and a
  `:total` count of indexed boundaries, or `{:error, exception}`.
  """
  def build(opts \\ []) do
    opts = defaults(opts)
    reset()

    with {:ok, %{levels: levels, resolved: resolved}} <- ensure(opts) do
      index = resolved |> index_from_files() |> put_index()
      {:ok, %{levels: levels, files: files(resolved), total: length(index.boundaries)}}
    end
  end

  defp files(resolved), do: %{BoundaryData.source() => resolved}

  defp ensure(opts) do
    levels = BoundaryData.levels(Keyword.fetch!(opts, :boundaries))

    if levels == [] do
      {:ok, %{levels: [], resolved: %{}}}
    else
      with {:ok, resolved} <-
             Fetch.ensure([BoundaryData], Keyword.put(opts, :boundaries, levels)) do
        {:ok, %{levels: levels, resolved: Map.get(resolved, BoundaryData.source(), %{})}}
      end
    end
  end

  @doc """
  Returns whether boundaries are currently loaded in memory.
  """
  def loaded? do
    case :persistent_term.get(@cache, :missing) do
      %{boundaries: [_ | _]} -> true
      _ -> false
    end
  end

  @doc """
  Loads the in-memory index, building it from the cached files on first use.
  """
  def load do
    case :persistent_term.get(@cache, :missing) do
      :missing ->
        index = from_disk()
        :persistent_term.put(@cache, index)
        index

      index ->
        index
    end
  end

  @doc """
  Clears the in-memory index, so the next lookup reloads it from disk.
  """
  def reset, do: :persistent_term.erase(@cache)

  @doc """
  Returns the supported boundary levels.
  """
  def levels, do: @levels

  @doc """
  Returns the boundary for a place or canonical id.

  Returns `{:ok, %GeoData.Boundary{}}` or `{:error, :not_found}`.
  """
  def get(%Place{id: id}), do: get(id)

  def get(id) do
    case boundary_id(id) do
      nil ->
        {:error, :not_found}

      id ->
        case Map.fetch(load().by_id, id) do
          {:ok, boundary} -> {:ok, boundary}
          :error -> {:error, :not_found}
        end
    end
  end

  @doc """
  Returns the boundaries matching the given options.

  Accepts `:kind` or `:kinds` to restrict the levels (e.g. `kind: :country`).
  """
  def boundaries(opts \\ []) do
    kinds = kinds(opts)
    Enum.filter(load().boundaries, &(&1.kind in kinds))
  end

  @doc """
  Returns the places whose boundaries contain the coordinate `{lat, lon}`.

  Returns `{:ok, places}` ordered from coarse to fine (country before
  subdivision). An ocean point or an area without an ingested place yields
  `{:ok, []}`. Options:

    * `:kind` / `:kinds` - restrict the levels to `:country`, `:subdivision`
      or a list of both

  ## Examples

      GeoData.Boundary.containing(40.20, -8.42)
      GeoData.Boundary.containing(40.20, -8.42, kind: :country)

  """
  def containing(lat, lon, opts \\ []) do
    with {:ok, point} <- normalize_point(lat, lon) do
      candidates = candidates(point, kinds(opts))

      matches =
        case contains(candidates, point) do
          [] -> intersects(candidates, point)
          matches -> matches
        end

      places =
        matches
        |> Enum.sort_by(&kind_rank/1)
        |> Enum.map(&to_place/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.id)

      {:ok, places}
    end
  end

  @doc """
  Returns whether `boundary` contains the `{lat, lon}` coordinate.

  The coordinate is a `{latitude, longitude}` tuple.
  """
  def contains?(%__MODULE__{geometry: geometry}, {lat, lon})
      when is_number(lat) and is_number(lon),
      do: Topo.contains?(geometry, {lon, lat})

  def contains?(_boundary, _point), do: false

  @doc """
  Returns whether the `{lat, lon}` coordinate lies on the boundary of `boundary`.

  Unlike `contains?/2`, a point on the polygon's edge returns `true`.
  """
  def intersects?(%__MODULE__{geometry: geometry}, {lat, lon})
      when is_number(lat) and is_number(lon),
      do: Topo.intersects?(geometry, {lon, lat})

  def intersects?(_boundary, _point), do: false

  @doc """
  Returns whether the `{lat, lon}` coordinate lies within `boundary`.
  """
  def within?(point, %__MODULE__{} = boundary), do: contains?(boundary, point)

  @doc """
  Returns the bounding box of `boundary` as `{min_lat, min_lon, max_lat, max_lon}`.

  The order matches `{latitude, longitude}` points, `GeoData.Distance.bounding_box/3`
  and the `where: [bbox: ...]` search filter.
  """
  def bbox(%__MODULE__{bbox: bbox}), do: bbox

  # Fetching and building

  defp defaults(opts) do
    opts
    |> Keyword.put_new(:boundaries, configured(:boundaries, []))
    |> Keyword.put_new(:boundary_detail, configured(:boundary_detail, :low))
    |> Keyword.put_new(:source_path, source_path())
  end

  defp from_disk do
    directory = Path.join(source_path(), "boundaries")
    expected = expected_files()

    case File.ls(directory) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&MapSet.member?(expected, &1))
        |> Enum.sort()
        |> Enum.flat_map(&boundaries_from_file(Path.join(directory, &1)))
        |> index()

      {:error, _reason} ->
        index([])
    end
  end

  defp expected_files do
    levels = BoundaryData.levels(configured(:boundaries, []))
    detail = configured(:boundary_detail, :low)

    BoundaryData.files(boundaries: levels, boundary_detail: detail)
    |> Enum.map(&Path.basename(&1.filename))
    |> MapSet.new()
  end

  defp index(boundaries) do
    %{
      boundaries: boundaries,
      by_id: Map.new(boundaries, &{&1.id, &1})
    }
  end

  defp index_from_files(resolved) do
    resolved
    |> Enum.sort_by(fn {key, _info} -> key end)
    |> Enum.flat_map(fn {_key, %{path: path}} -> boundaries_from_file(path) end)
    |> index()
  end

  defp put_index(index) do
    :persistent_term.put(@cache, index)
    index
  end

  defp boundaries_from_file(path) do
    {kind, detail} = file_meta(path)

    with {:ok, body} <- File.read(path),
         {:ok, %{"features" => features}} when is_list(features) <- JSON.decode(body) do
      features
      |> Enum.map(&boundary(&1, kind, detail))
      |> Enum.reject(&is_nil/1)
    else
      _ -> []
    end
  rescue
    _error -> []
  end

  defp boundary(%{"geometry" => %{} = geometry} = feature, kind, detail) do
    props = feature["properties"] || %{}

    with {:ok, geom} <- Geo.JSON.decode(geometry),
         {:ok, id, iso1, iso2} <- identifier(kind, props) do
      %__MODULE__{
        id: id,
        place_id: id,
        kind: kind,
        iso_3166_1: iso1,
        iso_3166_2: iso2,
        name: name(props),
        geometry: geom,
        bbox: bbox_of(geom),
        detail: detail,
        sources: [:natural_earth]
      }
    else
      _ -> nil
    end
  end

  defp boundary(_feature, _kind, _detail), do: nil

  defp identifier(:country, props) do
    case first_code([props["ISO_A2_EH"], props["ISO_A2"]]) do
      nil -> :error
      code -> {:ok, ID.for_country(code), code, nil}
    end
  end

  defp identifier(:subdivision, props) do
    case props["iso_3166_2"] do
      code when is_binary(code) ->
        case String.split(code, "-", parts: 2) do
          [country, rest] when rest != "" ->
            {:ok, ID.for_subdivision(code), String.upcase(country), String.upcase(code)}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp first_code(codes) do
    Enum.find_value(codes, fn
      code when is_binary(code) ->
        upcased = String.upcase(String.trim(code))

        if String.length(upcased) == 2 and upcased != "-99" and upcased =~ ~r/\A[A-Z]{2}\z/ do
          upcased
        end

      _ ->
        nil
    end)
  end

  defp name(props) do
    props["NAME_EN"] || props["NAME"] || props["name_en"] || props["name"] || props["name_local"]
  end

  defp bbox_of(geometry) do
    case points(geometry) do
      [] ->
        nil

      points ->
        {lons, lats} = Enum.unzip(points)
        {Enum.min(lats), Enum.min(lons), Enum.max(lats), Enum.max(lons)}
    end
  end

  defp points(%Geo.MultiPolygon{coordinates: polygons}) do
    Enum.flat_map(polygons, &ring_points/1)
  end

  defp points(%Geo.Polygon{coordinates: rings}), do: ring_points(rings)
  defp points(_geometry), do: []

  defp ring_points(rings), do: Enum.flat_map(rings, & &1)

  defp file_meta(path) do
    base = Path.basename(path)

    kind = if String.contains?(base, "admin_1"), do: :subdivision, else: :country
    detail = if String.contains?(base, "10m"), do: :high, else: :low

    {kind, detail}
  end

  # Lookup

  defp candidates(point, kinds) do
    load().boundaries
    |> Enum.filter(&(&1.kind in kinds and bbox_contains?(&1.bbox, point)))
  end

  defp bbox_contains?(nil, _point), do: false

  defp bbox_contains?({min_lat, min_lon, max_lat, max_lon}, {lon, lat}) do
    lat >= min_lat and lat <= max_lat and lon >= min_lon and lon <= max_lon
  end

  defp contains(candidates, point), do: Enum.filter(candidates, &contains?(&1, to_lat_lon(point)))

  defp intersects(candidates, point),
    do: Enum.filter(candidates, &intersects?(&1, to_lat_lon(point)))

  defp to_place(%__MODULE__{id: id}) do
    case Storage.get(id) do
      {:ok, place} -> place
      _ -> nil
    end
  end

  defp kind_rank(%__MODULE__{kind: kind}), do: Map.get(@kind_rank, kind, 99)

  defp kinds(opts) do
    cond do
      is_list(opts[:kinds]) -> opts[:kinds]
      opts[:kind] -> List.wrap(opts[:kind])
      true -> @levels
    end
  end

  defp normalize_point(lat, lon) when is_number(lat) and is_number(lon) do
    cond do
      lat < -90 or lat > 90 -> {:error, invalid_coordinate(:latitude, lat)}
      lon < -180 or lon > 180 -> {:error, invalid_coordinate(:longitude, lon)}
      true -> {:ok, {lon * 1.0, lat * 1.0}}
    end
  end

  defp normalize_point(lat, lon), do: {:error, invalid_coordinate(:coordinate, {lat, lon})}

  defp invalid_coordinate(field, value) do
    %ValidationError{
      field: field,
      value: value,
      reason: :invalid_type,
      expected: "latitude in -90..90 and longitude in -180..180"
    }
  end

  # `point` is a `{longitude, latitude}` tuple in geo coordinates.
  defp to_lat_lon({lon, lat}), do: {lat, lon}

  defp boundary_id(id) when is_binary(id) do
    case ID.parse(id) do
      {:ok, {:iso, code}} ->
        if String.contains?(code, "-"), do: ID.for_subdivision(code), else: ID.for_country(code)

      _ ->
        nil
    end
  end

  defp boundary_id(_id), do: nil

  defp configured(key, default), do: Application.get_env(:geodata, key, default)

  defp source_path do
    Application.get_env(:geodata, :source_path, @default_source_path)
  end
end
