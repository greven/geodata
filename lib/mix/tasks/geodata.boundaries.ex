defmodule Mix.Tasks.Geodata.Boundaries do
  @shortdoc "Fetches Natural Earth boundary polygons"

  @moduledoc """
  Fetches and indexes the Natural Earth boundary polygons used by
  `GeoData.Boundary`.

      mix geodata.boundaries --levels country,subdivision
      mix geodata.boundaries --all
      mix geodata.boundaries --all --detail high
      mix geodata.boundaries --all --force
      mix geodata.boundaries --source-path tmp/geodata

  With neither `--levels` nor `--all`, the configured `:boundaries` are used.
  `--detail` selects the Natural Earth scale: `low` (1:50m, the default) or
  `high` (1:10m, larger but more accurate). Files are cached under
  `--source-path` and reused unless `--force` is given.
  """

  use Mix.Task

  alias GeoData.Boundary
  alias GeoData.Fetch

  @switches [
    levels: :string,
    all: :boolean,
    detail: :string,
    force: :boolean,
    source_path: :string
  ]

  @impl true
  def run(argv) do
    {cli, _args} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    case Boundary.build(opts(cli)) do
      {:ok, info} ->
        Mix.shell().info("boundaries: #{length(info.levels)} levels, #{info.total} areas")
        Mix.shell().info("files: #{Fetch.format_changes(info.files)}")

      {:error, error} ->
        Mix.raise(Exception.message(error))
    end
  end

  defp opts(cli) do
    []
    |> put(:boundaries, levels(cli))
    |> put(:boundary_detail, detail(cli))
    |> put(:force, cli[:force])
    |> put(:source_path, cli[:source_path])
  end

  defp put(opts, _key, nil), do: opts
  defp put(opts, key, value), do: Keyword.put(opts, key, value)

  defp levels(cli) do
    cond do
      cli[:all] ->
        :all

      is_binary(cli[:levels]) ->
        cli[:levels]
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&String.to_atom/1)

      true ->
        nil
    end
  end

  defp detail(cli), do: if(is_binary(cli[:detail]), do: String.to_atom(cli[:detail]), else: nil)
end
