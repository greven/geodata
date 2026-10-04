defmodule Mix.Tasks.Geodata.Update do
  @shortdoc "Refreshes GeoData source files and rebuilds the dataset"

  @moduledoc """
  Updates the local dataset by re-downloading the source files and rebuilding
  storage from scratch.

      mix geodata.update
      mix geodata.update --dataset cities
      mix geodata.update --source-path tmp/geodata --storage-path tmp/geodata

  Equivalent to `mix geodata.download --force` followed by
  `mix geodata.ingest --reset`: cached files are re-downloaded and storage is
  cleared before ingesting, so removed or renamed upstream places do not
  linger. Accepts the same options as `mix geodata.ingest`.
  """

  use Mix.Task

  alias GeoData.CLI
  alias GeoData.Fetch
  alias GeoData.Ingest

  @impl true
  def run(argv) do
    {cli, _args} = CLI.parse!(argv)
    Mix.Task.run("app.start")

    opts =
      cli
      |> CLI.options()
      |> Keyword.put(:force, true)
      |> Keyword.put(:reset, true)

    case Ingest.run(opts) do
      {:ok, report} ->
        Mix.shell().info("sources: #{Fetch.format_changes(report.files)}")
        Mix.shell().info("updated #{report.total} places from #{inspect(report.sources)}")
        Mix.shell().info("by kind: #{inspect(report.by_kind)}")
        Mix.shell().info("by source: #{inspect(report.by_source)}")

      {:error, error} ->
        Mix.raise(Exception.message(error))
    end
  end
end
