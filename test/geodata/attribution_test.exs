defmodule GeoData.AttributionTest do
  use ExUnit.Case, async: true

  alias GeoData.Attribution
  alias GeoData.Source.Geonames
  alias GeoData.Source.IsoCodes

  setup do
    dir =
      Path.join(System.tmp_dir!(), "geodata-attribution-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, storage_path: dir}
  end

  test "filename/0 returns the manifest filename" do
    assert Attribution.filename() == "attribution.json"
  end

  test "every source declares complete attribution metadata" do
    for source <- [IsoCodes, Geonames] do
      attribution = source.attribution()

      assert is_binary(attribution.name)
      assert String.starts_with?(attribution.url, "https://")
      assert is_binary(attribution.license)
      assert is_binary(attribution.attribution)
    end
  end

  test "build/2 lists the sources, licenses and files" do
    manifest = Attribution.build([IsoCodes, Geonames], dataset: :cities)

    assert manifest["dataset"] == "cities"
    assert is_binary(manifest["generated_at"])
    assert Enum.map(manifest["sources"], & &1["name"]) == ["iso-codes", "GeoNames"]

    iso = Enum.find(manifest["sources"], &(&1["name"] == "iso-codes"))
    assert iso["license"] == "LGPL-2.1-or-later"
    assert "iso_3166-1.json" in iso["files"]

    geonames = Enum.find(manifest["sources"], &(&1["name"] == "GeoNames"))
    assert geonames["license"] == "CC BY 4.0"
    assert "cities1000.txt" in geonames["files"]
  end

  test "write/2 writes the manifest to storage_path", %{storage_path: dir} do
    assert {:ok, path} = Attribution.write([IsoCodes], dataset: :base, storage_path: dir)

    assert path == Path.join(dir, "attribution.json")
    assert JSON.decode!(File.read!(path))["dataset"] == "base"
  end
end
