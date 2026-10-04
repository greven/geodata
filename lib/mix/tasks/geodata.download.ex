defmodule Mix.Tasks.Geodata.Download do
  @shortdoc "Downloads and caches GeoData source files"

  @moduledoc """
  Downloads the source files needed by GeoData.

      mix geodata.download
      mix geodata.download --dataset cities
      mix geodata.download --file iso_3166_1=./iso_3166-1.json
      mix geodata.download --source-path tmp/geodata --force
      mix geodata.download --postal-countries PT,US
      mix geodata.download --boundaries country,subdivision --boundary-detail high

  Files already present under `--source-path` are reused unless `--force` is
  given. Use `--file KEY=PATH` to point at an existing local file instead of
  downloading it. `--postal-countries` (a list or `all`) also fetches the
  postal-code patterns (see `GeoData.Postal`), and `--boundaries` (a list or
  `all`, with optional `--boundary-detail low|high`) fetches the Natural Earth
  boundary polygons (see `GeoData.Boundary`). This task only ensures files
  are available; run `mix geodata.ingest` to load them into storage.
  """

  use Mix.Task

  alias GeoData.Boundary
  alias GeoData.CLI
  alias GeoData.Fetch
  alias GeoData.Postal
  alias GeoData.Source

  @impl true
  def run(argv) do
    {cli, _args} = CLI.parse!(argv)
    Mix.Task.run("app.start")

    opts = CLI.options(cli)

    with {:ok, sources} <- Source.resolve(opts),
         {:ok, resolved} <- Fetch.ensure(sources, opts),
         {:ok, postal} <- fetch_postal(opts),
         {:ok, boundaries} <- fetch_boundaries(opts) do
      report(resolved, postal, boundaries)
    else
      {:error, error} -> Mix.raise(Exception.message(error))
    end
  end

  defp fetch_postal(opts) do
    case Keyword.get(opts, :postal_countries, []) do
      [] -> {:ok, nil}
      _countries -> Postal.fetch(opts)
    end
  end

  defp fetch_boundaries(opts) do
    case GeoData.Source.BoundaryData.levels(Keyword.get(opts, :boundaries, [])) do
      [] -> {:ok, nil}
      _levels -> Boundary.fetch(opts)
    end
  end

  defp report(resolved, postal, boundaries) do
    for {source, files} <- resolved, {key, info} <- files do
      Mix.shell().info("#{info.status} (#{info.change}) #{source}/#{key} -> #{info.path}")
    end

    if postal, do: report_postal(postal)
    if boundaries, do: report_boundaries(boundaries)
  end

  defp report_postal(%{files: files, countries: countries, missing: missing}) do
    Mix.shell().info(
      "postal patterns: #{length(countries)} countries (#{Fetch.format_changes(files)})"
    )

    if missing != [], do: Mix.shell().info("postal missing: #{Enum.join(missing, ", ")}")
  end

  defp report_boundaries(%{files: files, levels: levels}) do
    Mix.shell().info(
      "boundaries: #{Enum.map_join(levels, ", ", &to_string/1)} " <>
        "(#{Fetch.format_changes(files)})"
    )
  end
end
