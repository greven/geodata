defmodule GeoData.Normalize do
  @moduledoc """
  Text normalization used for accent- and case-insensitive search.

  Folds a string to lowercase, strips accents and punctuation and collapses
  whitespace, so `"São Paulo"` and `"sao paulo"` normalize to the same value.
  Pure ASCII input takes a cheaper path that skips Unicode decomposition and
  property regexes.
  """

  @ascii ~r/[^a-z0-9]+/
  @unicode ~r/[^\p{L}\p{N}]+/u

  @doc """
  Normalizes `text` for matching. `nil` normalizes to `""`.

  ## Examples

      iex> GeoData.Normalize.normalize("São Paulo")
      "sao paulo"

      iex> GeoData.Normalize.normalize("  New-York  ")
      "new york"

  """
  def normalize(nil), do: ""

  def normalize(text) when is_binary(text) do
    if ascii?(text), do: normalize_ascii(text), else: normalize_unicode(text)
  end

  defp normalize_ascii(text) do
    text
    |> String.downcase()
    |> String.replace(@ascii, " ")
    |> String.trim()
  end

  defp normalize_unicode(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(@unicode, " ")
    |> String.trim()
  end

  defp ascii?(<<char, rest::binary>>) when char < 128, do: ascii?(rest)
  defp ascii?(<<>>), do: true
  defp ascii?(_text), do: false
end
