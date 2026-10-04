if Code.ensure_loaded?(Ecto.Query) do
  defmodule GeoData.Search.Ecto do
    @moduledoc """
    SQL pushdown `GeoData.Search` engine.

    Translates a query into an `Ecto.Query` so the database does the filtering,
    matching, ordering and paging, using indexes on `geodata_places`. Works
    with any Ecto SQL backend through the repo configured for
    `GeoData.Storage.Ecto` (or `GeoData.Search.Ecto` directly):

        config :geodata, search: GeoData.Search.Ecto
        config :geodata, GeoData.Storage.Ecto, repo: MyApp.Repo

    Text matching uses the precomputed, indexable `search_name`,
    `search_ascii` and `search_alternates` columns written by the storage
    adapter, so it stays accent- and case-insensitive and consistent with
    `GeoData.Search.Memory`. For `:relevance`, results are ranked by
    code/name match strength, then population (zeros last), then name, so the
    ordering follows `GeoData.Search.Memory` (the exact score values are not
    reproduced in SQL).

    Proximity is pushed down too: `where: [near: {lat, lon, radius_m}]` and
    `order_by: {:distance, {lat, lon}}` become a bounding-box prefilter plus a
    portable haversine expression.

    Fuzzy matching (`match: :fuzzy`) uses PostgreSQL's `pg_trgm` extension when
    it is installed — the bundled migration installs it and adds GIN trigram indexes
    — and returns a validation error otherwise. For `search/2`, `fuzziness` maps
    to `pg_trgm.word_similarity_threshold` (`0`/`1`/`2` → `1.0`/`0.6`/`0.4`);
    `stream/2` uses the server's configured threshold.

    Prefer this engine for large datasets (the `:all` tier); use
    `GeoData.Search.Memory` for smaller in-memory stores.

    By default each search also runs a `count(*)` over the same filter to report
    `:total`. Pass `count: false` to skip it and get `total: nil`, which halves
    the work when you only need the page.
    """

    @behaviour GeoData.Search

    import Ecto.Query

    alias GeoData.Distance
    alias GeoData.Search.Query
    alias GeoData.Search.Result
    alias GeoData.Storage.Ecto.Place, as: Row
    alias GeoData.Storage.Ecto.Postgres
    alias GeoData.ValidationError

    @batch_size 1_000

    @earth_radius 6_371_008.8

    # Haversine term (inside the outer sqrt), duplicated in the CASE guard so
    # floating point error cannot push `asin/1` out of its domain.
    @haversine_term "(pow(sin((? - ?) * pi() / 360.0), 2) + cos(? * pi() / 180.0) * cos(? * pi() / 180.0) * pow(sin((? - ?) * pi() / 360.0), 2))"

    @haversine "#{@earth_radius} * 2 * asin(sqrt(CASE WHEN #{@haversine_term} > 1.0 THEN 1.0 ELSE #{@haversine_term} END))"

    @impl true
    def search(text \\ nil, opts \\ []) do
      with {:ok, query} <- Query.parse(text, opts),
           :ok <- supported?(query) do
        run(query)
      end
    end

    # Fuzzy matching reads `pg_trgm.word_similarity_threshold`, so run it in a
    # transaction where that setting can be scoped to `fuzziness`.
    defp run(%{match: :fuzzy} = query) do
      case repo().transaction(fn ->
             set_fuzzy_threshold(query.fuzziness)
             execute(query)
           end) do
        {:ok, result} -> result
        {:error, error} -> {:error, error}
      end
    end

    defp run(query), do: execute(query)

    defp execute(query) do
      base = base_query(query)
      total = if query.count, do: repo().aggregate(base, :count)

      places =
        base
        |> order(query)
        |> paginate(query)
        |> repo().all()
        |> Enum.map(&decode/1)

      {:ok, %Result{places: places, total: total, limit: query.limit, offset: query.offset}}
    end

    defp set_fuzzy_threshold(fuzziness) do
      repo().query!(
        "SELECT set_config('pg_trgm.word_similarity_threshold', $1, true)",
        [fuzzy_threshold(fuzziness)]
      )
    end

    defp fuzzy_threshold(0), do: "1.0"
    defp fuzzy_threshold(1), do: "0.6"
    defp fuzzy_threshold(2), do: "0.4"

    defp paginate(query, %{limit: :infinity, offset: 0}), do: query
    defp paginate(query, %{limit: :infinity, offset: offset}), do: offset(query, ^offset)

    defp paginate(query, %{limit: limit, offset: offset}) do
      query |> limit(^limit) |> offset(^offset)
    end

    @impl true
    def stream(text \\ nil, opts \\ []) do
      case Query.parse(text, opts) do
        {:ok, query} ->
          case supported?(query) do
            :ok -> do_stream(query)
            {:error, error} -> raise error
          end

        {:error, error} ->
          raise error
      end
    end

    # Fuzzy matching is pushed down when PostgreSQL has the pg_trgm extension;
    # otherwise fail clearly. (`stream/2` uses the server's configured
    # `word_similarity_threshold`, so `fuzziness` is honored by `search/2`.)
    defp supported?(%{match: :fuzzy}) do
      if Postgres.pg_trgm?(repo()), do: :ok, else: {:error, unsupported(:fuzzy)}
    end

    defp supported?(_query), do: :ok

    defp unsupported(feature) do
      %ValidationError{
        field: feature,
        value: feature,
        reason: :invalid_option,
        expected:
          "#{feature} is not supported by GeoData.Search.Ecto; " <>
            "use GeoData.Search.Memory for this query"
      }
    end

    defp base_query(query) do
      from(p in Row)
      |> where(^filters_dynamic(query))
      |> where(^match_dynamic(query))
    end

    # Filters

    defp filters_dynamic(%{where: where}) do
      Enum.reduce(where, dynamic(true), fn {key, value}, acc ->
        dynamic([p], ^acc and ^filter_dynamic(key, value))
      end)
    end

    defp filter_dynamic(:kind, values),
      do: dynamic([p], p.kind in ^Enum.map(values, &to_string/1))

    defp filter_dynamic(:country, values), do: dynamic([p], p.iso_3166_1 in ^values)
    defp filter_dynamic(:subdivision, values), do: dynamic([p], p.iso_3166_2 in ^values)
    defp filter_dynamic(:continent, values), do: dynamic([p], p.continent in ^values)
    defp filter_dynamic(:feature_class, values), do: dynamic([p], p.feature_class in ^values)
    defp filter_dynamic(:feature_code, values), do: dynamic([p], p.feature_code in ^values)
    defp filter_dynamic(:timezone, values), do: dynamic([p], p.timezone in ^values)
    defp filter_dynamic(:id, values), do: dynamic([p], p.id in ^values)
    defp filter_dynamic(:geonames_id, values), do: dynamic([p], p.geonames_id in ^values)
    defp filter_dynamic(:population, {min, max}), do: population_dynamic(min, max)

    defp filter_dynamic(:has_coordinates, true),
      do: dynamic([p], not is_nil(p.latitude) and not is_nil(p.longitude))

    defp filter_dynamic(:has_coordinates, false),
      do: dynamic([p], is_nil(p.latitude) or is_nil(p.longitude))

    defp filter_dynamic(:bbox, {min_lat, min_lon, max_lat, max_lon}) do
      if min_lon > max_lon do
        dynamic(
          [p],
          p.latitude >= ^min_lat and p.latitude <= ^max_lat and
            (p.longitude >= ^min_lon or p.longitude <= ^max_lon)
        )
      else
        dynamic(
          [p],
          p.latitude >= ^min_lat and p.latitude <= ^max_lat and
            p.longitude >= ^min_lon and p.longitude <= ^max_lon
        )
      end
    end

    defp filter_dynamic(:near, {lat, lon, radius}) do
      dynamic(
        [p],
        not is_nil(p.latitude) and not is_nil(p.longitude) and
          ^bbox_dynamic(lat, lon, radius) and ^near_dynamic(lat, lon, radius)
      )
    end

    # Bounding box around the radius, so the (non-indexable) haversine only
    # runs on a small subset. `min_lon > max_lon` signals an antimeridian wrap.
    defp bbox_dynamic(lat, lon, radius) do
      {min_lat, min_lon, max_lat, max_lon} = Distance.bounding_box({lat, lon}, radius)

      if min_lon > max_lon do
        dynamic(
          [p],
          p.latitude >= ^min_lat and p.latitude <= ^max_lat and
            (p.longitude >= ^min_lon or p.longitude <= ^max_lon)
        )
      else
        dynamic(
          [p],
          p.latitude >= ^min_lat and p.latitude <= ^max_lat and
            p.longitude >= ^min_lon and p.longitude <= ^max_lon
        )
      end
    end

    defp near_dynamic(lat, lon, radius) do
      dynamic(
        [p],
        fragment(
          @haversine,
          ^lat,
          p.latitude,
          ^lat,
          p.latitude,
          ^lon,
          p.longitude,
          ^lat,
          p.latitude,
          ^lat,
          p.latitude,
          ^lon,
          p.longitude
        ) <= ^radius
      )
    end

    defp population_dynamic(min, max) do
      cond do
        is_nil(min) and is_nil(max) -> dynamic(true)
        is_nil(min) -> dynamic([p], p.population <= ^max)
        is_nil(max) -> dynamic([p], p.population >= ^min)
        true -> dynamic([p], p.population >= ^min and p.population <= ^max)
      end
    end

    # Text and code matching

    defp match_dynamic(%{text: "", raw: ""}), do: dynamic(true)

    defp match_dynamic(%{text: ""}), do: dynamic(false)

    defp match_dynamic(query) do
      Enum.reduce([text_dynamic(query), code_dynamic(query)], dynamic(false), fn condition, acc ->
        dynamic([p], ^acc or ^condition)
      end)
    end

    defp text_dynamic(%{match: :exact} = query), do: exact_dynamic(query.text, query.fields)

    defp text_dynamic(%{tokens: tokens, match: mode, fields: fields}) do
      Enum.reduce(tokens, dynamic(true), fn token, acc ->
        dynamic([p], ^acc and ^token_dynamic(token, mode, fields))
      end)
    end

    defp exact_dynamic(text, fields) do
      Enum.reduce(fields, dynamic(false), fn
        :name, acc -> dynamic([p], ^acc or p.search_name == ^text)
        :ascii_name, acc -> dynamic([p], ^acc or p.search_ascii == ^text)
        :names, acc -> dynamic([p], ^acc or ^alternate_dynamic(text, :exact))
      end)
    end

    defp token_dynamic(token, mode, fields) do
      Enum.reduce(fields, dynamic(false), fn field, acc ->
        dynamic([p], ^acc or ^field_dynamic(field, token, mode))
      end)
    end

    defp field_dynamic(:names, token, mode), do: alternate_dynamic(token, mode)

    defp field_dynamic(:name, token, :prefix) do
      dynamic(
        [p],
        like(p.search_name, ^(token <> "%")) or like(p.search_name, ^("% " <> token <> "%"))
      )
    end

    defp field_dynamic(:ascii_name, token, :prefix) do
      dynamic(
        [p],
        like(p.search_ascii, ^(token <> "%")) or like(p.search_ascii, ^("% " <> token <> "%"))
      )
    end

    defp field_dynamic(:name, token, :token) do
      dynamic(
        [p],
        p.search_name == ^token or like(p.search_name, ^("% " <> token)) or
          like(p.search_name, ^("% " <> token <> " %"))
      )
    end

    defp field_dynamic(:ascii_name, token, :token) do
      dynamic(
        [p],
        p.search_ascii == ^token or like(p.search_ascii, ^("% " <> token)) or
          like(p.search_ascii, ^("% " <> token <> " %"))
      )
    end

    defp field_dynamic(:name, token, :contains),
      do: dynamic([p], like(p.search_name, ^("%" <> token <> "%")))

    defp field_dynamic(:ascii_name, token, :contains),
      do: dynamic([p], like(p.search_ascii, ^("%" <> token <> "%")))

    # `? <% ?` is pg_trgm's word-similarity operator; it is backed by the GIN
    # trigram indexes added by the migration.
    defp field_dynamic(:name, token, :fuzzy),
      do: dynamic([p], fragment("? <% ?", ^token, p.search_name))

    defp field_dynamic(:ascii_name, token, :fuzzy),
      do: dynamic([p], fragment("? <% ?", ^token, p.search_ascii))

    defp alternate_dynamic(token, :exact) do
      dynamic(
        [p],
        p.search_alternates == ^token or like(p.search_alternates, ^(token <> " %")) or
          like(p.search_alternates, ^("% " <> token)) or
          like(p.search_alternates, ^("% " <> token <> " %"))
      )
    end

    defp alternate_dynamic(token, :prefix) do
      dynamic(
        [p],
        like(p.search_alternates, ^(token <> "%")) or
          like(p.search_alternates, ^("% " <> token <> "%"))
      )
    end

    defp alternate_dynamic(token, :token) do
      dynamic(
        [p],
        p.search_alternates == ^token or like(p.search_alternates, ^("% " <> token)) or
          like(p.search_alternates, ^("% " <> token <> " %"))
      )
    end

    defp alternate_dynamic(token, :contains),
      do: dynamic([p], like(p.search_alternates, ^("%" <> token <> "%")))

    defp alternate_dynamic(token, :fuzzy),
      do: dynamic([p], fragment("? <% ?", ^token, p.search_alternates))

    defp code_dynamic(%{raw: ""}), do: dynamic(false)

    defp code_dynamic(%{raw: raw}) do
      upcase = String.upcase(raw)

      conditions =
        [
          dynamic([p], p.kind == "country" and p.iso_3166_1 == ^upcase),
          dynamic([p], p.iso_3166_2 == ^upcase)
        ] ++ geonames_dynamic(raw)

      Enum.reduce(conditions, dynamic(false), fn condition, acc ->
        dynamic([p], ^acc or ^condition)
      end)
    end

    defp geonames_dynamic(raw) do
      case Integer.parse(raw) do
        {id, ""} -> [dynamic([p], p.geonames_id == ^id)]
        _ -> []
      end
    end

    # Ordering

    defp order(query, %{order: {:relevance, _}, match: :fuzzy} = q) do
      query
      |> order_by([p], desc: fragment("similarity(?, ?)", p.search_name, ^q.text))
      |> order_by([p], desc: coalesce(p.population, 0))
      |> order_by([p], asc: fragment("lower(?)", p.name))
      |> order_by([p], asc: p.id)
    end

    defp order(query, %{order: {:relevance, _}} = q) do
      query
      |> order_by(
        [p],
        desc:
          fragment(
            """
            CASE
              WHEN (? = 'country' AND ? = ?) OR ? = ? OR ? = ? THEN 4
              WHEN ? = ? THEN 3
              WHEN ? = ? THEN 2
              WHEN ? LIKE ? THEN 1
              ELSE 0
            END
            """,
            p.kind,
            p.iso_3166_1,
            ^q.code_upcase,
            p.iso_3166_2,
            ^q.code_upcase,
            p.geonames_id,
            ^q.geoname_id,
            p.search_name,
            ^q.text,
            p.search_ascii,
            ^q.text,
            p.search_name,
            ^(q.text <> "%")
          )
      )
      |> order_by([p], desc: coalesce(p.population, 0))
      |> order_by([p], asc: fragment("lower(?)", p.name))
      |> order_by([p], asc: p.id)
    end

    defp order(query, %{order: {:distance, {lat, lon}}}) do
      query
      |> order_by(
        [p],
        asc:
          fragment("CASE WHEN ? IS NULL OR ? IS NULL THEN 1 ELSE 0 END", p.latitude, p.longitude)
      )
      |> order_by(
        [p],
        asc:
          fragment(
            @haversine,
            ^lat,
            p.latitude,
            ^lat,
            p.latitude,
            ^lon,
            p.longitude,
            ^lat,
            p.latitude,
            ^lat,
            p.latitude,
            ^lon,
            p.longitude
          )
      )
      |> order_by([p], asc: p.id)
    end

    defp order(query, %{order: {field, direction}}) do
      query
      |> apply_order(field, direction)
      |> order_by([p], asc: p.id)
    end

    defp apply_order(q, :name, :asc), do: order_by(q, [p], asc: fragment("lower(?)", p.name))
    defp apply_order(q, :name, :desc), do: order_by(q, [p], desc: fragment("lower(?)", p.name))
    defp apply_order(q, :kind, :asc), do: order_by(q, [p], asc: p.kind)
    defp apply_order(q, :kind, :desc), do: order_by(q, [p], desc: p.kind)
    defp apply_order(q, :population, :asc), do: order_by(q, [p], asc: coalesce(p.population, 0))
    defp apply_order(q, :population, :desc), do: order_by(q, [p], desc: coalesce(p.population, 0))
    defp apply_order(q, :latitude, :asc), do: order_by(q, [p], asc: p.latitude)
    defp apply_order(q, :latitude, :desc), do: order_by(q, [p], desc: p.latitude)
    defp apply_order(q, :longitude, :asc), do: order_by(q, [p], asc: p.longitude)
    defp apply_order(q, :longitude, :desc), do: order_by(q, [p], desc: p.longitude)
    defp apply_order(q, :elevation, :asc), do: order_by(q, [p], asc: p.elevation)
    defp apply_order(q, :elevation, :desc), do: order_by(q, [p], desc: p.elevation)
    defp apply_order(q, :updated_at, :asc), do: order_by(q, [p], asc: p.updated_at)
    defp apply_order(q, :updated_at, :desc), do: order_by(q, [p], desc: p.updated_at)

    # Streaming

    defp do_stream(query) do
      Stream.resource(
        fn -> :start end,
        fn
          :done ->
            {:halt, :done}

          cursor ->
            case fetch_after(cursor, query) do
              [] -> {:halt, :done}
              rows -> {Enum.map(rows, &decode/1), List.last(rows).id}
            end
        end,
        fn _ -> :ok end
      )
    end

    defp fetch_after(cursor, query) do
      q = base_query(query)
      q = if cursor == :start, do: q, else: where(q, [p], p.id > ^cursor)
      q |> order_by([p], asc: p.id) |> limit(^@batch_size) |> repo().all()
    end

    defp decode(%Row{data: data}) when is_binary(data),
      do: :erlang.binary_to_term(data, [:safe])

    @doc false
    def repo do
      Keyword.get(Application.get_env(:geodata, __MODULE__, []), :repo) ||
        Keyword.get(Application.get_env(:geodata, GeoData.Storage.Ecto, []), :repo) ||
        raise ArgumentError,
              "no Ecto repo configured; set config :geodata, #{inspect(GeoData.Storage.Ecto)}, repo: MyApp.Repo"
    end
  end
end
