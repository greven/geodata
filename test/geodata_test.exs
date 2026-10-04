defmodule GeoDataTest do
  use ExUnit.Case, async: false
  doctest GeoData

  alias GeoData.NotFoundError
  alias GeoData.Place

  setup do
    GeoData.Storage.reset()
    :ok
  end

  test "fetch/1 and fetch!/1 return a stored place" do
    place = Place.new!(id: "ISO:PT", kind: :country, iso_3166_1: "PT", name: "Portugal")

    assert :ok = GeoData.put_many([place])
    assert {:ok, ^place} = GeoData.fetch("ISO:PT")
    assert GeoData.fetch!("ISO:PT") == place
  end

  test "fetch/1 returns a NotFoundError for a missing id" do
    assert {:error, %NotFoundError{id: "ISO:XX"}} = GeoData.fetch("ISO:XX")
  end

  test "fetch!/1 raises for a missing id" do
    assert_raise NotFoundError, fn -> GeoData.fetch!("ISO:XX") end
  end

  test "country/1 looks up by ISO 3166-1 code" do
    country = Place.new!(id: "ISO:PT", kind: :country, iso_3166_1: "PT", name: "Portugal")

    assert :ok = GeoData.put_many([country])
    assert {:ok, ^country} = GeoData.country("PT")
  end

  test "subdivision/1 looks up by ISO 3166-2 code" do
    subdivision =
      Place.new!(id: "ISO:PT-11", kind: :subdivision, iso_3166_2: "PT-11", name: "Lisbon")

    assert :ok = GeoData.put_many([subdivision])
    assert {:ok, ^subdivision} = GeoData.subdivision("PT-11")
  end

  test "place/1 looks up by GeoNames id" do
    place =
      Place.new!(id: "GN:2267057", kind: :city, geonames_id: 2_267_057, name: "Lisbon")

    assert :ok = GeoData.put_many([place])
    assert {:ok, ^place} = GeoData.place(2_267_057)
  end

  test "all/0 and count/0 reflect the stored places" do
    assert :ok = GeoData.put_many([Place.new!(id: "GN:1", kind: :city, name: "A")])
    assert GeoData.count() == 1
    assert GeoData.all() |> Enum.map(& &1.id) == ["GN:1"]
  end

  test "delete/1 removes a place" do
    assert :ok = GeoData.put_many([Place.new!(id: "GN:1", kind: :city, name: "A")])
    assert :ok = GeoData.delete("GN:1")
    assert GeoData.count() == 0
  end
end
