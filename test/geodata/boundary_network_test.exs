defmodule GeoData.BoundaryNetworkTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 300_000

  alias GeoData.Boundary
  alias GeoData.Place
  alias GeoData.Storage

  setup do
    root =
      Path.join(System.tmp_dir!(), "geodata_boundary_net_#{System.unique_integer([:positive])}")

    previous = Application.get_env(:geodata, :source_path)
    Application.put_env(:geodata, :source_path, root)
    Storage.reset()
    Boundary.reset()

    on_exit(fn ->
      Boundary.reset()
      Storage.reset()

      if previous do
        Application.put_env(:geodata, :source_path, previous)
      else
        Application.delete_env(:geodata, :source_path)
      end

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "loads Natural Earth boundaries and resolves a coordinate", %{root: root} do
    assert {:ok, info} =
             Boundary.build(
               boundaries: [:country, :subdivision],
               boundary_detail: :low,
               source_path: root
             )

    assert info.total > 200
    assert Boundary.loaded?()

    GeoData.put_many([
      Place.new!(id: "ISO:PT", kind: :country, iso_3166_1: "PT", name: "Portugal"),
      Place.new!(
        id: "ISO:US-CA",
        kind: :subdivision,
        iso_3166_1: "US",
        iso_3166_2: "US-CA",
        name: "California"
      )
    ])

    assert {:ok, [place]} = Boundary.containing(39.5, -8.0, kind: :country)
    assert place.iso_3166_1 == "PT"

    assert {:ok, [california]} = Boundary.containing(36.0, -120.0, kind: :subdivision)
    assert california.id == "ISO:US-CA"

    assert Boundary.containing(0.0, 0.0) == {:ok, []}
  end
end
