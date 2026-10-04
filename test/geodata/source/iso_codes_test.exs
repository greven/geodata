defmodule GeoData.Source.IsoCodesTest do
  use ExUnit.Case, async: true

  alias GeoData.Fixtures
  alias GeoData.IngestError
  alias GeoData.Place
  alias GeoData.Source.IsoCodes

  setup do
    {:ok, paths: Fixtures.iso_3166_paths()}
  end

  describe "files/1" do
    test "declares the three iso-codes json files" do
      files = IsoCodes.files()

      assert Enum.map(files, & &1.key) == [:iso_3166_1, :iso_3166_2, :iso_3166_3]
      assert Enum.all?(files, &(&1.format == :json))
      assert Enum.all?(files, &String.starts_with?(&1.url, "https://"))
    end
  end

  describe "parse/2" do
    test "returns countries and subdivisions", %{paths: paths} do
      assert {:ok, places} = IsoCodes.parse(paths)
      assert length(places) == 6
      assert Enum.all?(places, &match?(%Place{}, &1))
    end

    test "builds country places", %{paths: paths} do
      {:ok, places} = IsoCodes.parse(paths)
      pt = Enum.find(places, &(&1.id == "ISO:PT"))

      assert pt.kind == :country
      assert pt.iso_3166_1 == "PT"
      assert pt.name == "Portugal"
      assert pt.flag_emoji == "🇵🇹"
      assert pt.sources == [:iso_codes]
      assert pt.metadata.alpha_3 == "PRT"
      assert pt.metadata.numeric == "620"
      assert pt.metadata.official_name == "Portuguese Republic"
    end

    test "computes a flag emoji when one is missing", %{paths: paths} do
      {:ok, places} = IsoCodes.parse(paths)
      assert Enum.find(places, &(&1.id == "ISO:AW")).flag_emoji == "🇦🇼"
    end

    test "enriches a country from a matching former code", %{paths: paths} do
      {:ok, places} = IsoCodes.parse(paths)
      mm = Enum.find(places, &(&1.id == "ISO:MM"))

      assert mm.iso_3166_3 == "BUMM"
      assert mm.metadata.former.name =~ "Burma"
    end

    test "leaves the former code unset when no numeric matches", %{paths: paths} do
      {:ok, places} = IsoCodes.parse(paths)
      pt = Enum.find(places, &(&1.id == "ISO:PT"))

      assert pt.iso_3166_3 == nil
      refute Map.has_key?(pt.metadata, :former)
    end

    test "builds subdivision places", %{paths: paths} do
      {:ok, places} = IsoCodes.parse(paths)
      ca = Enum.find(places, &(&1.id == "ISO:US-CA"))

      assert ca.kind == :subdivision
      assert ca.iso_3166_1 == "US"
      assert ca.iso_3166_2 == "US-CA"
      assert ca.parent_id == "ISO:US"
      assert ca.ancestor_ids == ["ISO:US"]
      assert ca.name == "California"
      assert ca.metadata.type == "State"
    end

    test "returns an error when a file is missing" do
      paths = %{iso_3166_1: "/nope.json", iso_3166_2: "/nope.json"}

      assert {:error, %IngestError{source: :iso_codes, reason: :missing_file}} =
               IsoCodes.parse(paths)
    end

    test "returns an error for invalid json", %{paths: paths} do
      tmp =
        Path.join(System.tmp_dir!(), "geodata-invalid-#{System.unique_integer([:positive])}.json")

      File.write!(tmp, "not json")
      on_exit(fn -> File.rm(tmp) end)

      paths = Map.put(paths, :iso_3166_1, tmp)

      assert {:error, %IngestError{source: :iso_codes, reason: :invalid_format}} =
               IsoCodes.parse(paths)
    end
  end
end
