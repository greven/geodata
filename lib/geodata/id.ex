defmodule GeoData.ID do
  @moduledoc """
  Canonical identifiers for `GeoData.Place`.

  Every place has a canonical id built from its strongest identity:

    * `"ISO:PT"` - an ISO 3166-1 country (alpha-2)
    * `"ISO:US-CA"` - an ISO 3166-2 subdivision
    * `"GN:5128581"` - a GeoNames feature

  Code-based lookups are derived from these ids, so no secondary indexes are
  needed to fetch a place by ISO code or GeoNames id.

  Codes are normalized: lookups are case-insensitive, ignore surrounding
  whitespace, and accept atoms.

  """

  @doc """
  Returns the canonical id for a country alpha-2 code.

  Accepts a string or atom, case-insensitively.

  ## Examples

      iex> GeoData.ID.for_country("PT")
      "ISO:PT"

      iex> GeoData.ID.for_country("pt")
      "ISO:PT"

      iex> GeoData.ID.for_country(:pt)
      "ISO:PT"

  """
  def for_country(code) when is_binary(code) or (is_atom(code) and not is_nil(code)) do
    "ISO:" <> normalize_code(code)
  end

  @doc """
  Returns the canonical id for an ISO 3166-2 subdivision code.

  Accepts a string or atom, case-insensitively. The country and subdivision
  parts are separated by a hyphen.

  ## Examples

      iex> GeoData.ID.for_subdivision("US-CA")
      "ISO:US-CA"

      iex> GeoData.ID.for_subdivision("us-ca")
      "ISO:US-CA"

      iex> GeoData.ID.for_subdivision(:"US-CA")
      "ISO:US-CA"

  """
  def for_subdivision(code) when is_binary(code) or (is_atom(code) and not is_nil(code)) do
    "ISO:" <> normalize_code(code)
  end

  @doc """
  Returns the canonical id for a GeoNames feature id.

  Accepts an integer or a numeric string.

  ## Examples

      iex> GeoData.ID.for_geonames(5128581)
      "GN:5128581"

      iex> GeoData.ID.for_geonames("5128581")
      "GN:5128581"

  """
  def for_geonames(id) when is_integer(id), do: "GN:" <> Integer.to_string(id)

  def for_geonames(id) when is_binary(id) do
    case id |> String.trim() |> Integer.parse() do
      {value, ""} -> "GN:" <> Integer.to_string(value)
      _ -> raise ArgumentError, "invalid GeoNames id: #{inspect(id)}"
    end
  end

  @doc """
  Parses a canonical id.

  ## Examples

      iex> GeoData.ID.parse("ISO:US-CA")
      {:ok, {:iso, "US-CA"}}

      iex> GeoData.ID.parse("iso:us-ca")
      {:ok, {:iso, "US-CA"}}

      iex> GeoData.ID.parse(:"ISO:PT")
      {:ok, {:iso, "PT"}}

      iex> GeoData.ID.parse("GN:5128581")
      {:ok, {:geonames, 5128581}}

      iex> GeoData.ID.parse("nope")
      {:error, :invalid_id}

  """
  def parse(id) when is_atom(id) and not is_nil(id), do: id |> Atom.to_string() |> parse()

  def parse(id) when is_binary(id) do
    case :binary.split(id, ":") do
      [prefix, value] when value != "" ->
        case String.upcase(prefix) do
          "ISO" -> {:ok, {:iso, normalize_code(value)}}
          "GN" -> parse_geonames(value)
          _ -> {:error, :invalid_id}
        end

      _ ->
        {:error, :invalid_id}
    end
  end

  def parse(_id), do: {:error, :invalid_id}

  defp parse_geonames(value) do
    case value |> String.trim() |> Integer.parse() do
      {id, ""} -> {:ok, {:geonames, id}}
      _ -> {:error, :invalid_id}
    end
  end

  defp normalize_code(code) when is_atom(code) and not is_nil(code) do
    code |> Atom.to_string() |> normalize_code()
  end

  defp normalize_code(code) when is_binary(code) do
    code |> String.trim() |> String.upcase()
  end
end
