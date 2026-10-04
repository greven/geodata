defmodule GeoData.Source.PostalData do
  @moduledoc """
  Fetch declaration for Google's i18n address metadata.

  Supplies the per-territory postal-code patterns used by
  `GeoData.Postal`, from Google's
  [libaddressinput](https://github.com/google/libaddressinput) i18n address
  metadata (Apache-2.0). Each country is a small JSON document with a `zip`
  regular expression and `zipex` examples.

  This is only a declaration; `GeoData.Fetch` downloads and caches the files
  under `:source_path`.
  """

  @behaviour GeoData.Source

  alias GeoData.Source.File, as: SourceFile

  @base_url "https://www.gstatic.com/chrome/autofill/libaddressinput/chromium-i18n/ssl-address/data"

  @impl true
  def source, do: :postal_data

  @impl true
  def files(opts \\ []) do
    opts
    |> Keyword.get(:postal_countries, [])
    |> Enum.map(&file/1)
  end

  @impl true
  def parse(_paths, _opts), do: {:ok, []}

  @impl true
  def attribution do
    %{
      name: "Google i18n address metadata",
      url: "https://github.com/google/libaddressinput",
      license: "Apache-2.0",
      attribution:
        "Postal-code validation patterns from Google's libaddressinput i18n " <>
          "address metadata (Apache-2.0)."
    }
  end

  @doc """
  Returns the `GeoData.Source.File` for a country code.
  """
  def file(country) do
    code = country |> to_string() |> String.upcase()

    %SourceFile{
      key: code,
      filename: "postal/#{code}.json",
      url: "#{@base_url}/#{code}",
      format: :json
    }
  end
end

defmodule GeoData.Source.PostalIndex do
  @moduledoc false

  @behaviour GeoData.Source

  alias GeoData.Source.File, as: SourceFile

  @url "https://chromium-i18n.appspot.com/ssl-address/data"

  @impl true
  def source, do: :postal_index

  @impl true
  def files(_opts \\ []) do
    [%SourceFile{key: :index, filename: "postal/_index.json", url: @url, format: :json}]
  end

  @impl true
  def parse(_paths, _opts), do: {:ok, []}

  @impl true
  def attribution, do: GeoData.Source.PostalData.attribution()
end
