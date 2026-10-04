defmodule GeoData.Search.Query do
  @moduledoc false

  alias GeoData.Distance
  alias GeoData.Fuzzy
  alias GeoData.Place
  alias GeoData.ValidationError

  @match_modes [:exact, :prefix, :token, :contains, :fuzzy]
  @order_fields [
    :relevance,
    :name,
    :population,
    :latitude,
    :longitude,
    :elevation,
    :updated_at,
    :kind
  ]
  @fields [:name, :ascii_name, :names]

  @field_weights %{name: 1.0, ascii_name: 0.9, names: 0.5}

  @schema NimbleOptions.new!(
            match: [type: {:in, @match_modes}, default: :prefix],
            fuzziness: [type: {:in, [0, 1, 2]}, default: 1],
            where: [type: :keyword_list, default: []],
            order_by: [
              type:
                {:or,
                 [
                   {:in, @order_fields},
                   {:tuple, [{:in, @order_fields}, {:in, [:asc, :desc]}]},
                   {:tuple, [{:in, [:distance]}, :any]}
                 ]},
              default: :relevance
            ],
            limit: [type: {:or, [:pos_integer, {:in, [:infinity]}]}, default: 20],
            offset: [type: :non_neg_integer, default: 0],
            count: [type: :boolean, default: true],
            locale: [type: :atom, default: nil],
            fields: [type: {:list, {:in, @fields}}, default: @fields]
          )

  @doc """
  Validates search options and builds a normalized query.
  """
  def parse(text, opts) do
    validated = NimbleOptions.validate!(opts, @schema)
    normalized = normalize(text)

    with {:ok, filters} <- parse_filters(validated[:where]),
         {:ok, order} <- parse_order(validated[:order_by]) do
      raw = raw(text)
      {code_upcase, geoname_id} = code_query(raw)

      {:ok,
       %{
         text: normalized,
         raw: raw,
         code_upcase: code_upcase,
         geoname_id: geoname_id,
         tokens: tokens(normalized),
         match: validated[:match],
         fuzziness: validated[:fuzziness],
         where: filters,
         order: order,
         limit: validated[:limit],
         offset: validated[:offset],
         count: validated[:count],
         locale: validated[:locale],
         fields: validated[:fields]
       }}
    end
  rescue
    error in [NimbleOptions.ValidationError] -> {:error, to_validation_error(error)}
  end

  @doc """
  Normalizes a string for matching: accent-folded, lowercased, punctuation
  stripped and whitespace collapsed.
  """
  def normalize(text), do: GeoData.Normalize.normalize(text)

  @doc """
  Returns whether a place satisfies the query's `where` filters.
  """
  def filters?(place, %{where: filters}) do
    Enum.all?(filters, fn {key, value} -> match_filter?(place, key, value) end)
  end

  @doc """
  Returns `{:ok, score}` when the place matches the query text, or `:nomatch`.

  When `terms` are given (see `terms/1`), they are used directly instead of
  normalizing the place's names again.
  """
  def match(place, query), do: match(place, query, nil)

  def match(_place, %{text: "", raw: ""}, _terms), do: {:ok, 0}

  def match(_place, %{text: ""}, _terms), do: :nomatch

  def match(place, query, terms) do
    case code_score(place, query) do
      nil -> text_match(place, query, terms)
      score -> {:ok, score}
    end
  end

  defp text_match(place, query, terms) do
    fields = Enum.sort_by(query.fields, &Map.get(@field_weights, &1, 1.0), :desc)
    best_score(place, fields, query, terms)
  end

  # Fields are ordered by descending weight, so the first field that matches
  # also yields the highest possible score.
  defp best_score(_place, [], _query, _terms), do: :nomatch

  defp best_score(place, [field | rest], query, terms) do
    case field_scores(place, field, query, terms) do
      [] -> best_score(place, rest, query, terms)
      scores -> {:ok, Enum.max(scores)}
    end
  end

  @doc """
  Precomputes the normalized search terms for a place: a map with `:name`,
  `:ascii_name` and `:names`, ready for `match/3`.
  """
  def terms(place) do
    %{
      name: normalize(place.name),
      ascii_name: normalize(place.ascii_name),
      names:
        place.names
        |> Enum.map(&normalize/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
    }
  end

  @doc """
  Sorts `{place, score}` matches according to the query's ordering.
  """
  def sort(matches, %{order: {:distance, reference}}) do
    Enum.sort_by(matches, fn {place, _score} -> {distance(place, reference), place.id} end)
  end

  def sort(matches, %{order: order}) do
    Enum.sort(matches, fn {p1, s1}, {p2, s2} -> before?(p1, s1, p2, s2, order) end)
  end

  # Matching

  defp field_scores(place, field, query, nil) do
    place
    |> Map.get(field)
    |> name_scores(query)
    |> scale(Map.get(@field_weights, field, 1.0))
  end

  defp field_scores(_place, field, query, terms) do
    terms
    |> Map.get(field)
    |> normalized_scores(query)
    |> scale(Map.get(@field_weights, field, 1.0))
  end

  defp scale(scores, 1.0), do: scores
  defp scale(scores, weight), do: Enum.map(scores, &(&1 * weight))

  defp normalized_scores(values, query) when is_list(values),
    do: Enum.flat_map(values, &normalized_scores(&1, query))

  defp normalized_scores(value, query) when is_binary(value) do
    case match_score(value, query) do
      nil -> []
      score -> [score]
    end
  end

  defp normalized_scores(_value, _query), do: []

  defp name_scores(value, query) when is_binary(value) do
    case match_score(normalize(value), query) do
      nil -> []
      score -> [score]
    end
  end

  defp name_scores(names, query) when is_list(names) do
    Enum.flat_map(names, &name_scores(&1, query))
  end

  defp name_scores(_value, _query), do: []

  defp match_score(value, %{match: :exact, text: text}), do: if(value == text, do: 100)

  defp match_score(value, %{match: :prefix, tokens: tokens}),
    do: if(token_prefix?(value, tokens), do: 70)

  defp match_score(value, %{match: :token, tokens: tokens}),
    do: if(token_equal?(value, tokens), do: 50)

  defp match_score(value, %{match: :contains, tokens: tokens}),
    do: if(token_contains?(value, tokens), do: 30)

  defp match_score(value, %{match: :fuzzy, tokens: tokens, fuzziness: max}),
    do: fuzzy_score(value, tokens, max)

  defp token_prefix?(value, tokens) do
    words = String.split(value, " ", trim: true)
    Enum.all?(tokens, fn token -> Enum.any?(words, &String.starts_with?(&1, token)) end)
  end

  defp token_equal?(value, tokens) do
    words = String.split(value, " ", trim: true)
    Enum.all?(tokens, &(&1 in words))
  end

  defp token_contains?(value, tokens) do
    Enum.all?(tokens, &String.contains?(value, &1))
  end

  # Fuzzy matching requires every query token to be within `max` edits of some
  # word; the score falls as the worst token gets further, so closer matches
  # outrank looser ones and all sit below :prefix (70) and above :contains (30).
  defp fuzzy_score(_value, [], _max), do: nil

  defp fuzzy_score(value, tokens, max) do
    words = String.split(value, " ", trim: true)

    case worst_distance(tokens, words, max) do
      :nomatch -> nil
      distance -> 60 - 10 * distance
    end
  end

  defp worst_distance(tokens, words, max) do
    Enum.reduce_while(tokens, 0, fn token, worst ->
      case best_distance(token, words, max) do
        :nomatch -> {:halt, :nomatch}
        distance -> {:cont, max(worst, distance)}
      end
    end)
  end

  defp best_distance(token, words, max) do
    words
    |> Enum.map(&Fuzzy.distance(token, &1, max))
    |> Enum.reject(&(&1 == :too_far))
    |> case do
      [] -> :nomatch
      distances -> Enum.min(distances)
    end
  end

  defp code_score(_place, %{raw: ""}), do: nil

  defp code_score(place, %{code_upcase: upcase, geoname_id: geoname_id}) do
    cond do
      place.kind == :country and place.iso_3166_1 == upcase ->
        110

      place.iso_3166_2 == upcase ->
        110

      is_integer(geoname_id) and place.geonames_id == geoname_id ->
        110

      true ->
        nil
    end
  end

  # Ordering

  defp before?(p1, s1, p2, s2, {:relevance, _}) do
    {-s1, -population(p1), name_key(p1), p1.id} <=
      {-s2, -population(p2), name_key(p2), p2.id}
  end

  defp before?(p1, _s1, p2, _s2, {field, :asc}) do
    {order_value(p1, field), p1.id} <= {order_value(p2, field), p2.id}
  end

  defp before?(p1, _s1, p2, _s2, {field, :desc}) do
    descending?(order_value(p1, field), order_value(p2, field), p1.id, p2.id)
  end

  defp descending?(v1, v2, id1, id2) do
    cond do
      v1 > v2 -> true
      v1 < v2 -> false
      true -> id1 <= id2
    end
  end

  defp order_value(place, :name), do: name_key(place)
  defp order_value(place, :kind), do: to_string(place.kind)
  defp order_value(place, :updated_at), do: place.updated_at || ~D[0001-01-01]
  defp order_value(place, field), do: Map.get(place, field) || 0

  defp population(place), do: place.population || 0

  defp distance(%{latitude: lat, longitude: lon}, reference)
       when is_number(lat) and is_number(lon) do
    Distance.between({lat, lon}, reference)
  end

  defp distance(_place, _reference), do: :infinity

  defp name_key(place) do
    (place.name || place.ascii_name || "") |> String.downcase()
  end

  defp normalize_order(order) when is_atom(order), do: {order, default_dir(order)}
  defp normalize_order({field, direction}), do: {field, direction}

  defp parse_order({:distance, {lat, lon}}) when is_number(lat) and is_number(lon),
    do: {:ok, {:distance, {lat, lon}}}

  defp parse_order({:distance, point}) do
    {:error,
     %ValidationError{
       field: :order_by,
       value: point,
       reason: :invalid_option,
       expected: "a {latitude, longitude} tuple for :distance ordering"
     }}
  end

  defp parse_order(order), do: {:ok, normalize_order(order)}

  defp default_dir(:relevance), do: :desc
  defp default_dir(:population), do: :desc
  defp default_dir(_field), do: :asc

  # Filters

  defp parse_filters(where) do
    Enum.reduce_while(where, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case normalize_filter(key, value) do
        {:ok, filter} -> {:cont, {:ok, Map.put(acc, elem(filter, 0), elem(filter, 1))}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp normalize_filter(:kind, value) do
    kinds = listify(value)

    case Enum.reject(kinds, &(&1 in Place.kinds())) do
      [] -> {:ok, {:kind, kinds}}
      [bad | _] -> {:error, invalid(bad, :invalid_kind, allowed_values: Place.kinds())}
    end
  end

  defp normalize_filter(key, value)
       when key in [:country, :subdivision, :continent] do
    {:ok, {key, value |> listify() |> Enum.map(&upcase/1)}}
  end

  defp normalize_filter(:feature_class, value) do
    case feature_classes(value) do
      {:ok, classes} ->
        {:ok, {:feature_class, classes}}

      :error ->
        {:error,
         invalid(value, :invalid_option,
           expected: "a GeoNames class letter or one of #{inspect(GeoData.Feature.classes())}"
         )}
    end
  end

  defp normalize_filter(:feature_code, value) do
    case feature_codes(value) do
      {:ok, codes} ->
        {:ok, {:feature_code, codes}}

      :error ->
        {:error,
         invalid(value, :invalid_option,
           expected: "a GeoNames feature code or one of #{inspect(GeoData.Feature.groups())}"
         )}
    end
  end

  defp normalize_filter(key, value) when key in [:timezone, :id] do
    {:ok, {key, listify(value)}}
  end

  defp normalize_filter(:near, {lat, lon, radius})
       when is_number(lat) and is_number(lon) and is_number(radius) do
    {:ok, {:near, {lat, lon, radius}}}
  end

  defp normalize_filter(:has_coordinates, value) when is_boolean(value) do
    {:ok, {:has_coordinates, value}}
  end

  defp normalize_filter(:geonames_id, value) do
    case Enum.reduce_while(listify(value), {:ok, []}, fn item, {:ok, acc} ->
           case normalize_integer(item) do
             {:ok, integer} -> {:cont, {:ok, [integer | acc]}}
             :error -> {:halt, :error}
           end
         end) do
      {:ok, ids} -> {:ok, {:geonames_id, Enum.reverse(ids)}}
      :error -> {:error, invalid(value, :invalid_type, expected: :integer)}
    end
  end

  defp normalize_filter(:population, value) when is_list(value) do
    with {:ok, min} <- optional_integer(value[:min]),
         {:ok, max} <- optional_integer(value[:max]) do
      {:ok, {:population, {min, max}}}
    end
  end

  defp normalize_filter(:bbox, {min_lat, min_lon, max_lat, max_lon})
       when is_number(min_lat) and is_number(min_lon) and is_number(max_lat) and
              is_number(max_lon) do
    {:ok, {:bbox, {min_lat, min_lon, max_lat, max_lon}}}
  end

  defp normalize_filter(key, value) do
    {:error,
     invalid({key, value}, :invalid_option, expected: "unknown or invalid filter #{inspect(key)}")}
  end

  defp match_filter?(place, :kind, kinds), do: place.kind in kinds
  defp match_filter?(place, :country, codes), do: upcase(place.iso_3166_1) in codes
  defp match_filter?(place, :subdivision, codes), do: upcase(place.iso_3166_2) in codes
  defp match_filter?(place, :continent, continents), do: upcase(place.continent) in continents
  defp match_filter?(place, :feature_class, classes), do: upcase(place.feature_class) in classes
  defp match_filter?(place, :feature_code, codes), do: upcase(place.feature_code) in codes
  defp match_filter?(place, :timezone, zones), do: place.timezone in zones
  defp match_filter?(place, :id, ids), do: place.id in ids
  defp match_filter?(place, :geonames_id, ids), do: place.geonames_id in ids

  defp match_filter?(place, :population, {min, max}),
    do: population_between?(place.population, min, max)

  defp match_filter?(place, :near, {lat, lon, radius}) do
    is_number(place.latitude) and is_number(place.longitude) and
      Distance.within?(place, {lat, lon}, radius)
  end

  defp match_filter?(place, :has_coordinates, true),
    do: is_number(place.latitude) and is_number(place.longitude)

  defp match_filter?(place, :has_coordinates, false),
    do: not (is_number(place.latitude) and is_number(place.longitude))

  defp match_filter?(place, :bbox, {min_lat, min_lon, max_lat, max_lon}) do
    is_number(place.latitude) and is_number(place.longitude) and
      place.latitude >= min_lat and place.latitude <= max_lat and
      longitude_in?(place.longitude, min_lon, max_lon)
  end

  defp longitude_in?(lon, min_lon, max_lon) when min_lon > max_lon,
    do: lon >= min_lon or lon <= max_lon

  defp longitude_in?(lon, min_lon, max_lon), do: lon >= min_lon and lon <= max_lon

  defp population_between?(nil, nil, nil), do: true
  defp population_between?(nil, _min, _max), do: false

  defp population_between?(population, min, max) do
    (is_nil(min) or population >= min) and (is_nil(max) or population <= max)
  end

  # Helpers

  defp raw(nil), do: ""
  defp raw(text) when is_binary(text), do: text |> String.trim() |> String.downcase()

  defp code_query(""), do: {"", nil}

  defp code_query(raw) do
    {String.upcase(raw), geoname_id(raw)}
  end

  defp geoname_id(raw) do
    case Integer.parse(raw) do
      {id, ""} -> if Integer.to_string(id) == raw, do: id
      _ -> nil
    end
  end

  defp tokens(""), do: []
  defp tokens(normalized), do: String.split(normalized, " ", trim: true)

  defp listify(value) when is_list(value), do: value
  defp listify(value), do: [value]

  defp feature_codes(value) do
    value
    |> listify()
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case feature_code(item) do
        {:ok, codes} -> {:cont, {:ok, acc ++ codes}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp feature_code(item), do: GeoData.Feature.codes(item)

  defp feature_classes(value) do
    value
    |> listify()
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case feature_class(item) do
        {:ok, classes} -> {:cont, {:ok, acc ++ classes}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp feature_class(item), do: GeoData.Feature.classes(item)

  defp upcase(nil), do: nil
  defp upcase(value) when is_atom(value), do: value |> Atom.to_string() |> String.upcase()
  defp upcase(value) when is_binary(value), do: String.upcase(value)

  defp optional_integer(nil), do: {:ok, nil}
  defp optional_integer(value) when is_integer(value), do: {:ok, value}
  defp optional_integer(value), do: {:error, invalid(value, :invalid_type, expected: :integer)}

  defp normalize_integer(value) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value) when is_binary(value) do
    case value |> String.trim() |> Integer.parse() do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp normalize_integer(_value), do: :error

  defp to_validation_error(%NimbleOptions.ValidationError{} = error) do
    invalid(error.key || :search, :invalid_option, value: error.value, expected: error.message)
  end

  defp invalid(value, reason, opts) do
    struct!(
      ValidationError,
      [field: :where, value: value, reason: reason] ++ opts
    )
  end
end
