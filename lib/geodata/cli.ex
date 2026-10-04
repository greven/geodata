defmodule GeoData.CLI do
  @moduledoc false

  alias GeoData.Options

  @switches [
    source_path: :string,
    storage_path: :string,
    dataset: :string,
    sources: :string,
    postal_countries: :string,
    boundaries: :string,
    boundary_detail: :string,
    file: :keep,
    force: :boolean,
    reset: :boolean
  ]

  def parse!(argv), do: OptionParser.parse!(argv, strict: @switches)

  def options(cli), do: Options.config_options(collect(cli))

  defp collect(cli) do
    []
    |> put(:dataset, cli[:dataset], &String.to_atom/1)
    |> put(:sources, cli[:sources], &parse_csv/1)
    |> put(:postal_countries, cli[:postal_countries], &parse_countries/1)
    |> put(:boundaries, cli[:boundaries], &parse_levels/1)
    |> put(:boundary_detail, cli[:boundary_detail], &String.to_atom/1)
    |> put(:source_path, cli[:source_path], & &1)
    |> put(:storage_path, cli[:storage_path], & &1)
    |> put(:force, cli[:force], & &1)
    |> put(:reset, cli[:reset], & &1)
    |> put(:files, files(cli), & &1)
  end

  defp put(opts, _key, nil, _fun), do: opts
  defp put(opts, key, value, fun), do: Keyword.put(opts, key, fun.(value))

  defp parse_csv(value) do
    value |> String.split(",") |> Enum.map(&String.to_atom/1)
  end

  defp parse_countries("all"), do: :all

  defp parse_countries(value) do
    value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp parse_levels("all"), do: :all

  defp parse_levels(value) do
    value |> String.split(",") |> Enum.map(&String.to_atom/1)
  end

  defp files(cli) do
    cli
    |> Keyword.get_values(:file)
    |> List.flatten()
    |> Map.new(&split_pair/1)
  end

  defp split_pair(pair) do
    case :binary.split(pair, "=") do
      [key, path] when key != "" and path != "" -> {String.to_atom(key), path}
      _ -> raise ArgumentError, "expected --file KEY=PATH, got #{inspect(pair)}"
    end
  end
end
