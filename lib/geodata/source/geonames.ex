defmodule GeoData.Source.Geonames do
  @moduledoc """
  Ingestion source for [GeoNames](https://www.geonames.org/).

  Reads the tab-separated exports:

    * `countryInfo.txt` - country metadata, merged into ISO 3166-1 countries
      as `:capital`, `:currency`, `:phone_code`, `:tld`, `:continent`,
      `:population`, `:languages`, `:neighbours` and `:geonames_id`
    * `cities1000.zip` (`:cities`) or `allCountries.zip` (`:all`) - populated
      places, streamed as `:city`, `:locality` or `:feature` places. The
      `alternatenames` column is split into `:names`, a list of strings, for
      search

  Country records are returned eagerly so they can be merged by id; the large
  place file is returned as a lazy stream and never loaded into memory as a
  whole.

  Subdivisions are **not** enriched from GeoNames. GeoNames' `admin1` codes are
  its own administrative codes and do not match ISO 3166-2 codes for most
  countries, so joining them by code would corrupt subdivision identity.
  Subdivisions come from `iso-codes` only.
  """

  @behaviour GeoData.Source

  alias GeoData.ID
  alias GeoData.Place
  alias GeoData.Source.File, as: SourceFile

  @base_url "https://download.geonames.org/export/dump"

  @identity_fields 19
  @place_fields 19

  @impl true
  def source, do: :geonames

  @impl true
  def files(opts \\ []) do
    places = places_filename(opts)

    [
      %SourceFile{
        key: :geonames_country_info,
        filename: "countryInfo.txt",
        url: "#{@base_url}/countryInfo.txt",
        format: :tsv
      },
      %SourceFile{
        key: :geonames_places,
        filename: places,
        url: "#{@base_url}/#{Path.rootname(places)}.zip",
        format: :tsv,
        archive: :zip
      }
    ]
  end

  @impl true
  def parse(paths, _opts \\ []) do
    identity = country_places(paths[:geonames_country_info])

    {:ok, Stream.concat(identity, place_stream(paths[:geonames_places]))}
  end

  @impl true
  def attribution do
    %{
      name: "GeoNames",
      url: "https://www.geonames.org/",
      license: "CC BY 4.0",
      attribution:
        "This dataset includes data from GeoNames (https://www.geonames.org/), licensed under CC BY 4.0."
    }
  end

  defp places_filename(opts) do
    case Keyword.get(opts, :dataset, :base) do
      :all -> "allCountries.txt"
      _ -> "cities1000.txt"
    end
  end

  defp country_places(path) do
    path
    |> line_stream()
    |> Stream.reject(&comment?/1)
    |> Enum.map(&country_place/1)
  end

  defp place_stream(path) do
    path
    |> line_stream()
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&place/1)
  end

  defp country_place(line) do
    [
      iso,
      _iso3,
      _numeric,
      fips,
      name,
      capital,
      area,
      population,
      continent,
      tld,
      currency,
      cname,
      phone,
      _format,
      _regex,
      languages,
      geonameid,
      neighbours | _
    ] =
      pad(line, @identity_fields)

    Place.new!(
      id: ID.for_country(iso),
      kind: :country,
      iso_3166_1: iso,
      name: name,
      capital: blank(capital),
      currency: blank(currency),
      phone_code: blank(phone),
      tld: blank(tld),
      continent: blank(continent),
      population: integer(population),
      languages: split_languages(languages),
      neighbours: split_neighbours(neighbours),
      geonames_id: integer(geonameid),
      metadata: compact(%{fips: blank(fips), area: float(area), currency_name: blank(cname)}),
      sources: [:geonames]
    )
  end

  defp place(line) do
    [
      geonames_id,
      name,
      ascii,
      alternates,
      lat,
      lon,
      fclass,
      fcode,
      country,
      _cc2,
      admin1,
      admin2,
      _admin3,
      _admin4,
      population,
      elevation,
      dem,
      timezone,
      modified
    ] =
      pad(line, @place_fields)

    Place.new!(
      id: ID.for_geonames(integer(geonames_id)),
      kind: place_kind(fclass, fcode),
      geonames_id: integer(geonames_id),
      name: name,
      ascii_name: blank(ascii),
      names: split_names(alternates, name, blank(ascii)),
      latitude: float(lat),
      longitude: float(lon),
      feature_class: blank(fclass),
      feature_code: blank(fcode),
      iso_3166_1: blank(country),
      admin1_code: blank(admin1),
      admin2_code: blank(admin2),
      population: integer(population),
      elevation: integer(elevation) || integer(dem),
      timezone: blank(timezone),
      parent_id: parent(country),
      ancestor_ids: ancestors(country),
      updated_at: date(modified),
      sources: [:geonames]
    )
  end

  defp place_kind("P", "PPLX"), do: :locality
  defp place_kind("P", "PPL" <> _), do: :city
  defp place_kind("P", _), do: :locality
  defp place_kind(_, _), do: :feature

  defp parent(""), do: nil
  defp parent(country), do: ID.for_country(country)

  defp ancestors(""), do: []
  defp ancestors(country), do: [ID.for_country(country)]

  defp line_stream(path) do
    path
    |> File.stream!()
    |> Stream.map(&strip_newline/1)
  end

  defp strip_newline(line) do
    line |> String.trim_trailing("\n") |> String.trim_trailing("\r")
  end

  defp pad(line, size) do
    fields = String.split(line, "\t")
    fields ++ List.duplicate("", max(size - length(fields), 0))
  end

  defp comment?(line), do: line == "" or String.starts_with?(line, "#")

  defp split_languages(""), do: []

  defp split_languages(value),
    do: value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp split_neighbours(""), do: []

  defp split_neighbours(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.upcase/1)
  end

  defp split_names("", _name, _ascii), do: []

  defp split_names(value, name, ascii) do
    known = [name, ascii] |> Enum.reject(&is_nil/1) |> Enum.map(&String.downcase/1)

    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.reject(&(String.downcase(&1) in known))
  end

  defp blank(""), do: nil
  defp blank(value), do: value

  defp integer(""), do: nil

  defp integer(value) do
    case Integer.parse(value) do
      {number, _} -> number
      :error -> nil
    end
  end

  defp float(""), do: nil

  defp float(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> nil
    end
  end

  defp date(""), do: nil

  defp date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
