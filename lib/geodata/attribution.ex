defmodule GeoData.Attribution do
  @moduledoc """
  Builds and writes the attribution manifest for a generated dataset.

  GeoData bundles no data, but a dataset produced by `GeoData.Ingest` is a
  derivative work of its sources and must carry their notices. The manifest
  records every contributing source, its license and the required
  attribution, and is written as `attribution.json` in the configured
  `:storage_path`.

  Names and licenses are declared by each `GeoData.Source` through its
  `attribution/0` callback.
  """

  alias GeoData.IngestError

  @filename "attribution.json"

  @doc """
  Returns the filename of the attribution manifest.
  """
  def filename, do: @filename

  @doc """
  Builds the manifest as a JSON-encodable map.
  """
  def build(sources, opts) do
    %{
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "dataset" => to_string(opts[:dataset]),
      "sources" => Enum.map(sources, &entry(&1, opts))
    }
  end

  @doc """
  Writes the manifest to `:storage_path`.

  Returns `{:ok, path}` or `{:error, %GeoData.IngestError{}}`.
  """
  def write(sources, opts) do
    path = Path.join(opts[:storage_path], @filename)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, body} <- encode(build(sources, opts)),
         :ok <- File.write(path, body) do
      {:ok, path}
    else
      {:error, reason} ->
        {:error, %IngestError{reason: :attribution_failed, file: path, detail: reason}}
    end
  end

  defp encode(manifest) do
    {:ok, JSON.encode!(manifest)}
  rescue
    error -> {:error, error}
  end

  defp entry(source, opts) do
    attribution = source.attribution()

    %{
      "name" => attribution[:name],
      "url" => attribution[:url],
      "license" => attribution[:license],
      "attribution" => attribution[:attribution],
      "files" => source.files(opts) |> Enum.map(& &1.filename)
    }
  end
end
