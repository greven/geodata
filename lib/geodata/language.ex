defmodule GeoData.Language do
  @moduledoc """
  Language metadata resolved from CLDR via `Localize.Language`.

  Data is read at call time, so nothing is pre-translated at ingest. Names
  default to `Localize.get_locale()`; only `:en` is bundled with Localize, other
  locales must be downloaded (see `GeoData.Place.display_name/3`).

  CLDR has no country-to-languages mapping, so `for_country/2` reads the
  `:languages` populated on a country place by GeoNames enrichment; it returns
  an empty list on a `:base` store.

  ## Examples

      iex> {:ok, language} = GeoData.Language.get("en")
      iex> language.name
      "English"

  """

  alias GeoData.Place
  alias GeoData.UnknownCodeError

  defstruct [:code, :name]

  @doc """
  Returns the language for `code` with its localized name.

  `code` is an ISO 639 or BCP 47 language tag string or atom. Returns
  `{:ok, language}` or `{:error, %GeoData.UnknownCodeError{}}`.

  ## Options

    * `:locale` - the locale for the name, defaults to `Localize.get_locale()`
    * `:fallback` - when `true`, fall back to the default locale if the
      requested locale has no data (defaults to `false`)

  """
  def get(code, opts \\ []) do
    locale = Keyword.get(opts, :locale, Localize.get_locale())
    fallback = Keyword.get(opts, :fallback, false)

    with {:ok, tag} <- Localize.validate_locale(code),
         {:ok, name} <- Localize.Language.display_name(tag, locale: locale, fallback: fallback) do
      {:ok, %__MODULE__{code: canonical_code(tag, code), name: name}}
    else
      _ -> {:error, %UnknownCodeError{field: :language, value: code}}
    end
  end

  @doc """
  Same as `get/2` but returns the language directly or raises
  `GeoData.UnknownCodeError`.
  """
  def get!(code, opts \\ []) do
    case get(code, opts) do
      {:ok, language} -> language
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns whether `code` resolves to a known language.

  ## Examples

      iex> GeoData.Language.valid?("en")
      true

      iex> GeoData.Language.valid?("zz")
      false

  """
  def valid?(code), do: match?({:ok, _}, get(code))

  @doc """
  Returns the language codes with names available in `opts`' locale.

  Returns an empty list when the locale data is unavailable.
  """
  def codes(opts \\ []) do
    case Localize.Language.languages_for(opts) do
      {:ok, codes} -> codes
      {:error, _} -> []
    end
  end

  @doc """
  Returns the languages of a country.

  `country` is a `GeoData.Place`, or a country code string or atom (looked up in
  storage). Codes come from the place's GeoNames-enriched `:languages`; an
  unknown country or a place without language data yields an empty list.

  ## Examples

      iex> place = GeoData.Place.new!(kind: :country, languages: ["pt", "gl"])
      iex> {:ok, languages} = GeoData.Language.for_country(place)
      iex> Enum.map(languages, & &1.code)
      ["pt", "gl"]

  """
  def for_country(country, opts \\ [])

  def for_country(%Place{} = place, opts), do: {:ok, names(place, opts)}

  def for_country(code, opts) when (is_atom(code) and not is_nil(code)) or is_binary(code) do
    case GeoData.country(code) do
      {:ok, place} -> {:ok, names(place, opts)}
      {:error, _} -> {:ok, []}
    end
  end

  def for_country(_country, _opts), do: {:ok, []}

  defp names(%Place{languages: codes}, opts) do
    codes
    |> List.wrap()
    |> Enum.flat_map(fn code ->
      case get(code, opts) do
        {:ok, language} -> [language]
        {:error, _} -> []
      end
    end)
  end

  defp canonical_code(tag, fallback) do
    case Localize.LanguageTag.to_string(tag) do
      string when is_binary(string) -> string
      _ -> to_string(fallback)
    end
  end
end
