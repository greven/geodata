defmodule GeoData.Fuzzy do
  @moduledoc false

  # Bounded Damerau-Levenshtein distance (optimal string alignment), used by
  # `match: :fuzzy` search. Strings are compared by Unicode codepoint and the
  # computation bails out with `:too_far` as soon as a row exceeds `max`, so
  # distant pairs stay cheap.

  @doc """
  Returns the edit distance between `a` and `b` when it is at most `max`,
  otherwise `:too_far`.

  Uses the optimal string alignment variant, so adjacent transpositions count
  as a single edit.
  """
  def distance(a, b, max) when is_binary(a) and is_binary(b) and is_integer(max) and max >= 0 do
    length_a = String.length(a)
    length_b = String.length(b)

    cond do
      a == b -> 0
      abs(length_a - length_b) > max -> :too_far
      length_a == 0 -> if length_b <= max, do: length_b, else: :too_far
      length_b == 0 -> if length_a <= max, do: length_a, else: :too_far
      true -> run(String.to_charlist(a), String.to_charlist(b), max)
    end
  end

  @doc """
  Returns whether `a` and `b` are within `max` edits.
  """
  def within?(a, b, max), do: distance(a, b, max) != :too_far

  defp run(a, b, max) do
    a = List.to_tuple(a)
    b = List.to_tuple(b)
    len_b = tuple_size(b)
    row0 = List.to_tuple(Enum.to_list(0..len_b))

    try do
      {row, _row2} =
        Enum.reduce(1..tuple_size(a), {row0, nil}, fn i, {prev, prev2} ->
          curr = next_row(a, b, i, len_b, prev, prev2, max)
          {curr, prev}
        end)

      elem(row, len_b)
    catch
      :too_far -> :too_far
    end
  end

  defp next_row(a, b, i, len_b, prev, prev2, max) do
    ac = elem(a, i - 1)
    prev_ac = if prev2, do: elem(a, i - 2), else: nil

    row =
      1..len_b
      |> Enum.reduce([i], fn j, acc ->
        left = hd(acc)
        up = elem(prev, j)
        diagonal = elem(prev, j - 1)
        bc = elem(b, j - 1)
        cost = if ac == bc, do: 0, else: 1

        value = min(up + 1, min(left + 1, diagonal + cost))

        value =
          if prev2 && j >= 2 && prev_ac == bc && ac == elem(b, j - 2) do
            min(value, elem(prev2, j - 2) + 1)
          else
            value
          end

        [value | acc]
      end)
      |> :lists.reverse()
      |> List.to_tuple()

    if row |> Tuple.to_list() |> Enum.min() > max, do: throw(:too_far), else: row
  end
end
