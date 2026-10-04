defmodule GeoData.StatsTest do
  use ExUnit.Case, async: false

  alias GeoData.NotFoundError
  alias GeoData.Place
  alias GeoData.Stats
  alias GeoData.Stats.Country
  alias GeoData.Stats.Summary
  alias GeoData.StatsFixtures
  alias GeoData.Storage
  alias GeoData.ValidationError

  setup do
    Storage.reset()
    on_exit(&Storage.reset/0)
    GeoData.put_many(StatsFixtures.places())
    :ok
  end

  describe "summary/0" do
    test "counts places by kind and countries by continent" do
      assert {:ok, %Summary{} = summary} = Stats.summary()

      assert summary.total == 10
      assert summary.by_kind == %{country: 3, subdivision: 2, city: 4, locality: 1}
      assert summary.by_continent == %{"EU" => 3}
    end
  end

  describe "country/2" do
    test "rolls up a country" do
      assert {:ok, %Country{} = country} = Stats.country("PT")

      assert country.place.iso_3166_1 == "PT"
      assert country.subdivisions == 1
      assert country.cities == 1
      assert country.localities == 1
      assert country.population == 10_305_598
      assert Enum.map(country.neighbours, & &1.iso_3166_1) == ["ES"]
    end

    test "orders largest cities by population and honours :largest" do
      assert {:ok, country} = Stats.country("ES")
      assert Enum.map(country.largest_cities, & &1.name) == ["Madrid", "Barcelona"]

      assert {:ok, country} = Stats.country("ES", largest: 1)
      assert Enum.map(country.largest_cities, & &1.name) == ["Madrid"]
    end

    test "accepts an atom and a country place" do
      assert {:ok, _country} = Stats.country(:pt)
      assert {:ok, _country} = Stats.country(GeoData.country!("PT"))
    end

    test "errors for an unknown country" do
      assert {:error, %NotFoundError{}} = Stats.country("ZZ")
    end

    test "errors when the place is not a country" do
      assert {:error, %ValidationError{reason: :not_a_country}} = Stats.country("PT-11")

      subdivision = GeoData.subdivision!("PT-11")
      assert {:error, %ValidationError{reason: :not_a_country}} = Stats.country(subdivision)
    end

    test "rejects invalid options" do
      assert {:error, %ValidationError{reason: :invalid_option}} =
               Stats.country("PT", largest: 0)
    end
  end

  describe "neighbours/1" do
    test "resolves bordering countries in source order" do
      assert {:ok, neighbours} = Stats.neighbours("PT")
      assert Enum.map(neighbours, & &1.iso_3166_1) == ["ES"]

      assert {:ok, neighbours} = Stats.neighbours("ES")
      assert Enum.map(neighbours, & &1.iso_3166_1) == ["PT", "FR"]
    end

    test "omits neighbour codes that are not stored" do
      place = Place.new!(kind: :country, iso_3166_1: "PT", neighbours: ["ES", "ZZ"])

      assert {:ok, neighbours} = Stats.neighbours(place)
      assert Enum.map(neighbours, & &1.iso_3166_1) == ["ES"]
    end

    test "errors for an unknown country" do
      assert {:error, %NotFoundError{}} = Stats.neighbours("ZZ")
    end

    test "errors when the place is not a country" do
      assert {:error, %ValidationError{reason: :not_a_country}} = Stats.neighbours("PT-11")
    end
  end
end
