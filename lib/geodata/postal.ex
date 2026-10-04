defmodule GeoData.Postal do
  @moduledoc """
  Postal-code validation, normalization and formatting.

  Validation uses the postal-code patterns published by Google's
  [libaddressinput](https://github.com/google/libaddressinput) i18n address
  metadata (Apache-2.0). Nothing is downloaded unless you opt in with the
  `:postal_countries` option, and the patterns are fetched and cached through
  `GeoData.Fetch`:

      config :geodata, postal_countries: ["PT", "US", "GB"]

  or `:all` for every supported territory (roughly 250 small requests). The
  patterns are downloaded alongside ingestion when `:postal_countries` is set,
  or on demand with `fetch/1` / `mix geodata.postal`.

  Until patterns are loaded, `validate/2` returns `{:error, :not_loaded}` and
  `valid?/2` returns `false`.

  ## Validation

      GeoData.Postal.valid?("1000-001", :pt)   #=> true  (once PT is loaded)
      GeoData.Postal.valid?("1000 001", :pt)   #=> false
      GeoData.Postal.valid?("SW1A 1AA", "GB")  #=> true
      GeoData.Postal.valid?("SW1A 1AA", "US")  #=> false

      GeoData.Postal.validate("999", :pt)      #=> {:error, :invalid}
      GeoData.Postal.validate("12345", :pt)    #=> {:error, :not_loaded}

  `supported?/1` and `countries/0` describe the territory patterns that are
  currently loaded; countries without a postal system are simply absent.

  ## Normalization and formatting

  `normalize/1` and `format/2` work without any data. `normalize/1` returns a
  comparison key (upper-cased, alphanumeric only); `format/2` renders a
  best-effort canonical display form for a curated set of countries.

      iex> GeoData.Postal.normalize("sw1a 1aa")
      "SW1A1AA"

      iex> GeoData.Postal.format("1234123", :pt)
      "1234-123"

  """

  alias GeoData.Fetch
  alias GeoData.IngestError
  alias GeoData.DownloadError
  alias GeoData.Source.PostalData
  alias GeoData.Source.PostalIndex

  @cache {__MODULE__, :patterns}

  @default_source_path Application.compile_env(
                         :geodata,
                         :source_path,
                         "priv/geodata/sources"
                       )

  @formats %{
    "PT" => "NNNN-NNN",
    "NL" => "NNNN AA",
    "CA" => "A*A A*A",
    "JP" => "NNN-NNNN",
    "BR" => "NNNNN-NNN",
    "PL" => "NN-NNN",
    "CZ" => "NNN NN",
    "SK" => "NNN NN",
    "SE" => "NNN NN",
    "IE" => "A** ****",
    "MT" => "AAA NNNN"
  }

  @doc """
  Downloads the configured postal-code patterns.

  Reads `:postal_countries` from the given options, falling back to the
  application environment. `:all` fetches the country index and then every
  territory; a list fetches just those countries. Existing files are reused
  unless `:force` is set.

  Loaded patterns replace the in-memory cache. Returns `{:ok, info}` with the
  loaded `:countries`, any `:missing` territories (present in the index but
  without a data file) and the resolved `:files`, or `{:error, exception}`.
  """
  def fetch(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:postal_countries, configured_countries())
      |> Keyword.put_new(:source_path, source_path())

    countries = Keyword.fetch!(opts, :postal_countries)

    with {:ok, codes, index} <- resolve(countries, opts),
         {:ok, resolved, missing} <- fetch_countries(codes, opts),
         {:ok, patterns} <- read_patterns(resolved) do
      if codes != [], do: :persistent_term.put(@cache, patterns)

      {:ok,
       %{
         countries: patterns |> Map.keys() |> Enum.sort(),
         missing: Enum.sort(missing),
         files: Map.merge(index, resolved)
       }}
    end
  end

  @doc """
  Clears the in-memory patterns, so the next lookup reloads them from disk.
  """
  def reset, do: :persistent_term.erase(@cache)

  @doc """
  Returns whether `code` is a valid postal code for `country`.

  `country` is an ISO 3166-1 alpha-2 code (string or atom). Returns `false`
  when the country's pattern is not loaded or the code is malformed.
  """
  def valid?(code, country) when is_binary(code) do
    case lookup(country) do
      {regex, _examples} -> Regex.match?(regex, input(code))
      nil -> false
    end
  end

  def valid?(_code, _country), do: false

  @doc """
  Validates `code` for `country`.

  Returns `:ok`, `{:error, :invalid}` or `{:error, :not_loaded}` (when the
  country's pattern has not been fetched).
  """
  def validate(code, country) when is_binary(code) do
    case lookup(country) do
      {regex, _examples} ->
        if Regex.match?(regex, input(code)), do: :ok, else: {:error, :invalid}

      nil ->
        {:error, :not_loaded}
    end
  end

  def validate(_code, _country), do: {:error, :invalid}

  @doc """
  Returns a normalized comparison key for `code`.

  The result is upper-cased and stripped of every non-alphanumeric character,
  so codes compare equal regardless of spacing or hyphenation. `nil`
  normalizes to `""`.

  ## Examples

      iex> GeoData.Postal.normalize("sw1a 1aa")
      "SW1A1AA"

      iex> GeoData.Postal.normalize("1000-001")
      "1000001"

  """
  def normalize(nil), do: ""

  def normalize(code) when is_binary(code) do
    code
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]+/, "")
  end

  @doc """
  Returns a canonical display form of `code` for `country`.

  Grouping is applied for a subset of countries (see the module documentation);
  for every other country the normalized code is returned. Unknown input
  degrades to `normalize/1`.

  ## Examples

      iex> GeoData.Postal.format("1234123", :pt)
      "1234-123"

      iex> GeoData.Postal.format("sw1a1aa", :gb)
      "SW1A 1AA"

  """
  def format(code, country) when is_binary(code) do
    key = normalize(code)

    case country_code(country) do
      "GB" ->
        format_gb(key)

      cc ->
        case Map.fetch(@formats, cc) do
          {:ok, mask} -> apply_mask(key, mask)
          :error -> key
        end
    end
  end

  def format(_code, _country), do: ""

  @doc """
  Returns whether `country` has a loaded postal-code pattern.
  """
  def supported?(country), do: lookup(country) != nil

  @doc """
  Returns the ISO 3166-1 codes with a loaded pattern, sorted.
  """
  def countries, do: patterns() |> Map.keys() |> Enum.sort()

  defp resolve(:all, opts) do
    with {:ok, resolved} <- Fetch.ensure([PostalIndex], opts),
         %{index: %{path: path}} <- resolved[PostalIndex.source()],
         {:ok, body} <- read(path, :postal_index),
         {:ok, codes} <- decode_countries(body) do
      {:ok, codes, resolved}
    else
      {:error, error} -> {:error, error}
      _ -> {:error, %IngestError{source: :postal_index, reason: :invalid_format}}
    end
  end

  defp resolve(countries, _opts) when is_list(countries) do
    {:ok, Enum.map(countries, &normalize_country/1), %{}}
  end

  defp fetch_countries([], _opts), do: {:ok, %{}, []}

  defp fetch_countries(codes, opts) do
    codes
    |> Enum.reduce_while({:ok, %{}, []}, fn code, {:ok, files, missing} ->
      case Fetch.ensure([PostalData], Keyword.put(opts, :postal_countries, [code])) do
        {:ok, resolved} ->
          files = Map.merge(files, Map.get(resolved, PostalData.source(), %{}))
          {:cont, {:ok, files, missing}}

        {:error, %DownloadError{status: 404}} ->
          {:cont, {:ok, files, [code | missing]}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, files, missing} -> {:ok, %{PostalData.source() => files}, missing}
      error -> error
    end
  end

  defp read_patterns(resolved) do
    resolved
    |> Map.get(PostalData.source(), %{})
    |> Enum.reduce_while({:ok, %{}}, fn {code, %{path: path}}, {:ok, acc} ->
      case read(path, :postal_data) do
        {:ok, body} ->
          case pattern(body) do
            {:ok, value} -> {:cont, {:ok, Map.put(acc, code, value)}}
            :skip -> {:cont, {:ok, acc}}
            :error -> {:halt, {:error, invalid_format(path)}}
          end

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp pattern(body) do
    case JSON.decode(body) do
      {:ok, %{"zip" => zip} = data} when is_binary(zip) and zip != "" ->
        case compile(zip) do
          nil -> :skip
          regex -> {:ok, {regex, examples(data)}}
        end

      {:ok, _data} ->
        :skip

      {:error, _reason} ->
        :error
    end
  end

  defp compile(zip) do
    Regex.compile!("\\A(?:" <> zip <> ")\\z")
  rescue
    _error -> nil
  end

  defp examples(%{"zipex" => zipex}) when is_binary(zipex) do
    zipex |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

  defp examples(_data), do: []

  defp decode_countries(body) do
    case JSON.decode(body) do
      {:ok, %{"countries" => countries}} when is_binary(countries) ->
        {:ok, countries |> String.split("~", trim: true) |> Enum.map(&String.upcase/1)}

      _ ->
        {:error, %IngestError{source: :postal_index, reason: :invalid_format}}
    end
  end

  defp read(path, source) do
    case File.read(path) do
      {:ok, body} ->
        {:ok, body}

      {:error, _reason} ->
        {:error, %IngestError{source: source, file: path, reason: :read_failed}}
    end
  end

  defp invalid_format(path) do
    %IngestError{source: :postal_data, file: path, reason: :invalid_format}
  end

  defp lookup(country) do
    case country_code(country) do
      nil -> nil
      cc -> Map.get(patterns(), cc)
    end
  end

  defp patterns do
    case :persistent_term.get(@cache, :missing) do
      :missing ->
        loaded = load_from_disk()
        :persistent_term.put(@cache, loaded)
        loaded

      loaded ->
        loaded
    end
  end

  defp load_from_disk do
    directory = Path.join(source_path(), "postal")

    case File.ls(directory) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.reject(&(&1 == "_index.json"))
        |> Enum.reduce(%{}, fn entry, acc ->
          with {:ok, body} <- File.read(Path.join(directory, entry)),
               {:ok, value} <- pattern(body) do
            Map.put(acc, entry |> Path.rootname() |> String.upcase(), value)
          else
            _ -> acc
          end
        end)

      {:error, _reason} ->
        %{}
    end
  end

  defp configured_countries do
    Application.get_env(:geodata, :postal_countries, [])
  end

  defp source_path do
    Application.get_env(:geodata, :source_path, @default_source_path)
  end

  defp normalize_country(country) when is_atom(country) and not is_nil(country),
    do: country |> Atom.to_string() |> String.upcase()

  defp normalize_country(country) when is_binary(country),
    do: country |> String.trim() |> String.upcase()

  defp country_code(country) when is_atom(country) and not is_nil(country),
    do: country |> Atom.to_string() |> String.upcase()

  defp country_code(country) when is_binary(country),
    do: country |> String.trim() |> String.upcase()

  defp country_code(_country), do: nil

  defp input(code) do
    code
    |> String.upcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp apply_mask(code, mask) do
    mask_chars = String.graphemes(mask)
    placeholders = Enum.count(mask_chars, &(&1 in ["N", "A", "*"]))

    if String.length(code) == placeholders do
      {result, []} =
        Enum.map_reduce(mask_chars, String.graphemes(code), fn
          char, [taken | rest] when char in ["N", "A", "*"] -> {taken, rest}
          char, rest -> {char, rest}
        end)

      Enum.join(result)
    else
      code
    end
  end

  ## Special formatting

  defp format_gb(code) when byte_size(code) > 3 do
    {head, tail} = String.split_at(code, String.length(code) - 3)
    head <> " " <> tail
  end

  defp format_gb(code), do: code
end
