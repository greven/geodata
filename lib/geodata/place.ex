defmodule GeoData.Place do
  @moduledoc """
  A normalized geographic place.

  Places are the merged result of the ISO 3166 identity from Debian
  `iso-codes` and the place data from GeoNames. A place is one of:

    * `:country` - an ISO 3166-1 country
    * `:subdivision` - an ISO 3166-2 subdivision
    * `:city` / `:locality` - a populated place from GeoNames
    * `:feature` - any other GeoNames feature

  ## Fields

  ### Identity

    * `:id` - canonical identifier, e.g. `"ISO:US"`, `"ISO:US-CA"` or `"GN:5128581"`
    * `:kind` - the place kind (see above)
    * `:iso_3166_1` - ISO 3166-1 alpha-2 country code
    * `:iso_3166_2` - ISO 3166-2 subdivision code
    * `:iso_3166_3` - ISO 3166-3 former country code
    * `:geonames_id` - GeoNames feature id
    * `:parent_id` - canonical `:id` of the parent place
    * `:ancestor_ids` - canonical `:id`s from parent to root
    * `:sources` - sources that contributed, e.g. `[:iso_codes, :geonames]`

  ### Names

    * `:name` - canonical display name
    * `:ascii_name` - ASCII transliteration
    * `:names` - alternate names as a list of strings

  Use `display_name/3` to resolve a display name for a locale. Countries and
  subdivisions are localized from CLDR via
  `Localize.Territory.display_name/2`; other places fall back to `:name` /
  `:ascii_name`.

  ### Location

    * `:latitude` / `:longitude` - decimal degrees (WGS84)
    * `:population` - population, when known
    * `:elevation` - elevation in meters
    * `:timezone` - IANA time zone id
    * `:feature_class` / `:feature_code` - GeoNames classification; see
      `GeoData.Feature` for semantic group/class names
    * `:admin1_code` / `:admin2_code` - GeoNames administrative codes

  ### Country metadata

    * `:capital` - capital city name
    * `:flag_emoji` - Unicode flag emoji
    * `:currency` - ISO 4217 currency code; see `GeoData.Currency`
    * `:languages` - ISO 639 language codes; see `GeoData.Language`
    * `:phone_code` - international dialling prefix
    * `:tld` - country code top-level domain
    * `:continent` - GeoNames continent code (`"AF"`, `"AS"`, `"EU"`, ...)
    * `:neighbours` - ISO 3166-1 alpha-2 codes of bordering countries

  ### Provenance

    * `:metadata` - source-specific extras
    * `:updated_at` - when the place was last updated

  """

  alias GeoData.NoNameError
  alias GeoData.ValidationError

  @kinds [:country, :subdivision, :city, :locality, :feature]

  defstruct [
    :id,
    :kind,
    :iso_3166_1,
    :iso_3166_2,
    :iso_3166_3,
    :geonames_id,
    :parent_id,
    :name,
    :ascii_name,
    :latitude,
    :longitude,
    :population,
    :elevation,
    :timezone,
    :feature_class,
    :feature_code,
    :admin1_code,
    :admin2_code,
    :capital,
    :flag_emoji,
    :currency,
    :phone_code,
    :tld,
    :continent,
    :updated_at,
    ancestor_ids: [],
    sources: [],
    names: [],
    languages: [],
    neighbours: [],
    metadata: %{}
  ]

  @doc """
  Returns the supported place kinds.
  """
  def kinds, do: @kinds

  @doc """
  Builds a place from a keyword list or map.

  Returns `{:ok, place}` or `{:error, %GeoData.ValidationError{}}`.

  ## Examples

      iex> GeoData.Place.new(kind: :country, iso_3166_1: "PT")
      {:ok, %GeoData.Place{kind: :country, iso_3166_1: "PT"}}

  """
  def new(attrs \\ []) do
    attrs = Map.new(attrs)

    with :ok <- validate_kind(attrs),
         :ok <- validate_optional(attrs, :id, :binary, &is_binary/1),
         :ok <- validate_optional(attrs, :names, :list, &is_list/1),
         :ok <- validate_optional(attrs, :ancestor_ids, :list, &is_list/1),
         :ok <- validate_optional(attrs, :sources, :list, &is_list/1),
         :ok <- validate_optional(attrs, :languages, :list, &is_list/1),
         :ok <- validate_optional(attrs, :neighbours, :list, &is_list/1),
         :ok <- validate_optional(attrs, :metadata, :map, &is_map/1) do
      {:ok, struct(__MODULE__, attrs)}
    end
  end

  @doc """
  Same as `new/1` but returns the place directly or raises
  `GeoData.ValidationError`.

  ## Examples

      iex> GeoData.Place.new!(kind: :city, name: "Lisbon").name
      "Lisbon"

  """
  def new!(attrs \\ []) do
    case new(attrs) do
      {:ok, place} -> place
      {:error, error} -> raise error
    end
  end

  @doc """
  Merges two places with the same identity.

  Fields already set on `base` win over `override`; `nil` fields are filled
  from `override`. Collection fields are combined: `:names`, `:sources`,
  `:languages` and `:ancestor_ids` are unioned. `:metadata` is deep-merged with
  `base` taking precedence.

  ## Examples

      iex> base = GeoData.Place.new!(kind: :country, iso_3166_1: "PT")
      iex> override = GeoData.Place.new!(kind: :country, name: "Portugal", sources: [:geonames])
      iex> merged = GeoData.Place.merge(base, override)
      iex> merged.name
      "Portugal"

  """
  def merge(%__MODULE__{} = base, %__MODULE__{} = override) do
    fields =
      Map.merge(Map.from_struct(base), Map.from_struct(override), fn
        :metadata, base_meta, override_meta ->
          Map.merge(override_meta, base_meta)

        collection, base_values, override_values
        when collection in [:names, :sources, :languages, :ancestor_ids, :neighbours] ->
          Enum.uniq(base_values ++ override_values)

        _field, base_value, _override_value when not is_nil(base_value) ->
          base_value

        _field, _base_value, override_value ->
          override_value
      end)

    struct!(__MODULE__, fields)
  end

  @doc """
  Returns a display name for `place` in `locale`.

  `locale` defaults to `Localize.get_locale()`. Resolution order:

    1. CLDR for countries (`Localize.Territory.display_name/2`) and
       subdivisions (`Localize.Territory.Subdivision.display_name/2`)
    2. `place.name`, then `place.ascii_name`

  Localization is read-time and backed by CLDR, so GeoData stores only the
  canonical name. When the locale's CLDR data is unavailable — Localize ships
  only `:en`, other locales must be installed with
  `mix localize.download_locales` — resolution **silently falls back** to the
  canonical name instead of erroring.

  Returns `{:ok, name}` or `{:error, %GeoData.NoNameError{}}` (only when there
  is no CLDR name and neither `:name` nor `:ascii_name` is set).

  ## Options

    * `:style` - CLDR territory style, one of `:short`, `:standard` or
      `:variant` (countries only)

  ## Examples

      iex> place = GeoData.Place.new!(kind: :city, name: "Lisbon")
      iex> GeoData.Place.display_name(place, :en)
      {:ok, "Lisbon"}

      iex> place = GeoData.Place.new!(kind: :country, iso_3166_1: "PT")
      iex> GeoData.Place.display_name!(place, :en)
      "Portugal"

  """
  def display_name(place, locale \\ nil, opts \\ []) do
    locale = locale || Localize.get_locale()

    fallback_name(place, locale, opts)
  end

  @doc """
  Same as `display_name/3` but returns the name directly or raises
  `GeoData.NoNameError`.
  """
  def display_name!(place, locale \\ nil, opts \\ []) do
    case display_name(place, locale, opts) do
      {:ok, name} -> name
      {:error, error} -> raise error
    end
  end

  defp validate_kind(attrs) do
    case Map.fetch(attrs, :kind) do
      {:ok, kind} when kind in @kinds ->
        :ok

      {:ok, kind} ->
        invalid(:kind, kind, :invalid_kind, allowed_values: @kinds)

      :error ->
        invalid(:kind, nil, :missing)
    end
  end

  defp validate_optional(attrs, field, expected, fun) do
    case Map.fetch(attrs, field) do
      {:ok, value} ->
        if fun.(value), do: :ok, else: invalid(field, value, :invalid_type, expected: expected)

      :error ->
        :ok
    end
  end

  defp invalid(field, value, reason, extra \\ []) do
    {:error, struct!(ValidationError, [field: field, value: value, reason: reason] ++ extra)}
  end

  defp fallback_name(place, locale, opts) do
    style = Keyword.get(opts, :style)

    case cldr_name(place, locale, style) || place.name || place.ascii_name do
      nil -> {:error, %NoNameError{place: place, locale: locale}}
      name -> {:ok, name}
    end
  end

  defp cldr_name(%__MODULE__{kind: :subdivision, iso_3166_2: code}, locale, _style)
       when is_binary(code) do
    subdivision_display_name(code, locale)
  end

  defp cldr_name(%__MODULE__{kind: :country, iso_3166_1: code}, locale, style)
       when is_binary(code) do
    territory_display_name(code, locale, style)
  end

  defp cldr_name(_place, _locale, _style), do: nil

  defp territory_display_name(code, locale, style) do
    options = if style, do: [locale: locale, style: style], else: [locale: locale]

    case Localize.Territory.display_name(code, options) do
      {:ok, name} -> name
      _ -> nil
    end
  end

  defp subdivision_display_name(code, locale) do
    normalized = code |> String.downcase() |> String.replace("-", "")

    case Localize.Territory.Subdivision.display_name(normalized, locale: locale) do
      {:ok, name} -> name
      _ -> nil
    end
  end
end
