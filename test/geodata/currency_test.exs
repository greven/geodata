defmodule GeoData.CurrencyTest do
  use ExUnit.Case, async: true

  doctest GeoData.Currency

  alias GeoData.Currency
  alias GeoData.Place
  alias GeoData.UnknownCodeError

  test "get/2 returns a localized currency" do
    assert {:ok, currency} = Currency.get("EUR")
    assert currency.code == "EUR"
    assert currency.name == "Euro"
    assert currency.symbol == "€"
    assert currency.tender
  end

  test "get/2 is case-insensitive and accepts atoms" do
    assert {:ok, %{code: "EUR"}} = Currency.get("eur")
    assert {:ok, %{code: "EUR"}} = Currency.get(:eur)
  end

  test "get!/2 raises for an unknown code" do
    assert_raise UnknownCodeError, ~r/unknown currency code/, fn -> Currency.get!("XYZ") end
  end

  test "get/2 returns an error for an unknown code" do
    assert {:error, %UnknownCodeError{field: :currency, value: "XYZ", reason: :unknown_code}} =
             Currency.get("XYZ")
  end

  test "valid?/1 checks known codes" do
    assert Currency.valid?("EUR")
    refute Currency.valid?("XYZ")
  end

  test "codes/0 returns currency codes" do
    codes = Currency.codes()
    assert "USD" in codes
    assert "EUR" in codes
  end

  test "for_country/1 resolves a code or place to its current currency" do
    assert {:ok, [%{code: "USD"}]} = Currency.for_country("US")
    assert {:ok, [%{code: "USD"}]} = Currency.for_country(:US)

    place = Place.new!(kind: :country, iso_3166_1: "PT")
    assert {:ok, [%{code: "EUR"}]} = Currency.for_country(place)
  end

  test "for_country/1 falls back to the stored currency" do
    place = Place.new!(kind: :country, iso_3166_1: "ZZ", currency: "EUR")
    assert {:ok, [%{code: "EUR"}]} = Currency.for_country(place)
  end

  test "for_country/1 returns an empty list when nothing is known" do
    assert {:ok, []} = Currency.for_country("ZZ")
    assert {:ok, []} = Currency.for_country(nil)
  end
end
