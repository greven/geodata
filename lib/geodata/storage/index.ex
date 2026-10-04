defmodule GeoData.Storage.Index do
  @moduledoc false

  # Shared text index used by the in-memory (ETS) and DETS storage adapters.
  #
  # Two structures are maintained:
  #
  #   * a word-token index, `{token, id}` in an `:ordered_set`, used for the
  #     `:prefix`, `:token` and `:exact` match modes;
  #   * a trigram index, `{trigram, id}` in an `:ordered_set`, used to produce a
  #     candidate superset for `:fuzzy` matching. Trigrams are generated from
  #     the padded word tokens (see `token_trigrams/1`).
  #
  # An `id => keys` map backs each index so a place's entries can be removed
  # when it is updated or deleted.
  #
  # `backend` is `:ets` or `:dets`; both expose the same `insert/2`, `delete/2`,
  # `lookup/2`, `match_object/2` and `next/2` functions.
  #
  # Fuzzy candidates are only a prefilter: `GeoData.Search.Memory` still applies
  # the exact bounded Damerau-Levenshtein distance, and only asks for candidates
  # when the trigram overlap is a reliable superset (see `Search.Memory`).

  alias GeoData.Place
  alias GeoData.Search.Query

  @pad "##"

  @doc """
  Adds or replaces the index entries for `place`.
  """
  def put(backend, names, %Place{} = place, terms) do
    terms = terms || Query.terms(place)

    delete(backend, names, place.id)

    tokens = tokens(place, terms)
    trigrams = trigrams(word_tokens(terms))

    backend.insert(names.tokens, {place.id, tokens})
    backend.insert(names.trigrams, {place.id, trigrams})

    Enum.each(tokens, fn token ->
      backend.insert(names.index, {{token, place.id}, true})
    end)

    Enum.each(trigrams, fn trigram ->
      backend.insert(names.trigram_index, {{trigram, place.id}, true})
    end)

    :ok
  end

  @doc """
  Removes the index entries for `id`.
  """
  def delete(backend, names, id) do
    remove(backend, names.tokens, names.index, id)
    remove(backend, names.trigrams, names.trigram_index, id)
    :ok
  end

  @doc """
  Returns the ids whose index entries satisfy `match`.

  `:fuzzy` returns a trigram-overlap candidate set; the other modes use the
  word-token index.
  """
  def candidates(backend, names, tokens, :fuzzy), do: fuzzy(backend, names.trigram_index, tokens)

  def candidates(backend, names, tokens, match),
    do: intersect(backend, names.index, tokens, match)

  @doc """
  Returns the word tokens for `place`, given its precomputed `terms`.
  """
  def tokens(%Place{} = place, terms) do
    (word_tokens(terms) ++
       code_tokens(place.iso_3166_1) ++
       code_tokens(place.iso_3166_2) ++
       geonames_tokens(place.geonames_id))
    |> Enum.uniq()
  end

  defp word_tokens(terms) do
    [terms.name, terms.ascii_name | terms.names]
    |> Enum.flat_map(&String.split(&1, " ", trim: true))
  end

  # Index maintenance

  defp remove(backend, id_table, index_table, id) do
    case backend.lookup(id_table, id) do
      [{^id, keys}] ->
        Enum.each(keys, fn key -> backend.delete(index_table, {key, id}) end)
        backend.delete(id_table, id)

      _ ->
        :ok
    end
  end

  # Candidate lookup

  defp intersect(_backend, _index, [], _match), do: []

  defp intersect(backend, index, tokens, match) do
    tokens
    |> Enum.map(&MapSet.new(ids_for(backend, index, &1, match)))
    |> Enum.reduce(&MapSet.intersection/2)
    |> MapSet.to_list()
  end

  defp fuzzy(_backend, _index, []), do: []

  defp fuzzy(backend, index, tokens) do
    tokens
    |> Enum.map(&MapSet.new(trigram_ids(backend, index, &1)))
    |> Enum.reduce(&MapSet.intersection/2)
    |> MapSet.to_list()
  end

  defp trigram_ids(backend, index, token) do
    token
    |> token_trigrams()
    |> Enum.flat_map(&match_ids(backend, index, &1))
    |> Enum.uniq()
  end

  defp ids_for(backend, index, token, :prefix), do: prefix_ids(backend, index, token)

  defp ids_for(backend, index, token, match) when match in [:token, :exact],
    do: match_ids(backend, index, token)

  defp ids_for(_backend, _index, _token, _match), do: []

  defp prefix_ids(backend, index, prefix) do
    backend.next(index, {prefix, ""})
    |> Stream.unfold(fn
      :"$end_of_table" ->
        nil

      {token, id} = key ->
        if String.starts_with?(token, prefix), do: {id, backend.next(index, key)}, else: nil
    end)
  end

  defp match_ids(backend, index, key) do
    backend.match_object(index, {{key, :_}, :_})
    |> Enum.map(fn {{_key, id}, _value} -> id end)
  end

  # Trigram derivation: pad the token so short words still yield trigrams, then
  # slide a window of three graphemes.
  defp trigrams(tokens) do
    tokens
    |> Enum.flat_map(&token_trigrams/1)
    |> Enum.uniq()
  end

  defp token_trigrams(token) do
    token
    |> then(&(@pad <> &1 <> @pad))
    |> String.graphemes()
    |> sliding()
  end

  defp sliding([a, b, c | rest]), do: [a <> b <> c | sliding([b, c | rest])]
  defp sliding(_graphemes), do: []

  defp code_tokens(nil), do: []

  defp code_tokens(code) do
    code |> String.downcase() |> String.replace("-", " ") |> String.split(" ", trim: true)
  end

  defp geonames_tokens(id) when is_integer(id), do: [Integer.to_string(id)]
  defp geonames_tokens(_id), do: []
end
