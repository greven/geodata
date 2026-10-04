defmodule GeoData.LanguageTest do
  use ExUnit.Case, async: true

  doctest GeoData.Language

  alias GeoData.Language
  alias GeoData.Place
  alias GeoData.UnknownCodeError

  test "get/2 returns a localized language" do
    assert {:ok, language} = Language.get("en")
    assert language.code == "en"
    assert language.name == "English"
  end

  test "get/2 accepts atoms" do
    assert {:ok, %{code: "de", name: "German"}} = Language.get(:de)
  end

  test "get!/2 raises for an unknown code" do
    assert_raise UnknownCodeError, ~r/unknown language code/, fn -> Language.get!("zz") end
  end

  test "get/2 returns an error for an unknown code" do
    assert {:error, %UnknownCodeError{field: :language, value: "zz", reason: :unknown_code}} =
             Language.get("zz")
  end

  test "valid?/1 checks known languages" do
    assert Language.valid?("en")
    refute Language.valid?("zz")
  end

  test "for_country/1 names a place's languages" do
    place = Place.new!(kind: :country, languages: ["pt", "gl"])

    assert {:ok, languages} = Language.for_country(place)
    assert Enum.map(languages, &{&1.code, &1.name}) == [{"pt", "Portuguese"}, {"gl", "Galician"}]
  end

  test "for_country/1 returns an empty list when nothing is known" do
    assert {:ok, []} = Language.for_country("ZZ")
    assert {:ok, []} = Language.for_country(nil)
  end

  test "codes/0 returns a list of language codes" do
    assert is_list(Language.codes())
  end
end
