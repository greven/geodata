defmodule GeoData.ListingTest do
  use ExUnit.Case, async: false

  alias GeoData.NotFoundError
  alias GeoData.SearchFixtures
  alias GeoData.Storage

  setup do
    Storage.reset()
    on_exit(&Storage.reset/0)
    GeoData.put_many(SearchFixtures.places())
    :ok
  end

  describe "countries/1" do
    test "returns every country ordered by name" do
      assert names(GeoData.countries()) == ["Brazil", "Portugal"]
    end

    test "merges extra filters" do
      assert names(GeoData.countries(where: [continent: "EU"])) == ["Portugal"]
    end

    test "honours order_by and limit" do
      assert names(GeoData.countries(order_by: {:population, :desc})) == ["Brazil", "Portugal"]
      assert length(GeoData.countries(limit: 1)) == 1
    end

    test "stream_countries/1 is lazy" do
      assert GeoData.stream_countries() |> Enum.map(& &1.name) |> Enum.sort() ==
               ["Brazil", "Portugal"]
    end
  end

  describe "subdivisions/2" do
    test "returns every subdivision" do
      assert ids(GeoData.subdivisions()) == ["ISO:US-CA"]
    end

    test "scopes to a country code" do
      assert ids(GeoData.subdivisions("US")) == ["ISO:US-CA"]
      assert GeoData.subdivisions("PT") == []
    end

    test "stream_subdivisions/2 is lazy" do
      assert GeoData.stream_subdivisions("US") |> Enum.map(& &1.id) == ["ISO:US-CA"]
    end
  end

  describe "features/1" do
    test "returns features (not populated places) by default" do
      assert ids(GeoData.features()) == ["GN:1863967"]
      assert ids(GeoData.features(where: [feature_code: :mountain])) == ["GN:1863967"]
      assert GeoData.features(where: [feature_code: :lake]) == []
    end

    test "accepts feature class aliases and merges other filters" do
      assert ids(GeoData.features(where: [feature_class: :landforms])) == ["GN:1863967"]
      assert GeoData.features(where: [country: "PT"]) == []
      assert ids(GeoData.features(where: [country: "JP"])) == ["GN:1863967"]
    end

    test "honours order_by and limit" do
      assert length(GeoData.features(limit: 1)) == 1
    end

    test "stream_features/1 is lazy" do
      assert GeoData.stream_features() |> Enum.map(& &1.id) == ["GN:1863967"]
    end

    test "exposes the available groups and classes" do
      assert :mountain in GeoData.feature_groups()
      assert :landforms in GeoData.feature_classes()
    end
  end

  describe "display_name/3" do
    test "accepts a place or a canonical id" do
      place = GeoData.fetch!("ISO:PT")

      assert GeoData.display_name(place, :en) == {:ok, "Portugal"}
      assert GeoData.display_name("ISO:PT", :en) == {:ok, "Portugal"}
      assert GeoData.display_name!("ISO:BR", :en) == "Brazil"
    end

    test "returns or raises NotFoundError for an unknown id" do
      assert {:error, %NotFoundError{}} = GeoData.display_name("ISO:ZZ", :en)
      assert_raise NotFoundError, fn -> GeoData.display_name!("ISO:ZZ", :en) end
    end
  end

  describe "code normalization" do
    test "country/1 accepts lowercase and atoms" do
      assert {:ok, pt} = GeoData.country("pt")
      assert pt.id == "ISO:PT"
      assert {:ok, pt} = GeoData.country(:pt)
      assert pt.id == "ISO:PT"
    end

    test "subdivision/1 accepts lowercase and atoms" do
      assert {:ok, ca} = GeoData.subdivision("us-ca")
      assert ca.id == "ISO:US-CA"
      assert {:ok, ca} = GeoData.subdivision(:"US-CA")
      assert ca.id == "ISO:US-CA"
    end

    test "place/1 accepts a numeric string" do
      assert {:ok, ny} = GeoData.place("5128581")
      assert ny.id == "GN:5128581"
    end

    test "filters accept atoms and numeric string ids" do
      assert ids(GeoData.subdivisions(:us)) == ["ISO:US-CA"]

      assert {:ok, result} = GeoData.search(nil, where: [country: :us])
      assert Enum.sort(ids(result.places)) == ["GN:5128581", "ISO:US-CA"]

      assert {:ok, result} = GeoData.search(nil, where: [geonames_id: "5128581"])
      assert ids(result.places) == ["GN:5128581"]
    end
  end

  describe "bang lookups" do
    test "return the place directly" do
      assert GeoData.country!("pt").id == "ISO:PT"
      assert GeoData.subdivision!("us-ca").id == "ISO:US-CA"
      assert GeoData.place!("5128581").id == "GN:5128581"
    end

    test "raise NotFoundError for unknown ids" do
      assert_raise NotFoundError, fn -> GeoData.country!("ZZ") end
      assert_raise NotFoundError, fn -> GeoData.subdivision!("ZZ-ZZ") end
      assert_raise NotFoundError, fn -> GeoData.place!(999) end
    end
  end

  defp names(places), do: Enum.map(places, & &1.name)
  defp ids(places), do: Enum.map(places, & &1.id)
end
