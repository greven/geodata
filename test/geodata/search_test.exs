defmodule GeoData.SearchTest do
  use ExUnit.Case, async: false

  alias GeoData.SearchFixtures
  alias GeoData.Storage

  setup do
    Storage.reset()
    on_exit(&Storage.reset/0)
    GeoData.put_many(SearchFixtures.places())
    :ok
  end

  use GeoData.SearchTests, search: GeoData.Search.Memory

  describe "fuzzy matching" do
    test "matches a typo" do
      assert {:ok, result} = search("lisbom", match: :fuzzy)
      assert ids(result) == ["GN:2267057"]
    end

    test "matches an adjacent transposition" do
      assert {:ok, result} = search("lisbno", match: :fuzzy)
      assert ids(result) == ["GN:2267057"]
    end

    test "matches every word of a multi-word query" do
      assert {:ok, result} = search("new yrok", match: :fuzzy)
      assert ids(result) == ["GN:5128581"]
    end

    test "fuzziness 0 requires exact tokens" do
      assert {:ok, %{places: []}} = search("lisbom", match: :fuzzy, fuzziness: 0)

      assert {:ok, result} = search("lisbon", match: :fuzzy, fuzziness: 0)
      assert ids(result) == ["GN:2267057"]
    end

    test "fuzziness 2 widens the match" do
      assert {:ok, %{places: []}} = search("lsbn", match: :fuzzy, fuzziness: 1)
      assert {:ok, result} = search("lsbn", match: :fuzzy, fuzziness: 2)
      assert ids(result) == ["GN:2267057"]
    end

    test "returns an empty result when nothing is close enough" do
      assert {:ok, result} = search("zzzzz", match: :fuzzy)
      assert result.places == []
    end
  end

  describe "proximity" do
    test "orders by distance" do
      assert {:ok, result} =
               search(nil, where: [kind: :city], order_by: {:distance, {38.71667, -9.13333}})

      assert ids(result) == ["GN:2267057", "GN:2867714", "GN:5128581", "GN:3448439"]
    end

    test "filters by radius" do
      assert {:ok, result} = search(nil, where: [near: {38.71667, -9.13333, 50_000}])
      assert ids(result) == ["GN:2267057"]

      assert {:ok, result} = search(nil, where: [near: {0.0, 0.0, 100.0}])
      assert result.places == []
    end

    test "puts places without coordinates last" do
      assert {:ok, result} = search(nil, order_by: {:distance, {38.71667, -9.13333}})
      assert List.last(result.places).latitude == nil
    end

    test "nearest/3 returns the closest places" do
      engine = [search: GeoData.Search.Memory]

      assert {:ok, result} = GeoData.nearest(38.71667, -9.13333, engine ++ [limit: 1])
      assert ids(result) == ["GN:2267057"]

      assert {:ok, result} = GeoData.nearest(38.71667, -9.13333, engine)

      assert ids(result) == [
               "GN:2267057",
               "GN:2867714",
               "GN:5128581",
               "GN:3448439",
               "GN:1863967"
             ]

      assert {:ok, result} = GeoData.nearest(38.71667, -9.13333, engine ++ [radius: 50_000])
      assert ids(result) == ["GN:2267057"]
    end

    test "near/2 resolves a canonical id" do
      engine = [search: GeoData.Search.Memory]

      assert {:ok, result} = GeoData.near("GN:2267057", engine ++ [limit: 1])
      assert ids(result) == ["GN:2267057"]

      assert {:ok, result} = GeoData.near("GN:2267057", engine ++ [limit: 2])
      assert ids(result) == ["GN:2267057", "GN:2867714"]
    end

    test "near/2 accepts a point or a place" do
      engine = [search: GeoData.Search.Memory]

      assert {:ok, result} = GeoData.near({38.71667, -9.13333}, engine ++ [limit: 1])
      assert ids(result) == ["GN:2267057"]

      assert {:ok, result} = GeoData.near(GeoData.place!(2_267_057), engine ++ [limit: 1])
      assert ids(result) == ["GN:2267057"]
    end

    test "near/2 forwards a radius and reports non-point origins" do
      engine = [search: GeoData.Search.Memory]

      assert {:ok, result} = GeoData.near("GN:2267057", engine ++ [radius: 1_000])
      assert ids(result) == ["GN:2267057"]

      assert {:error, %GeoData.NotFoundError{}} = GeoData.near("GN:999999", engine)

      assert {:error, %GeoData.ValidationError{reason: :invalid_type}} =
               GeoData.near("ISO:PT", engine)
    end

    test "near!/2 returns the result or raises" do
      engine = [search: GeoData.Search.Memory]

      assert %GeoData.Search.Result{} =
               GeoData.near!("GN:2267057", engine ++ [limit: 1])

      assert_raise GeoData.ValidationError, fn -> GeoData.near!("ISO:PT", engine) end
    end
  end
end
