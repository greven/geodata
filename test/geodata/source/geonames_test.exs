defmodule GeoData.Source.GeonamesTest do
  use ExUnit.Case, async: true

  alias GeoData.Fixtures
  alias GeoData.Source.Geonames

  describe "files/1" do
    test "declares the identity files and the cities archive" do
      files = Geonames.files(dataset: :cities)

      assert Enum.map(files, & &1.key) == [
               :geonames_country_info,
               :geonames_places
             ]

      places = Enum.find(files, &(&1.key == :geonames_places))
      assert places.filename == "cities1000.txt"
      assert places.archive == :zip
      assert String.ends_with?(places.url, "cities1000.zip")
    end

    test "uses allCountries for the :all tier" do
      places = Geonames.files(dataset: :all) |> Enum.find(&(&1.key == :geonames_places))

      assert places.filename == "allCountries.txt"
      assert String.ends_with?(places.url, "allCountries.zip")
    end
  end

  describe "parse/2" do
    setup do
      {:ok, places: Fixtures.geonames_paths() |> Geonames.parse() |> elem(1) |> Enum.to_list()}
    end

    test "returns country and place records", %{places: places} do
      assert length(places) == 8
    end

    test "does not emit subdivision records", %{places: places} do
      refute Enum.any?(places, &(&1.kind == :subdivision))
    end

    test "emits withdrawn countries unfiltered", %{places: places} do
      assert Enum.any?(places, &(&1.id == "ISO:AN"))
    end

    test "builds country records from countryInfo", %{places: places} do
      ad = Enum.find(places, &(&1.id == "ISO:AD"))

      assert ad.kind == :country
      assert ad.capital == "Andorra la Vella"
      assert ad.currency == "EUR"
      assert ad.phone_code == "376"
      assert ad.tld == ".ad"
      assert ad.continent == "EU"
      assert ad.population == 77_006
      assert ad.languages == ["ca"]
      assert ad.neighbours == ["ES", "FR"]
      assert ad.geonames_id == 3_041_565
      assert ad.sources == [:geonames]
      assert ad.metadata.fips == "AN"
      assert ad.metadata.area == 468.0
    end

    test "builds city records", %{places: places} do
      ny = Enum.find(places, &(&1.id == "GN:5128581"))

      assert ny.kind == :city
      assert ny.name == "New York City"
      assert ny.latitude == 40.71427
      assert ny.longitude == -74.00597
      assert ny.population == 8_175_133
      assert ny.elevation == 10
      assert ny.timezone == "America/New_York"
      assert ny.iso_3166_1 == "US"
      assert ny.parent_id == "ISO:US"
      assert ny.ancestor_ids == ["ISO:US"]
      assert ny.geonames_id == 5_128_581
      assert ny.updated_at == ~D[2024-10-19]
      assert ny.sources == [:geonames]
    end

    test "maps P-class non-PPL codes to localities", %{places: places} do
      assert Enum.find(places, &(&1.id == "GN:5128582")).kind == :locality
    end

    test "splits the alternatenames column into :names", %{places: places} do
      lisbon = Enum.find(places, &(&1.id == "GN:2267057"))
      nyc = Enum.find(places, &(&1.id == "GN:5128581"))

      assert lisbon.name == "Lisboa"
      assert lisbon.names == ["Lisbon"]
      assert nyc.names == ["NYC", "New York"]
    end

    test "leaves :names empty when there are no alternates", %{places: places} do
      assert Enum.find(places, &(&1.id == "GN:5128582")).names == []
      assert Enum.find(places, &(&1.id == "ISO:AD")).names == []
    end
  end
end
