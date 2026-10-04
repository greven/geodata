defmodule GeoData.IDTest do
  use ExUnit.Case, async: true
  doctest GeoData.ID

  alias GeoData.ID

  describe "for_country/1" do
    test "builds an ISO id, normalizing case, whitespace and atoms" do
      assert ID.for_country("PT") == "ISO:PT"
      assert ID.for_country("pt") == "ISO:PT"
      assert ID.for_country(" Pt ") == "ISO:PT"
      assert ID.for_country(:pt) == "ISO:PT"
      assert ID.for_country(:PT) == "ISO:PT"
    end
  end

  describe "for_subdivision/1" do
    test "builds an ISO id, normalizing case, whitespace and atoms" do
      assert ID.for_subdivision("US-CA") == "ISO:US-CA"
      assert ID.for_subdivision("us-ca") == "ISO:US-CA"
      assert ID.for_subdivision(:"US-CA") == "ISO:US-CA"
    end
  end

  describe "for_geonames/1" do
    test "accepts an integer or numeric string" do
      assert ID.for_geonames(5_128_581) == "GN:5128581"
      assert ID.for_geonames("5128581") == "GN:5128581"
      assert ID.for_geonames(" 5128581 ") == "GN:5128581"
    end

    test "raises on a non-numeric string" do
      assert_raise ArgumentError, fn -> ID.for_geonames("abc") end
    end
  end

  describe "parse/1" do
    test "round-trips valid ids" do
      assert ID.parse("ISO:PT") == {:ok, {:iso, "PT"}}
      assert ID.parse("ISO:US-CA") == {:ok, {:iso, "US-CA"}}
      assert ID.parse("GN:5128581") == {:ok, {:geonames, 5_128_581}}
    end

    test "normalizes case and accepts atoms" do
      assert ID.parse("iso:pt") == {:ok, {:iso, "PT"}}
      assert ID.parse("iso:us-ca") == {:ok, {:iso, "US-CA"}}
      assert ID.parse(:"ISO:PT") == {:ok, {:iso, "PT"}}
    end

    test "rejects invalid ids" do
      assert ID.parse("nope") == {:error, :invalid_id}
      assert ID.parse("GN:abc") == {:error, :invalid_id}
      assert ID.parse("ISO:") == {:error, :invalid_id}
      assert ID.parse("GN:") == {:error, :invalid_id}
      assert ID.parse(nil) == {:error, :invalid_id}
    end
  end
end
