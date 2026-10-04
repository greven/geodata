defmodule GeoData.Ingest.EctoTest do
  use ExUnit.Case, async: false
  use GeoData.EctoSetup

  alias GeoData.Fixtures
  alias GeoData.Ingest
  alias GeoData.Storage.Ecto

  test "ingests iso-codes into an Ecto-backed store", %{
    storage_path: storage_path,
    source_path: source_path
  } do
    opts = [
      dataset: :base,
      sources: [:iso_codes],
      files: Fixtures.iso_3166_paths(),
      storage: Ecto,
      storage_path: storage_path,
      source_path: source_path,
      reset: true
    ]

    assert {:ok, report} = Ingest.run(opts)
    assert report.total == 6
    assert report.by_kind == %{country: 3, subdivision: 3}

    assert {:ok, pt} = Ecto.get("ISO:PT")
    assert pt.name == "Portugal"
    assert Ecto.count() == 6

    assert {:ok, result} = GeoData.search("port", search: GeoData.Search.Ecto)
    assert Enum.map(result.places, & &1.id) == ["ISO:PT"]

    assert {:ok, by_code} = GeoData.search("US-CA", search: GeoData.Search.Ecto)
    assert Enum.map(by_code.places, & &1.id) == ["ISO:US-CA"]
  end
end
