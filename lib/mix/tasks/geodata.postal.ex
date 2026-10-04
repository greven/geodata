defmodule Mix.Tasks.Geodata.Postal do
  @shortdoc "Fetches postal-code validation patterns"

  @moduledoc """
  Fetches the postal-code patterns used by `GeoData.Postal`.

      mix geodata.postal --countries PT,US
      mix geodata.postal --all
      mix geodata.postal --all --force
      mix geodata.postal --source-path tmp/geodata

  With neither `--countries` nor `--all`, the configured `:postal_countries`
  are fetched. Files are cached under `--source-path` and reused unless
  `--force` is given.
  """

  use Mix.Task

  alias GeoData.Fetch
  alias GeoData.Postal

  @switches [countries: :string, all: :boolean, force: :boolean, source_path: :string]

  @impl true
  def run(argv) do
    {cli, _args} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    case Postal.fetch(opts(cli)) do
      {:ok, info} ->
        Mix.shell().info("files: #{Fetch.format_changes(info.files)}")
        Mix.shell().info("postal countries: #{length(info.countries)}")

        if info.missing != [] do
          Mix.shell().info("missing: #{Enum.join(info.missing, ", ")}")
        end

      {:error, error} ->
        Mix.raise(Exception.message(error))
    end
  end

  defp opts(cli) do
    []
    |> put(:postal_countries, countries(cli))
    |> put(:force, cli[:force])
    |> put(:source_path, cli[:source_path])
  end

  defp put(opts, _key, nil), do: opts
  defp put(opts, key, value), do: Keyword.put(opts, key, value)

  defp countries(cli) do
    cond do
      cli[:all] ->
        :all

      is_binary(cli[:countries]) ->
        cli[:countries]
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      true ->
        nil
    end
  end
end
