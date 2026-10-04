defmodule GeoData.Search.Memory do
  @moduledoc """
  In-memory `GeoData.Search` engine.

  Applies matching, filtering and ordering in memory. When the storage adapter
  exposes a text index (`candidates/2`, as the ETS adapter and DETS in `:eager`
  mode do), text queries are resolved from the index without scanning the
  dataset; adapters that also expose normalized terms
  (`get_with_terms/1`/`stream_with_terms/0`, as the ETS and DETS adapters do)
  avoid re-normalizing during matching. For `:fuzzy`, a trigram index provides
  candidates when every query token is long enough for trigram overlap to be a
  reliable superset; short tokens and `fuzziness: 2` scan instead.
  Otherwise it falls back to streaming every place through
  `GeoData.Storage.stream/0` and normalizing on the fly. This works with every
  storage adapter, including DETS and Ecto.

  ## Options

    * `:match` - `:prefix` (default, per-token prefix), `:exact`, `:token`,
      `:contains` or `:fuzzy` (typo-tolerant)
    * `:fuzziness` - maximum edits per token for `match: :fuzzy`, one of
      `0`, `1` (default) or `2`
    * `:where` - keyword list of filters: `:kind`, `:country`, `:subdivision`,
      `:continent`, `:feature_class` and `:feature_code` (raw codes/letters or
      a semantic name from `GeoData.Feature`, e.g. `:mountain`, `:lake` or
      `:landforms`), `:timezone`, `:id`, `:geonames_id`, `:population`
      (`[min:, max:]`), `:bbox` (`{min_lat, min_lon, max_lat, max_lon}`),
      `:near` (`{lat, lon, radius_m}`) and `:has_coordinates` (boolean)
    * `:order_by` - `:relevance` (default), `:name`, `:population`,
      `{field, :asc | :desc}`, or `{:distance, {lat, lon}}` (nearest first,
      places without coordinates last)
    * `:limit` - page size, default 20
    * `:offset` - page offset, default 0
    * `:count` - whether to report `:total` in the result, default `true`. Set
      to `false` to skip the total and get `total: nil` (the Ecto engine skips
      an extra `count(*)` query)
    * `:fields` - `:name`, `:ascii_name` and/or `:names` (alternate names),
      default all
    * `:search` - override the search engine for this call

  Matching is accent- and case-insensitive; a query also matches ISO codes and
  GeoNames ids exactly.

  ## Examples

      iex> GeoData.Search.Memory.search("lisbon", limit: 1)
      {:ok, %GeoData.Search.Result{}}

  """

  @behaviour GeoData.Search

  # Query tokens shorter than this skip the trigram candidate index, since
  # trigram overlap is not a reliable superset for them.
  @fuzzy_min_token 5

  alias GeoData.Search.Query
  alias GeoData.Search.Result
  alias GeoData.Storage

  @impl true
  def search(text \\ nil, opts \\ []) do
    with {:ok, query} <- Query.parse(text, opts) do
      matches = collect(query)
      total = if query.count, do: length(matches)

      places =
        matches
        |> Enum.drop(query.offset)
        |> take(query.limit)
        |> Enum.map(&elem(&1, 0))

      {:ok, %Result{places: places, total: total, limit: query.limit, offset: query.offset}}
    end
  end

  defp take(places, :infinity), do: places
  defp take(places, limit), do: Enum.take(places, limit)

  @impl true
  def stream(text \\ nil, opts \\ []) do
    case Query.parse(text, opts) do
      {:ok, query} -> do_stream(query)
      {:error, error} -> raise error
    end
  end

  defp do_stream(query) do
    query
    |> matching_places()
    |> Stream.map(&elem(&1, 0))
  end

  defp collect(query) do
    query
    |> matching_places()
    |> Enum.to_list()
    |> Query.sort(query)
  end

  defp matching_places(query) do
    query
    |> source()
    |> Stream.filter(fn {place, _terms} -> Query.filters?(place, query) end)
    |> Stream.flat_map(fn {place, terms} ->
      case Query.match(place, query, terms) do
        {:ok, score} -> [{place, score}]
        :nomatch -> []
      end
    end)
  end

  # Uses the storage text index when available, else scans every place. Terms
  # come precomputed from indexed adapters and are `nil` otherwise.
  defp source(query) do
    case candidates(query) do
      nil -> Storage.stream_with_terms()
      ids -> ids |> Enum.uniq() |> Enum.flat_map(&fetch/1)
    end
  end

  defp candidates(%{tokens: []}), do: nil
  defp candidates(%{match: :contains}), do: nil
  defp candidates(%{match: :fuzzy, tokens: tokens, fuzziness: 1}), do: fuzzy_candidates(tokens)
  defp candidates(%{match: :fuzzy}), do: nil
  defp candidates(%{tokens: tokens, match: match}), do: Storage.candidates(tokens, match)

  # Trigram overlap is not a guaranteed superset for very short tokens, so only
  # use the index when every token is long enough; otherwise scan.
  defp fuzzy_candidates(tokens) do
    if Enum.all?(tokens, &(String.length(&1) >= @fuzzy_min_token)) do
      Storage.candidates(tokens, :fuzzy)
    else
      nil
    end
  end

  defp fetch(id) do
    case Storage.get_with_terms(id) do
      {:ok, place, terms} -> [{place, terms}]
      _ -> []
    end
  end
end
