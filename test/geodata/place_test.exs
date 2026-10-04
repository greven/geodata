defmodule GeoData.PlaceTest do
  use ExUnit.Case, async: true
  doctest GeoData.Place

  alias GeoData.NoNameError
  alias GeoData.Place
  alias GeoData.ValidationError

  test "defaults collection fields" do
    place = %Place{}

    assert place.id == nil
    assert place.ancestor_ids == []
    assert place.sources == []
    assert place.names == []
    assert place.languages == []
    assert place.neighbours == []
    assert place.metadata == %{}
  end

  test "kinds/0 lists the supported place kinds" do
    assert :country in Place.kinds()
    assert :subdivision in Place.kinds()
    assert :city in Place.kinds()
  end

  describe "new/1" do
    test "builds a valid place from a keyword list" do
      assert {:ok, %Place{kind: :country, iso_3166_1: "PT"} = place} =
               Place.new(kind: :country, iso_3166_1: "PT")

      assert place.ancestor_ids == []
    end

    test "builds a valid place from a map" do
      assert {:ok, %Place{kind: :city}} = Place.new(%{kind: :city})
    end

    test "ignores unknown attributes" do
      assert {:ok, %Place{kind: :city}} = Place.new(kind: :city, unknown: 1)
    end

    test "requires :kind" do
      assert {:error, %ValidationError{field: :kind, reason: :missing}} =
               Place.new(iso_3166_1: "PT")
    end

    test "rejects an unknown kind" do
      assert {:error,
              %ValidationError{
                field: :kind,
                value: :county,
                reason: :invalid_kind,
                allowed_values: allowed
              }} = Place.new(kind: :county)

      assert allowed == Place.kinds()
    end

    test "rejects invalid optional field types" do
      assert {:error, %ValidationError{field: :names, reason: :invalid_type, expected: :list}} =
               Place.new(kind: :city, names: %{})

      assert {:error, %ValidationError{field: :id, reason: :invalid_type, expected: :binary}} =
               Place.new(kind: :city, id: 1)

      assert {:error, %ValidationError{field: :metadata, reason: :invalid_type, expected: :map}} =
               Place.new(kind: :city, metadata: [])
    end
  end

  describe "new!/1" do
    test "returns the place" do
      assert %Place{kind: :city, name: "Lisbon"} = Place.new!(kind: :city, name: "Lisbon")
    end

    test "raises on invalid attributes" do
      assert_raise ValidationError, fn -> Place.new!(kind: :county) end
    end
  end

  describe "display_name/3" do
    test "falls back to the canonical name for cities" do
      place = Place.new!(kind: :city, name: "Lisbon")

      assert Place.display_name(place, :en) == {:ok, "Lisbon"}
    end

    test "falls back to CLDR for countries" do
      place = Place.new!(kind: :country, iso_3166_1: "PT")

      assert Place.display_name(place, :en) == {:ok, "Portugal"}
    end

    test "uses the current locale by default" do
      place = Place.new!(kind: :country, iso_3166_1: "PT")

      assert Place.display_name(place) == Place.display_name(place, Localize.get_locale())
    end

    test "returns an error when no name is available" do
      assert {:error, %NoNameError{}} = Place.display_name(Place.new!(kind: :city), :en)
    end
  end

  describe "display_name!/3" do
    test "returns the name" do
      place = Place.new!(kind: :city, name: "Lisbon")

      assert Place.display_name!(place, :en) == "Lisbon"
    end

    test "raises when no name is available" do
      assert_raise NoNameError, fn ->
        Place.display_name!(Place.new!(kind: :city), :en)
      end
    end
  end

  describe "merge/2" do
    test "fills nil fields from the override" do
      base = Place.new!(kind: :country, iso_3166_1: "PT")
      override = Place.new!(kind: :country, iso_3166_1: "PT", name: "Portugal")

      merged = Place.merge(base, override)

      assert merged.name == "Portugal"
      assert merged.iso_3166_1 == "PT"
    end

    test "keeps base fields over the override" do
      base = Place.new!(kind: :country, name: "Portugal")
      override = Place.new!(kind: :country, name: "Other")

      assert Place.merge(base, override).name == "Portugal"
    end

    test "unions names" do
      base = Place.new!(kind: :country, names: ["Portugal"])
      override = Place.new!(kind: :country, names: ["Portuguese Republic", "Portugal"])

      merged = Place.merge(base, override)

      assert merged.names == ["Portugal", "Portuguese Republic"]
    end

    test "unions collection fields" do
      base =
        Place.new!(
          kind: :country,
          sources: [:iso_codes],
          languages: ["pt"],
          neighbours: ["ES"],
          ancestor_ids: ["ISO:EU"]
        )

      override =
        Place.new!(
          kind: :country,
          sources: [:geonames],
          languages: ["pt", "en"],
          neighbours: ["ES", "FR"],
          ancestor_ids: ["ISO:EU", "ISO:WW"]
        )

      merged = Place.merge(base, override)

      assert merged.sources == [:iso_codes, :geonames]
      assert merged.languages == ["pt", "en"]
      assert merged.neighbours == ["ES", "FR"]
      assert merged.ancestor_ids == ["ISO:EU", "ISO:WW"]
    end

    test "merges metadata with base precedence" do
      base = Place.new!(kind: :country, metadata: %{a: 1, b: 2})
      override = Place.new!(kind: :country, metadata: %{b: 3, c: 4})

      assert Place.merge(base, override).metadata == %{a: 1, b: 2, c: 4}
    end
  end
end
