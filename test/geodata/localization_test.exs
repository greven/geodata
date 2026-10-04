defmodule GeoData.LocalizationTest do
  use ExUnit.Case, async: true

  alias GeoData.Place

  # Localize bundles `:en`; other locales are loaded from downloaded locale
  # data (mix localize.download_locales), so these tests use `:en`.

  describe "country localization" do
    test "translates a country via CLDR" do
      place = Place.new!(kind: :country, iso_3166_1: "DE")

      assert Place.display_name(place, :en) == {:ok, "Germany"}
      assert Place.display_name!(place, :en) == "Germany"
    end

    test "supports CLDR styles" do
      place = Place.new!(kind: :country, iso_3166_1: "GB")

      assert Place.display_name(place, :en) == {:ok, "United Kingdom"}
      assert Place.display_name(place, :en, style: :short) == {:ok, "UK"}
    end
  end

  describe "subdivision localization" do
    test "translates a subdivision via CLDR" do
      place = Place.new!(kind: :subdivision, iso_3166_2: "US-CA")

      assert {:ok, name} = Place.display_name(place, :en)
      assert name == Localize.Territory.Subdivision.display_name!("usca", locale: :en)
      assert name == "California"
    end

    test "falls back to the canonical name when CLDR has no translation" do
      place = Place.new!(kind: :subdivision, iso_3166_2: "ZZ-ZZ", name: "Nowhere")

      assert Place.display_name(place, :en) == {:ok, "Nowhere"}
    end
  end

  describe "unavailable locales" do
    test "silently falls back to the canonical name" do
      place = Place.new!(kind: :country, iso_3166_1: "DE", name: "Deutschland")

      assert Place.display_name(place, :tlh) == {:ok, "Deutschland"}
    end
  end

  test "cities keep their canonical name" do
    place = Place.new!(kind: :city, name: "Lisbon")

    assert Place.display_name(place, :en) == {:ok, "Lisbon"}
  end
end
