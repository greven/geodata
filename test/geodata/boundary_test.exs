defmodule GeoData.BoundaryTest do
  use ExUnit.Case, async: false

  alias GeoData.Boundary
  alias GeoData.Place
  alias GeoData.Storage
  alias GeoData.ValidationError

  setup do
    root =
      Path.join(System.tmp_dir!(), "geodata_boundary_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "boundaries"))
    previous = Application.get_env(:geodata, :source_path)
    Application.put_env(:geodata, :source_path, Path.join(root, "unloaded"))

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

  describe "before boundaries are loaded" do
    test "containment is empty and lookups miss" do
      assert Boundary.containing(38.8, -9.1) == {:ok, []}
      refute Boundary.loaded?()
      assert Boundary.get("ISO:PT") == {:error, :not_found}
      assert Boundary.boundaries() == []
    end
  end

  describe "with country and subdivision boundaries" do
    setup %{root: root} do
      write(root, :admin0, [country("ZZ", "Zed", square(-10.0, 38.0, -8.0, 40.0))])
      write(root, :admin1, [subdivision("ZZ-01", "Zed One", square(-9.5, 38.5, -8.5, 39.5))])

      GeoData.put_many([
        Place.new!(id: "ISO:ZZ", kind: :country, iso_3166_1: "ZZ", name: "Zed"),
        Place.new!(
          id: "ISO:ZZ-01",
          kind: :subdivision,
          iso_3166_1: "ZZ",
          iso_3166_2: "ZZ-01",
          name: "Zed One"
        )
      ])

      assert {:ok, %{total: 2}} =
               Boundary.build(boundaries: [:country, :subdivision], source_path: root)

      :ok
    end

    test "returns files grouped by source for reporting", %{root: root} do
      assert {:ok, %{files: files}} =
               Boundary.fetch(boundaries: [:country, :subdivision], source_path: root)

      assert %{boundary_data: source_files} = files
      assert map_size(source_files) == 2
      assert is_binary(GeoData.Fetch.format_changes(files))
    end

    test "returns containing places coarse to fine" do
      assert {:ok, places} = Boundary.containing(39.0, -9.0)
      assert Enum.map(places, & &1.id) == ["ISO:ZZ", "ISO:ZZ-01"]
    end

    test "restricts to the requested kind" do
      assert {:ok, [place]} = Boundary.containing(39.0, -9.0, kind: :subdivision)
      assert place.id == "ISO:ZZ-01"
    end

    test "returns [] for a point that is in no area" do
      assert Boundary.containing(0.0, 0.0) == {:ok, []}
    end

    test "matches a point on the polygon edge" do
      assert {:ok, places} = Boundary.containing(38.0, -9.0)
      assert Enum.map(places, & &1.id) == ["ISO:ZZ"]
    end

    test "exposes geometry and predicates" do
      assert {:ok, boundary} = Boundary.get("ISO:ZZ")
      assert Boundary.contains?(boundary, {39.0, -9.0})
      refute Boundary.contains?(boundary, {0.0, 0.0})
      assert Boundary.bbox(boundary) == {38.0, -10.0, 40.0, -8.0}
      assert GeoData.within?({39.0, -9.0}, "ISO:ZZ-01")
      refute GeoData.within?({0.0, 0.0}, "ISO:ZZ-01")
    end

    test "lists boundaries" do
      assert length(Boundary.boundaries()) == 2
      assert [%Boundary{id: "ISO:ZZ"}] = Boundary.boundaries(kind: :country)
    end

    test "rejects out-of-range coordinates" do
      assert {:error, %ValidationError{}} = Boundary.containing(91.0, 0.0)
      assert {:error, %ValidationError{}} = Boundary.containing(0.0, 181.0)
    end
  end

  describe "lazy loading from disk" do
    test "loads only the configured levels and scales", %{root: root} do
      write(root, :admin0, [country("ZZ", "Zed", square(-10.0, 38.0, -8.0, 40.0))])
      write(root, :admin1, [subdivision("ZZ-01", "Zed One", square(-9.5, 38.5, -8.5, 39.5))])

      write_collection(root, "ne_10m_admin_0_countries.geojson", [
        country("YY", "Yankee", square(1.0, 1.0, 2.0, 2.0))
      ])

      Application.put_env(:geodata, :source_path, root)
      Application.put_env(:geodata, :boundaries, [:country])
      Application.put_env(:geodata, :boundary_detail, :low)

      on_exit(fn ->
        Application.delete_env(:geodata, :boundaries)
        Application.delete_env(:geodata, :boundary_detail)
      end)

      Boundary.reset()

      assert [%Boundary{id: "ISO:ZZ", kind: :country}] = Boundary.boundaries()
    end
  end

  describe "identifier mapping" do
    test "prefers ISO_A2_EH and skips features without a usable code", %{root: root} do
      features = [
        country(nil, "France", square(2.0, 46.0, 3.0, 47.0), %{
          "ISO_A2" => "-99",
          "ISO_A2_EH" => "FR"
        }),
        country(nil, "Mystery", square(4.0, 46.0, 5.0, 47.0), %{
          "ISO_A2" => "-99",
          "ISO_A2_EH" => "-99"
        }),
        country("PT", "Portugal", square(-10.0, 38.0, -8.0, 40.0))
      ]

      write(root, :admin0, features)
      assert {:ok, _info} = Boundary.build(boundaries: [:country], source_path: root)

      assert Boundary.boundaries() |> Enum.map(& &1.id) |> Enum.sort() == ["ISO:FR", "ISO:PT"]
    end

    test "skips subdivisions without an ISO 3166-2 code", %{root: root} do
      features = [
        subdivision("US-CA", "California", square(-124.0, 32.0, -114.0, 42.0)),
        subdivision("", "Nowhere", square(0.0, 0.0, 1.0, 1.0))
      ]

      write(root, :admin1, features)
      assert {:ok, _info} = Boundary.build(boundaries: [:subdivision], source_path: root)
      assert [%Boundary{id: "ISO:US-CA"}] = Boundary.boundaries()
    end
  end

  defp country(code, name, geometry, extra \\ %{}) do
    props = Map.merge(%{"ISO_A2" => code, "NAME_EN" => name}, extra)
    %{"type" => "Feature", "properties" => props, "geometry" => geometry}
  end

  defp subdivision(code, name, geometry) do
    %{
      "type" => "Feature",
      "properties" => %{"iso_3166_2" => code, "name" => name},
      "geometry" => geometry
    }
  end

  defp square(min_lon, min_lat, max_lon, max_lat) do
    %{
      "type" => "Polygon",
      "coordinates" => [
        [
          [min_lon, min_lat],
          [max_lon, min_lat],
          [max_lon, max_lat],
          [min_lon, max_lat],
          [min_lon, min_lat]
        ]
      ]
    }
  end

  defp write(root, :admin0, features) do
    write_collection(root, "ne_50m_admin_0_countries.geojson", features)
  end

  defp write(root, :admin1, features) do
    write_collection(root, "ne_10m_admin_1_states_provinces.geojson", features)
  end

  defp write_collection(root, filename, features) do
    body = JSON.encode!(%{"type" => "FeatureCollection", "features" => features})
    File.write!(Path.join([root, "boundaries", filename]), body)
  end
end
