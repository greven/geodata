defmodule GeoData.FuzzyTest do
  use ExUnit.Case, async: true

  alias GeoData.Fuzzy

  test "identical strings have distance zero" do
    assert Fuzzy.distance("lisbon", "lisbon", 1) == 0
  end

  test "counts a substitution, insertion and deletion" do
    assert Fuzzy.distance("lisbon", "lisbom", 1) == 1
    assert Fuzzy.distance("lisbon", "lisbonne", 2) == 2
    assert Fuzzy.distance("lisbonne", "lisbon", 2) == 2
  end

  test "counts an adjacent transposition as a single edit" do
    assert Fuzzy.distance("lisbon", "lisbno", 1) == 1
    assert Fuzzy.distance("york", "yrok", 1) == 1
  end

  test "works on Unicode codepoints" do
    assert Fuzzy.distance("são", "sao", 1) == 1
    assert Fuzzy.distance("münchen", "munchen", 1) == 1
  end

  test "handles empty strings" do
    assert Fuzzy.distance("", "", 0) == 0
    assert Fuzzy.distance("", "ab", 2) == 2
    assert Fuzzy.distance("ab", "", 2) == 2
  end

  test "returns :too_far past the bound" do
    assert Fuzzy.distance("porto", "lisbon", 1) == :too_far
    assert Fuzzy.distance("lisbon", "lisbom", 0) == :too_far
    assert Fuzzy.distance("a", "abcdef", 2) == :too_far
  end

  test "within?/3 reflects the bounded distance" do
    assert Fuzzy.within?("lisbon", "lisbom", 1)
    refute Fuzzy.within?("lisbon", "lisbom", 0)
    refute Fuzzy.within?("porto", "lisbon", 2)
  end
end
