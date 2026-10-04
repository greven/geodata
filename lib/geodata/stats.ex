defmodule GeoData.Stats do
  @moduledoc """
  Aggregate statistics and country relationships over the stored places.

  Statistics are computed at read time from `GeoData.Storage`, so they reflect
  whatever is in the store and work with every storage adapter.

  ## Examples

  ```elixir
  {:ok, summary} = GeoData.Stats.summary()
  summary.total

  {:ok, country} = GeoData.Stats.country("PT")
  country.cities
  country.neighbours

  {:ok, neighbours} = GeoData.Stats.neighbours("PT")
  ```

  Borders come from the GeoNames `neighbours` column, exposed as the
  `:neighbours` field of a country `GeoData.Place` (a list of ISO 3166-1
  alpha-2 codes). Because that data is ingested, existing stores need to be
  re-ingested for `neighbours/1` to return anything.
  """

  alias GeoData.Place
  alias GeoData.Stats.Country
  alias GeoData.Stats.Summary

  alias GeoData.NotFoundError
  alias GeoData.ValidationError

  @country_schema NimbleOptions.new!(
                    largest: [
                      type: :pos_integer,
                      default: 5,
                      doc: "Number of largest cities to include"
                    ]
                  )

  @doc """
  Returns dataset-wide statistics.

  Counts every stored place by kind and counts countries by continent.

  ## Examples

      GeoData.Stats.summary()
      #=> {:ok, %GeoData.Stats.Summary{total: 5295, ...}}

  """
  def summary do
    {:ok,
     GeoData.all()
     |> Enum.reduce(%Summary{}, fn place, summary ->
       summary = %{summary | total: summary.total + 1, by_kind: bump(summary.by_kind, place.kind)}

       if place.kind == :country and is_binary(place.continent) do
         %{summary | by_continent: bump(summary.by_continent, place.continent)}
       else
         summary
       end
     end)}
  end

  @doc """
  Returns statistics for a country.

  Accepts an ISO 3166-1 alpha-2 code (string or atom) or a country
  `GeoData.Place`. The subdivision, city and locality counts cover the places
  stored under the country; `:largest_cities` is ordered by population.

  ## Options

    * `:largest` - number of largest cities to include, defaults to `5`

  Returns `{:ok, %GeoData.Stats.Country{}}`, `{:error,
  %GeoData.NotFoundError{}}` for an unknown country or `{:error,
  %GeoData.ValidationError{reason: :not_a_country}}` for a place that is not a
  country.

  ## Examples

      GeoData.Stats.country("PT")
      GeoData.Stats.country("BR", largest: 10)

  """
  def country(code_or_place, opts \\ []) do
    with {:ok, opts} <- validate_country_opts(opts),
         {:ok, place} <- resolve_country(code_or_place) do
      {:ok, build_country(place, opts[:largest])}
    end
  end

  @doc """
  Returns the countries bordering a country as `GeoData.Place` records.

  Accepts an ISO 3166-1 alpha-2 code (string or atom) or a country
  `GeoData.Place`. Neighbour codes that are not stored are omitted; the full
  list of codes is always available as `place.neighbours`.

  Returns `{:ok, places}`, `{:error, %GeoData.NotFoundError{}}` for an unknown
  country or `{:error, %GeoData.ValidationError{reason: :not_a_country}}` for a
  place that is not a country.

  ## Examples

      {:ok, neighbours} = GeoData.Stats.neighbours("PT")
      Enum.map(neighbours, & &1.iso_3166_1)
      #=> ["ES", "FR"]

  """
  def neighbours(code_or_place) do
    with {:ok, place} <- resolve_country(code_or_place) do
      {:ok, resolve_neighbours(place.neighbours)}
    end
  end

  # Building

  defp build_country(place, largest) do
    counts = count_kinds(place.iso_3166_1)

    %Country{
      place: place,
      subdivisions: Map.get(counts, :subdivision, 0),
      cities: Map.get(counts, :city, 0),
      localities: Map.get(counts, :locality, 0),
      population: place.population,
      largest_cities: largest_cities(place.iso_3166_1, largest),
      neighbours: resolve_neighbours(place.neighbours)
    }
  end

  defp count_kinds(nil), do: %{}

  defp count_kinds(code) do
    GeoData.stream(where: [country: code])
    |> Enum.reduce(%{}, fn place, acc -> bump(acc, place.kind) end)
  end

  defp largest_cities(nil, _largest), do: []

  defp largest_cities(code, largest) do
    GeoData.search!(
      where: [country: code, kind: [:city]],
      order_by: {:population, :desc},
      limit: largest
    ).places
  end

  defp resolve_neighbours(codes) do
    codes
    |> Enum.map(&GeoData.country/1)
    |> Enum.flat_map(fn
      {:ok, place} -> [place]
      {:error, _error} -> []
    end)
  end

  # Resolution

  defp resolve_country(%Place{kind: :country} = place), do: {:ok, place}
  defp resolve_country(%Place{} = place), do: {:error, not_a_country(place.id)}

  defp resolve_country(code) when is_binary(code) or (is_atom(code) and not is_nil(code)) do
    case GeoData.country(code) do
      {:ok, %Place{kind: :country} = place} -> {:ok, place}
      {:ok, %Place{} = place} -> {:error, not_a_country(place.id)}
      {:error, %NotFoundError{} = error} -> {:error, error}
    end
  end

  defp resolve_country(value), do: {:error, not_a_country(value)}

  defp not_a_country(value) do
    %ValidationError{
      field: :country,
      value: value,
      reason: :not_a_country,
      expected: "an ISO 3166-1 country code or country place"
    }
  end

  # Options

  defp validate_country_opts(opts) do
    {:ok, NimbleOptions.validate!(opts, @country_schema)}
  rescue
    error in [NimbleOptions.ValidationError] ->
      {:error,
       %ValidationError{
         field: error.key || :stats,
         value: error.value,
         reason: :invalid_option,
         expected: error.message
       }}
  end

  # Helpers

  defp bump(map, key), do: Map.update(map, key, 1, &(&1 + 1))
end
