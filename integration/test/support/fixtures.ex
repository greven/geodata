defmodule GeodataIntegration.Fixtures do
  @moduledoc false

  # Reuse the library's own fixtures through the dependency path, the same way
  # downstream adapter projects load shared cases from Ecto. This keeps a single
  # source of truth for the sample data.
  def dir do
    Path.join(Mix.Project.deps_paths()[:geodata], "test/fixtures")
  end

  def path(name), do: Path.join(dir(), name)

  def iso_codes do
    %{
      iso_3166_1: path("iso_3166-1.json"),
      iso_3166_2: path("iso_3166-2.json"),
      iso_3166_3: path("iso_3166-3.json")
    }
  end
end
