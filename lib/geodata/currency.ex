defmodule GeoData.Currency do
  @moduledoc """
  Currency metadata resolved from CLDR via `Localize.Currency`.

  Data is read at call time, so nothing is pre-translated at ingest. Names and
  symbols default to `Localize.get_locale()`; only `:en` is bundled with
  Localize, other locales must be downloaded (see
  `GeoData.Place.display_name/3`).

  ## Examples

      iex> {:ok, currency} = GeoData.Currency.get("eur")
      iex> currency.code
      "EUR"

      iex> {:ok, [currency]} = GeoData.Currency.for_country("PT")
      iex> currency.code
      "EUR"

  """

  alias GeoData.Place
  alias GeoData.UnknownCodeError

  defstruct [:code, :name, :symbol, :tender]

  @doc """
  Returns the currency for `code`.

  `code` is a case-insensitive ISO 4217 string or atom. Returns `{:ok, currency}`
  or `{:error, %GeoData.UnknownCodeError{}}`.

  ## Options

    * `:locale` - the locale for the name and symbol, defaults to
      `Localize.get_locale()`
    * `:fallback` - when `true`, fall back to the default locale if the
      requested locale has no data (defaults to `false`)

  """
  def get(code, opts \\ []) do
    locale = Keyword.get(opts, :locale, Localize.get_locale())
    fallback = Keyword.get(opts, :fallback, false)

    with {:ok, normalized} <- normalize_code(code),
         {:ok, currency} <-
           Localize.Currency.currency_for_code(normalized, locale: locale, fallback: fallback) do
      {:ok, from_localize(currency)}
    else
      _ -> {:error, %UnknownCodeError{field: :currency, value: code}}
    end
  end

  @doc """
  Same as `get/2` but returns the currency directly or raises
  `GeoData.UnknownCodeError`.
  """
  def get!(code, opts \\ []) do
    case get(code, opts) do
      {:ok, currency} -> currency
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns whether `code` is a known ISO 4217 currency.

  ## Examples

      iex> GeoData.Currency.valid?("EUR")
      true

      iex> GeoData.Currency.valid?("XYZ")
      false

  """
  def valid?(code) do
    case normalize_code(code) do
      {:ok, normalized} -> Localize.Currency.known_currency_code?(normalized)
      :error -> false
    end
  end

  @doc """
  Returns all known currency codes as strings.
  """
  def codes do
    Enum.map(Localize.Currency.known_currency_codes(), &Atom.to_string/1)
  end

  @doc """
  Returns the current currency of a country.

  `country` is a `GeoData.Place` of kind `:country`, or a country code string or
  atom. The currency is resolved from CLDR and falls back to the place's stored
  `:currency` when CLDR has no current entry. Returns `{:ok, [currency]}`, with
  an empty list when no currency is known.

  ## Examples

      iex> {:ok, [currency]} = GeoData.Currency.for_country(:US)
      iex> currency.code
      "USD"

  """
  def for_country(country, opts \\ []) do
    {territory, stored} = territory_and_currency(country)
    current = territory && Localize.Currency.current_currency_for_territory(territory)

    {:ok, load(current || stored, opts)}
  end

  defp load(nil, _opts), do: []

  defp load(code, opts) do
    case get(code, opts) do
      {:ok, currency} -> [currency]
      {:error, _} -> []
    end
  end

  defp territory_and_currency(%Place{iso_3166_1: code, currency: currency}), do: {code, currency}

  defp territory_and_currency(code)
       when (is_atom(code) and not is_nil(code)) or is_binary(code),
       do: {code, nil}

  defp territory_and_currency(_country), do: {nil, nil}

  defp from_localize(%Localize.Currency{} = currency) do
    %__MODULE__{
      code: Atom.to_string(currency.code),
      name: currency.name,
      symbol: blank(currency.symbol),
      tender: currency.tender
    }
  end

  defp normalize_code(code) when is_atom(code) and not is_nil(code) do
    {:ok, code |> Atom.to_string() |> String.upcase()}
  end

  defp normalize_code(code) when is_binary(code), do: {:ok, String.upcase(code)}
  defp normalize_code(_code), do: :error

  defp blank(""), do: nil
  defp blank(value), do: value
end
