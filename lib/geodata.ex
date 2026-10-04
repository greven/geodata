defmodule GeoData do
  @external_resource readme = Path.join([__DIR__, "..", "README.md"])
  @moduledoc File.read!(readme)

  alias GeoData.Boundary
  alias GeoData.ID
  alias GeoData.Place
  alias GeoData.Search
  alias GeoData.Storage

  alias GeoData.NotFoundError
  alias GeoData.ValidationError

  @doc """
  Returns a lazy stream over every stored place.
  """
  def all, do: Storage.stream()

  @doc """
  Fetches a place by canonical id.

  Returns `{:ok, place}` or `{:error, %GeoData.NotFoundError{}}`.
  """
  def fetch(id) do
    case Storage.get(id) do
      {:ok, place} -> {:ok, place}
      {:error, :not_found} -> {:error, %NotFoundError{id: id}}
    end
  end

  @doc """
  Same as `fetch/1` but returns the place directly or raises
  `GeoData.NotFoundError`.
  """
  def fetch!(id) do
    case fetch(id) do
      {:ok, place} -> place
      {:error, error} -> raise error
    end
  end

  @doc """
  Stores a batch of places, keyed by `GeoData.Place.id`.
  """
  def put_many(places), do: Storage.put_many(places)

  @doc """
  Deletes a place by canonical id.
  """
  def delete(id), do: Storage.delete(id)

  @doc """
  Returns the number of stored places.
  """
  def count, do: Storage.count()

  @doc """
  Fetches a country by its ISO 3166-1 alpha-2 code.

  The code is case-insensitive and may be a string or atom: `"PT"`, `"pt"`,
  `:pt` and `:PT` are equivalent.
  """
  def country(code), do: fetch(ID.for_country(code))

  @doc """
  Same as `country/1` but returns the place directly or raises
  `GeoData.NotFoundError`.
  """
  def country!(code), do: fetch!(ID.for_country(code))

  @doc """
  Fetches a subdivision by its ISO 3166-2 code.

  The code is case-insensitive and may be a string or atom: `"US-CA"`,
  `"us-ca"` and `:"US-CA"` are equivalent.
  """
  def subdivision(code), do: fetch(ID.for_subdivision(code))

  @doc """
  Same as `subdivision/1` but returns the place directly or raises
  `GeoData.NotFoundError`.
  """
  def subdivision!(code), do: fetch!(ID.for_subdivision(code))

  @doc """
  Fetches a place by its GeoNames feature id.

  Accepts an integer or a numeric string.
  """
  def place(geonames_id), do: fetch(ID.for_geonames(geonames_id))

  @doc """
  Same as `place/1` but returns the place directly or raises
  `GeoData.NotFoundError`.
  """
  def place!(geonames_id), do: fetch!(ID.for_geonames(geonames_id))

  @doc """
  Searches stored places by text and/or filters.

  The text argument is optional, so options may be passed on their own.
  Returns `{:ok, %GeoData.Search.Result{}}` or `{:error, exception}`.

  ## Examples

      GeoData.search("lisbon")
      GeoData.search("sao", where: [kind: [:city]], order_by: {:population, :desc})
      GeoData.search(where: [kind: [:country], continent: "EU"], order_by: :name)

  Pass `match: :fuzzy` (with `fuzziness: 0..2`) for typo-tolerant matching:

      GeoData.search("lisbom", match: :fuzzy)

  """
  def search(text \\ nil, opts \\ []), do: Search.search(text, opts)

  @doc """
  Same as `search/2` but returns the result directly or raises.
  """
  def search!(text \\ nil, opts \\ []), do: Search.search!(text, opts)

  @doc """
  Returns the places nearest to a coordinate, ordered by distance.

  Equivalent to `search/2` with `order_by: {:distance, {lat, lon}}`; when
  `:radius` (in metres) is given, only places within it are returned. Places
  without coordinates are never returned.

  ## Options

  Accepts the search options (`:where`, `:limit`, `:match`, ...) plus:

    * `:radius` - only return places within this many metres

  ## Examples

      GeoData.nearest(38.71667, -9.13333)
      GeoData.nearest(38.71667, -9.13333, radius: 50_000, limit: 10)

  """
  def nearest(lat, lon, opts \\ []) do
    {limit, opts} = Keyword.pop(opts, :limit, 5)
    {radius, opts} = Keyword.pop(opts, :radius)

    where =
      case radius do
        nil -> Keyword.put(Keyword.get(opts, :where, []), :has_coordinates, true)
        radius -> Keyword.put(Keyword.get(opts, :where, []), :near, {lat, lon, radius})
      end

    opts
    |> Keyword.put(:where, where)
    |> Keyword.put(:order_by, {:distance, {lat, lon}})
    |> Keyword.put(:limit, limit)
    |> search()
  end

  @doc """
  Same as `nearest/3` but returns the result directly or raises.
  """
  def nearest!(lat, lon, opts \\ []) do
    case nearest(lat, lon, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns the places nearest to a place or point, ordered by distance.

  The origin may be a `GeoData.Place` with coordinates, a `{lat, lon}` tuple,
  a coordinate map or a canonical id such as `"GN:2267057"` (fetched first).
  It then behaves like `nearest/3`, accepting the same options (`:radius`,
  `:limit`, `:where`, ...).

  Returns `{:error, %GeoData.NotFoundError{}}` for an unknown id or
  `{:error, %GeoData.ValidationError{reason: :invalid_type}}` when the origin
  has no coordinates (for example every country and subdivision, which come
  from `iso-codes` and carry no location).

  ## Examples

      GeoData.near("GN:2267057")
      GeoData.near({38.71667, -9.13333}, radius: 50_000, limit: 10)
      GeoData.near(GeoData.place!(2_267_057))

  """
  def near(origin, opts \\ []) do
    with {:ok, {lat, lon}} <- origin_point(origin) do
      nearest(lat, lon, opts)
    end
  end

  @doc """
  Same as `near/2` but returns the result directly or raises.
  """
  def near!(origin, opts \\ []) do
    case near(origin, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Lazily streams matching places.
  """
  def stream(text \\ nil, opts \\ []), do: Search.stream(text, opts)

  @doc """
  Returns the places whose boundaries contain the coordinate `{lat, lon}`.

  Boundaries must be fetched and loaded first (see `GeoData.Boundary` and the
  `:boundaries` option); otherwise `{:ok, []}` is returned. When boundaries are
  loaded, the result is ordered from coarse to fine (country before
  subdivision). Options:

    * `:kind` / `:kinds` - restrict the levels to `:country`, `:subdivision`
      or a list of both

  ## Examples

      GeoData.containing(40.20, -8.42)
      GeoData.containing(40.20, -8.42, kind: :country)

  """
  def containing(lat, lon, opts \\ []), do: Boundary.containing(lat, lon, opts)

  @doc """
  Same as `containing/3` but returns the places directly or raises.
  """
  def containing!(lat, lon, opts \\ []) do
    case containing(lat, lon, opts) do
      {:ok, places} -> places
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns the boundary for a place or canonical id.

  Returns `{:ok, %GeoData.Boundary{}}` or `{:error, :not_found}`.
  """
  def boundary(place_or_id), do: Boundary.get(place_or_id)

  @doc """
  Same as `boundary/1` but returns the boundary directly or raises
  `GeoData.NotFoundError`.
  """
  def boundary!(place_or_id) do
    case boundary(place_or_id) do
      {:ok, boundary} -> boundary
      {:error, :not_found} -> raise GeoData.NotFoundError, id: place_or_id
    end
  end

  @doc """
  Returns the loaded boundaries, optionally filtered by `:kind` or `:kinds`.

  ## Examples

      GeoData.boundaries()
      GeoData.boundaries(kind: :country)

  """
  def boundaries(opts \\ []), do: Boundary.boundaries(opts)

  @doc """
  Streams the loaded boundaries; see `boundaries/1`.
  """
  def stream_boundaries(opts \\ []), do: Stream.map(boundaries(opts), & &1)

  @doc """
  Returns whether the `{lat, lon}` coordinate lies within a boundary.

  Accepts a `%GeoData.Boundary{}`, a `%GeoData.Place{}` or a canonical id.
  Unknown ids return `false`.
  """
  def within?(point, %Boundary{} = boundary), do: Boundary.within?(point, boundary)

  def within?(point, %Place{} = place), do: within?(point, place.id)

  def within?(point, id) when is_binary(id) or is_atom(id) do
    case boundary(id) do
      {:ok, boundary} -> Boundary.within?(point, boundary)
      _ -> false
    end
  end

  @doc """
  Returns a localized display name for a place or canonical id.

  Accepts a `GeoData.Place` or a canonical id such as `"ISO:PT"`. See
  `GeoData.Place.display_name/3` for the resolution order and options
  (`:style`). Returns `{:ok, name}` or `{:error, exception}`.

  ## Examples

      GeoData.display_name("ISO:PT", :en)
      GeoData.display_name(place, :en, style: :short)

  """
  def display_name(place_or_id, locale \\ nil, opts \\ []) do
    with {:ok, place} <- resolve_place(place_or_id) do
      Place.display_name(place, locale, opts)
    end
  end

  @doc """
  Same as `display_name/3` but returns the name directly or raises.
  """
  def display_name!(place_or_id, locale \\ nil, opts \\ []) do
    case display_name(place_or_id, locale, opts) do
      {:ok, name} -> name
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns every country as a list of `GeoData.Place`, ordered by name.

  Accepts search options (e.g. `:where`, `:order_by`, `:limit`) which are
  merged with the country filter.

  ## Examples

      GeoData.countries()
      GeoData.countries(where: [continent: "EU"])

  """
  def countries(opts \\ []), do: list_places(:country, [], opts)

  @doc """
  Lazily streams every country.
  """
  def stream_countries(opts \\ []), do: stream_places(:country, [], opts)

  @doc """
  Returns subdivisions as a list of `GeoData.Place`, ordered by name.

  When a country code is given, only that country's subdivisions are returned.

  ## Examples

      GeoData.subdivisions()
      GeoData.subdivisions("US")

  """
  def subdivisions(country \\ nil, opts \\ []),
    do: list_places(:subdivision, country_where(country), opts)

  @doc """
  Lazily streams subdivisions, optionally scoped to a country code.
  """
  def stream_subdivisions(country \\ nil, opts \\ []),
    do: stream_places(:subdivision, country_where(country), opts)

  @doc """
  Returns geographic features as a list of `GeoData.Place`, ordered by name.

  Features are everything that is not a populated place. The `:feature_code`
  and `:feature_class` filters accept the semantic names from
  `GeoData.Feature`, so landforms can be searched without knowing GeoNames
  codes:

      GeoData.features(where: [feature_code: :mountain])
      GeoData.features(where: [feature_class: :landforms], limit: 10)
      GeoData.features(where: [feature_code: [:lake, :waterfall], country: "PT"])

  Accepts the usual search options; `:kind` defaults to `[:feature, :locality]`
  and can be overridden through `:where`.

  ## Examples

      GeoData.features(where: [feature_code: :lake])

  """
  def features(opts \\ []) do
    search!(nil, feature_opts(opts)).places
  end

  @doc """
  Lazily streams geographic features. See `features/1`.
  """
  def stream_features(opts \\ []), do: stream(nil, feature_opts(opts))

  @doc """
  Returns the available semantic feature-code groups; see `GeoData.Feature`.
  """
  def feature_groups, do: GeoData.Feature.groups()

  @doc """
  Returns the available feature-class aliases; see `GeoData.Feature`.
  """
  def feature_classes, do: GeoData.Feature.classes()

  defp resolve_place(%Place{} = place), do: {:ok, place}
  defp resolve_place(id) when is_binary(id), do: fetch(id)

  defp origin_point({lat, lon}) when is_number(lat) and is_number(lon),
    do: {:ok, {lat, lon}}

  defp origin_point(%{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon),
       do: {:ok, {lat, lon}}

  defp origin_point(%Place{} = place), do: {:error, invalid_origin(place.id)}

  defp origin_point(id) when is_binary(id) do
    with {:ok, place} <- fetch(id), do: origin_point(place)
  end

  defp origin_point(other), do: {:error, invalid_origin(other)}

  defp invalid_origin(value) do
    %ValidationError{
      field: :origin,
      value: value,
      reason: :invalid_type,
      expected: "{latitude, longitude}"
    }
  end

  defp list_places(kind, extra, opts) do
    result = search!(nil, query_opts(kind, extra, opts))
    result.places
  end

  defp stream_places(kind, extra, opts), do: stream(nil, query_opts(kind, extra, opts))

  defp country_where(nil), do: []
  defp country_where(country), do: [country: [country]]

  defp query_opts(kind, extra, opts) do
    where =
      opts
      |> Keyword.get(:where, [])
      |> Keyword.put(:kind, kind)
      |> Keyword.merge(extra)

    opts
    |> Keyword.put_new(:order_by, :name)
    |> Keyword.put_new(:limit, :infinity)
    |> Keyword.put(:where, where)
  end

  defp feature_opts(opts) do
    where =
      opts
      |> Keyword.get(:where, [])
      |> Keyword.put_new(:kind, [:feature, :locality])

    opts
    |> Keyword.put_new(:order_by, :name)
    |> Keyword.put_new(:limit, :infinity)
    |> Keyword.put(:where, where)
  end
end
