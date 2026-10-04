defmodule Mix.Tasks.Geodata.Ingest do
  @shortdoc "Ingests GeoData source files into storage"

  @moduledoc """
  Ingests the configured dataset into `GeoData.Storage`.

      mix geodata.ingest
      mix geodata.ingest --dataset cities --reset
      mix geodata.ingest --source-path tmp/geodata
      mix geodata.ingest --storage-path tmp/geodata
      mix geodata.ingest --file iso_3166_1=./iso_3166-1.json
      mix geodata.ingest --postal-countries PT,US
      mix geodata.ingest --boundaries country,subdivision

  Source files are downloaded and cached as needed; see
  `mix geodata.download`. `--reset` clears storage before ingesting. The
  attribution manifest is written as `attribution.json` under
  `--storage-path`. When `--postal-countries` (a list or `all`) is given, the
  postal-code patterns are fetched too (see `GeoData.Postal`); when
  `--boundaries` (a list or `all`, with optional `--boundary-detail low|high`)
  is given, the boundary polygons are built (see `GeoData.Boundary`).
  """

  use Mix.Task

  alias GeoData.CLI
  alias GeoData.Fetch
  alias GeoData.Ingest

  @impl true
  def run(argv) do
    {cli, _args} = CLI.parse!(argv)
    Mix.Task.run("app.start")

    case Ingest.run(CLI.options(cli)) do
      {:ok, report} -> report(report)
      {:error, error} -> Mix.raise(Exception.message(error))
    end
  end

  defp report(report) do
    Mix.shell().info("sources: #{Fetch.format_changes(report.files)}")
    Mix.shell().info("ingested #{report.total} places from #{inspect(report.sources)}")
    Mix.shell().info("by kind: #{inspect(report.by_kind)}")
    Mix.shell().info("by source: #{inspect(report.by_source)}")
  end
end
