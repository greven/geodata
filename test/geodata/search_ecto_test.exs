defmodule GeoData.SearchEctoTest do
  use ExUnit.Case, async: false
  use GeoData.EctoSetup

  alias GeoData.SearchFixtures
  alias GeoData.Storage.Ecto

  setup do
    Ecto.put_many(SearchFixtures.places())
    :ok
  end

  use GeoData.SearchTests, search: GeoData.Search.Ecto

  describe "proximity" do
    test "orders by distance, with places without coordinates last" do
      assert {:ok, result} =
               search(nil, where: [kind: :city], order_by: {:distance, {38.71667, -9.13333}})

      assert ids(result) == ["GN:2267057", "GN:2867714", "GN:5128581", "GN:3448439"]

      assert {:ok, all} = search(nil, order_by: {:distance, {38.71667, -9.13333}})
      assert List.last(all.places).latitude == nil
    end

    test "filters by radius" do
      assert {:ok, result} = search(nil, where: [near: {38.71667, -9.13333, 50_000}])
      assert ids(result) == ["GN:2267057"]
      assert result.total == 1

      assert {:ok, empty} = search(nil, where: [near: {0.0, 0.0, 100.0}])
      assert empty.places == []
    end

    test "combines a radius with other filters" do
      assert {:ok, result} =
               search(nil, where: [near: {38.71667, -9.13333, 800_000}, kind: :city])

      assert ids(result) == ["GN:2267057"]
    end
  end

  describe "fuzzy" do
    test "fuzzy matching is not supported by the Ecto engine" do
      assert {:error, %GeoData.ValidationError{reason: :invalid_option}} =
               GeoData.search("lisbom", match: :fuzzy, search: GeoData.Search.Ecto)
    end
  end
end
