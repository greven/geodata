defmodule GeoData.Storage.Ecto.AssociationsTest do
  use ExUnit.Case, async: false
  use GeoData.EctoSetup

  import Ecto.Query

  alias GeoData.Storage.Ecto
  alias GeoData.Storage.Ecto.Place, as: Row
  alias GeoData.Storage.Ecto.TestRepo, as: Repo

  setup do
    country = GeoData.Place.new!(id: "ISO:PT", kind: :country, iso_3166_1: "PT", name: "Portugal")

    subdivision =
      GeoData.Place.new!(
        id: "ISO:PT-11",
        kind: :subdivision,
        iso_3166_1: "PT",
        iso_3166_2: "PT-11",
        parent_id: "ISO:PT",
        name: "Lisboa"
      )

    city = GeoData.Place.new!(id: "GN:1", kind: :city, iso_3166_1: "PT", parent_id: "ISO:PT")

    other =
      GeoData.Place.new!(
        id: "GN:2",
        kind: :city,
        iso_3166_1: "ES",
        parent_id: "ISO:ES",
        name: "Madrid"
      )

    Ecto.put_many([country, subdivision, city, other])
    :ok
  end

  test "selects the cities of a country" do
    ids =
      Repo.all(from(r in Row, where: r.iso_3166_1 == "PT" and r.kind == "city", select: r.id))

    assert ids == ["GN:1"]
  end

  test "selects every place of a country" do
    ids =
      Repo.all(from(r in Row, where: r.iso_3166_1 == "PT", select: r.id)) |> Enum.sort()

    assert ids == ["GN:1", "ISO:PT", "ISO:PT-11"]
  end

  test "selects the direct children of a place" do
    ids =
      Repo.all(from(r in Row, where: r.parent_id == "ISO:PT", select: r.id)) |> Enum.sort()

    assert ids == ["GN:1", "ISO:PT-11"]
  end

  test "preloads the parent and children associations" do
    city = Repo.one(from(r in Row, where: r.id == "GN:1", preload: [:parent]))
    assert city.parent.id == "ISO:PT"

    country = Repo.one(from(r in Row, where: r.id == "ISO:PT", preload: [:children]))
    assert country.children |> Enum.map(& &1.id) |> Enum.sort() == ["GN:1", "ISO:PT-11"]
  end
end
