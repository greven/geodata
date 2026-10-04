defmodule GeodataIntegration.StorageEctoTest do
  @moduledoc """
  Drives the public API with `GeoData.Storage.Ecto` configured the way a host
  application would: `storage:` set in config, a real repo, and the bundled
  migration applied through Ecto.
  """

  use GeodataIntegration.EctoCase, async: false

  alias GeodataIntegration.Fixtures

  test "ingests, reads, localizes and searches through a real Ecto repo", %{
    storage_path: storage_path,
    source_path: source_path
  } do
    assert {:ok, report} =
             GeoData.Ingest.run(
               dataset: :base,
               sources: [:iso_codes],
               files: Fixtures.iso_codes(),
               storage_path: storage_path,
               source_path: source_path,
               reset: true
             )

    assert report.total == 6

    # The storage configured for this application (Ecto) backs the public API.
    assert {:ok, pt} = GeoData.country("PT")
    assert pt.name == "Portugal"
    assert GeoData.count() == 6

    # CLDR display names resolve in a consumer project.
    assert GeoData.display_name("ISO:PT", :en) == {:ok, "Portugal"}

    # `GeoData.Search.Ecto` pushes the query into SQL.
    assert {:ok, result} = GeoData.search("port", search: GeoData.Search.Ecto)
    assert Enum.map(result.places, & &1.id) == ["ISO:PT"]

    # The bundled migration produced a table the host can query directly.
    assert Repo.aggregate(GeoData.Storage.Ecto.Place, :count) == 6
  end
end
