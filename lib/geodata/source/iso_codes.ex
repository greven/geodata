defmodule GeoData.Source.IsoCodes do
  @moduledoc """
  Ingestion source for the Debian `iso-codes` package.

  Reads the package's JSON data files:

    * `iso_3166-1.json` - countries, stored as `:country` places
    * `iso_3166-2.json` - subdivisions, stored as `:subdivision` places
    * `iso_3166-3.json` - former country codes, used to enrich countries whose
      numeric code matches a withdrawn entry (`:iso_3166_3` and metadata)

  Localized names are not read from this source; display names are resolved
  from CLDR at read time via `GeoData.Place.display_name/3`.

  The files are fetched from a mirror of the Debian package and can be
  pointed at local copies with the `:files` option.
  """

  @behaviour GeoData.Source

  alias GeoData.ID
  alias GeoData.Place
  alias GeoData.IngestError
  alias GeoData.Source.File, as: SourceFile

  @base_url "https://raw.githubusercontent.com/sailfishos-mirror/iso-codes/main/data"

  @files [
    iso_3166_1: "iso_3166-1.json",
    iso_3166_2: "iso_3166-2.json",
    iso_3166_3: "iso_3166-3.json"
  ]

  @impl true
  def source, do: :iso_codes

  @impl true
  def files(_opts \\ []) do
    for {key, filename} <- @files do
      %SourceFile{
        key: key,
        filename: filename,
        url: "#{@base_url}/#{filename}",
        format: :json
      }
    end
  end

  @impl true
  def attribution do
    %{
      name: "iso-codes",
      url: "https://salsa.debian.org/iso-codes-team/iso-codes",
      license: "LGPL-2.1-or-later",
      attribution: "ISO 3166 data from the Debian iso-codes project."
    }
  end

  @doc """
  Returns the set of ISO 3166-3 (withdrawn) country `alpha_2` codes.

  Reads the `iso_3166-3` JSON file at `path`; a missing or unreadable file
  yields an empty set.
  """
  def former_country_codes(path) do
    path
    |> read_former()
    |> Map.values()
    |> Enum.map(& &1["alpha_2"])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @impl true
  def parse(paths, _opts \\ []) do
    with {:ok, country_rows} <- read_rows(paths, :iso_3166_1, "3166-1"),
         {:ok, subdivision_rows} <- read_rows(paths, :iso_3166_2, "3166-2") do
      former = former_codes(paths)

      places =
        Enum.map(country_rows, &country_place(&1, former)) ++
          Enum.map(subdivision_rows, &subdivision_place/1)

      {:ok, places}
    end
  rescue
    error in [GeoData.ValidationError] ->
      {:error, %IngestError{source: :iso_codes, reason: :parse_failed, detail: error}}
  end

  defp country_place(row, former) do
    numeric = row["numeric"]
    former_row = numeric && Map.get(former, numeric)

    metadata =
      %{}
      |> put_if(:alpha_3, row["alpha_3"])
      |> put_if(:numeric, numeric)
      |> put_if(:official_name, row["official_name"])
      |> put_if(:former, former_metadata(former_row))

    Place.new!(
      id: ID.for_country(row["alpha_2"]),
      kind: :country,
      iso_3166_1: row["alpha_2"],
      iso_3166_3: former_row && former_row["alpha_4"],
      name: row["name"],
      flag_emoji: row["flag"] || flag_emoji(row["alpha_2"]),
      metadata: metadata,
      sources: [:iso_codes]
    )
  end

  defp subdivision_place(row) do
    code = row["code"]
    country = code |> String.split("-", parts: 2) |> hd()

    Place.new!(
      id: ID.for_subdivision(code),
      kind: :subdivision,
      iso_3166_1: country,
      iso_3166_2: code,
      parent_id: ID.for_country(country),
      ancestor_ids: [ID.for_country(country)],
      name: row["name"],
      metadata: put_if(%{}, :type, row["type"]),
      sources: [:iso_codes]
    )
  end

  defp former_codes(paths) do
    case Map.fetch(paths, :iso_3166_3) do
      {:ok, path} -> read_former(path)
      :error -> %{}
    end
  end

  defp read_former(path) do
    with true <- File.exists?(path),
         {:ok, body} <- File.read(path),
         {:ok, data} <- decode(body) do
      data
      |> Map.get("3166-3", [])
      |> Enum.filter(& &1["numeric"])
      |> Map.new(&{&1["numeric"], &1})
    else
      _ -> %{}
    end
  end

  defp former_metadata(nil), do: nil

  defp former_metadata(row) do
    %{
      alpha_2: row["alpha_2"],
      alpha_3: row["alpha_3"],
      alpha_4: row["alpha_4"],
      name: row["name"],
      numeric: row["numeric"],
      withdrawal_date: row["withdrawal_date"]
    }
  end

  defp read_rows(paths, key, field) do
    path = Map.fetch!(paths, key)

    with {:ok, body} <- File.read(path),
         {:ok, data} <- decode(body) do
      {:ok, Map.get(data, field, [])}
    else
      {:error, :enoent} -> {:error, error(:missing_file, path)}
      {:error, :invalid_format} -> {:error, error(:invalid_format, path)}
      {:error, reason} -> {:error, error(:read_failed, path, reason)}
    end
  end

  defp decode(body) do
    {:ok, JSON.decode!(body)}
  rescue
    _ -> {:error, :invalid_format}
  end

  defp error(reason, path, detail \\ nil) do
    %IngestError{source: :iso_codes, file: path, reason: reason, detail: detail}
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp flag_emoji(<<a, b>>) when a in ?A..?Z and b in ?A..?Z do
    <<regional(a)::utf8, regional(b)::utf8>>
  end

  defp flag_emoji(_alpha_2), do: nil

  defp regional(letter), do: 0x1F1E6 + letter - ?A
end
