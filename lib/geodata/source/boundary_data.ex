defmodule GeoData.Source.BoundaryData do
  @moduledoc """
  Fetch declaration for [Natural Earth](https://www.naturalearthdata.com/) boundary data.

  Supplies the country (`admin_0`) and subdivision (`admin_1`) polygons used by
  `GeoData.Boundary`. The data is public domain.

  Countries follow the requested `:boundary_detail`: `:low` uses Natural Earth
  1:50m, `:high` uses 1:10m. Subdivisions **always** use 1:10m, because Natural
  Earth's 1:50m admin-1 layer only covers a handful of large countries.

  Only the levels named in `:boundaries` are declared; when it is empty this
  source lists no files. This is only a declaration; `GeoData.Fetch` downloads
  and caches the files under `:source_path`.
  """

  @behaviour GeoData.Source

  alias GeoData.Source.File, as: SourceFile

  @base_url "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson"

  @scales %{low: "50m", high: "10m"}

  # The 1:50m admin-1 layer covers only ~9 large countries, so subdivisions
  # always come from 1:10m.
  @subdivision_scale "10m"

  @levels [:country, :subdivision]

  @impl true
  def source, do: :boundary_data

  @impl true
  def files(opts \\ []) do
    levels = levels(Keyword.get(opts, :boundaries, []))
    scale = scale(Keyword.get(opts, :boundary_detail, :low))

    []
    |> admin_file(:country, :admin0, "admin_0_countries", scale, levels)
    |> admin_file(:subdivision, :admin1, "admin_1_states_provinces", @subdivision_scale, levels)
  end

  @impl true
  def parse(_paths, _opts), do: {:ok, []}

  @impl true
  def attribution do
    %{
      name: "Natural Earth",
      url: "https://www.naturalearthdata.com/",
      license: "Public domain",
      attribution:
        "Boundary data from Natural Earth (https://www.naturalearthdata.com/), " <>
          "which is in the public domain."
    }
  end

  @doc """
  Normalizes the `:boundaries` option into a list of levels.

  `:all` expands to every level; unknown values are dropped and the result is
  in a stable coarse-to-fine order.
  """
  def levels(:all), do: @levels

  def levels(boundaries) when is_list(boundaries) do
    Enum.filter(@levels, &(&1 in boundaries))
  end

  def levels(_boundaries), do: []

  @doc """
  Returns the supported boundary levels.
  """
  def supported_levels, do: @levels

  @doc """
  Returns the supported detail levels.
  """
  def details, do: Map.keys(@scales)

  defp scale(:high), do: @scales.high
  defp scale(_detail), do: @scales.low

  defp admin_file(acc, level, key, name, scale, levels) do
    if level in levels do
      acc ++
        [
          %SourceFile{
            key: key,
            filename: "boundaries/ne_#{scale}_#{name}.geojson",
            url: "#{@base_url}/ne_#{scale}_#{name}.geojson",
            format: :json
          }
        ]
    else
      acc
    end
  end
end
