defmodule GeoData.Search.QueryTest do
  use ExUnit.Case, async: true

  alias GeoData.Place
  alias GeoData.Search.Query
  alias GeoData.ValidationError

  test "weights primary name matches above alternate-name matches" do
    {:ok, query} = Query.parse("lisbon", [])

    primary = Place.new!(kind: :city, name: "Lisbon")

    alternate =
      Place.new!(
        kind: :city,
        name: "Campo Pequeno",
        names: ["Campo Pequeno  Lisbon  Portugal"]
      )

    assert {:ok, primary_score} = Query.match(primary, query)
    assert {:ok, alternate_score} = Query.match(alternate, query)

    assert primary_score > alternate_score
  end

  test "expands feature code groups to their codes" do
    {:ok, capital} = Query.parse(nil, where: [feature_code: :capital])
    assert capital.where[:feature_code] == ["PPLC"]

    {:ok, city} = Query.parse(nil, where: [feature_code: :city])
    assert "PPL" in city.where[:feature_code]
    assert "PPLC" in city.where[:feature_code]

    {:ok, mixed} = Query.parse(nil, where: [feature_code: [:capital, "PPLX"]])
    assert Enum.sort(mixed.where[:feature_code]) == ["PPLC", "PPLX"]
  end

  test "expands semantic feature groups without knowing codes" do
    {:ok, mountain} = Query.parse(nil, where: [feature_code: :mountain])
    assert mountain.where[:feature_code] == ["MT", "MTS"]

    {:ok, mixed} = Query.parse(nil, where: [feature_code: [:lake, "VLC"]])
    assert "LK" in mixed.where[:feature_code]
    assert "VLC" in mixed.where[:feature_code]
  end

  test "expands feature class aliases" do
    {:ok, landforms} = Query.parse(nil, where: [feature_class: :landforms])
    assert landforms.where[:feature_class] == ["T"]

    {:ok, raw} = Query.parse(nil, where: [feature_class: "t"])
    assert raw.where[:feature_class] == ["T"]

    {:ok, mixed} = Query.parse(nil, where: [feature_class: [:hydrography, "V"]])
    assert Enum.sort(mixed.where[:feature_class]) == ["H", "V"]
  end

  test "rejects unknown feature code groups" do
    assert {:error, %ValidationError{reason: :invalid_option}} =
             Query.parse(nil, where: [feature_code: :bogus])
  end

  test "rejects unknown feature class aliases" do
    assert {:error, %ValidationError{reason: :invalid_option}} =
             Query.parse(nil, where: [feature_class: :bogus])
  end

  test "parses proximity filters" do
    {:ok, query} = Query.parse(nil, where: [near: {38.7, -9.1, 50_000}])
    assert query.where[:near] == {38.7, -9.1, 50_000}
  end

  test "parses distance ordering" do
    {:ok, query} = Query.parse(nil, order_by: {:distance, {38.7, -9.1}})
    assert query.order == {:distance, {38.7, -9.1}}
  end

  test "rejects malformed proximity options" do
    assert {:error, %ValidationError{reason: :invalid_option}} =
             Query.parse(nil, where: [near: {1.0, 2.0}])

    assert {:error, %ValidationError{reason: :invalid_option, field: :order_by}} =
             Query.parse(nil, order_by: {:distance, :nope})

    assert {:error, %ValidationError{reason: :invalid_option}} =
             Query.parse(nil, order_by: :distance)
  end

  test "parses fuzzy matching and its fuzziness" do
    {:ok, query} = Query.parse("lisbom", match: :fuzzy)
    assert query.match == :fuzzy
    assert query.fuzziness == 1

    {:ok, wide} = Query.parse("lisbom", match: :fuzzy, fuzziness: 2)
    assert wide.fuzziness == 2
  end

  test "rejects an out-of-range fuzziness" do
    assert {:error, %ValidationError{reason: :invalid_option}} =
             Query.parse("x", match: :fuzzy, fuzziness: 3)
  end

  test "orders names case-insensitively" do
    {:ok, query} = Query.parse(nil, order_by: :name)
    banana = Place.new!(id: "ISO:BB", kind: :city, name: "Banana")
    apple = Place.new!(id: "ISO:AA", kind: :city, name: "apple")

    assert [{^apple, _}, {^banana, _}] = Query.sort([{banana, 0}, {apple, 0}], query)
  end

  test "breaks ordering ties by id" do
    {:ok, query} = Query.parse(nil, order_by: {:population, :desc})
    a = Place.new!(id: "ISO:AA", kind: :city, name: "A", population: 5)
    b = Place.new!(id: "ISO:BB", kind: :city, name: "B", population: 5)

    assert [{^a, _}, {^b, _}] = Query.sort([{b, 0}, {a, 0}], query)
  end

  test "a non-empty query that normalizes to nothing matches nothing" do
    {:ok, query} = Query.parse("!!!", [])
    place = Place.new!(kind: :city, name: "Lisbon")
    assert Query.match(place, query) == :nomatch

    {:ok, blank} = Query.parse(nil, [])
    assert {:ok, 0} = Query.match(place, blank)
  end

  test "matches an antimeridian-wrapping bbox" do
    {:ok, query} = Query.parse(nil, where: [bbox: {-1.0, 179.0, 1.0, -179.0}])

    east = Place.new!(kind: :city, name: "East", latitude: 0.0, longitude: 179.5)
    west = Place.new!(kind: :city, name: "West", latitude: 0.0, longitude: -179.5)
    middle = Place.new!(kind: :city, name: "Middle", latitude: 0.0, longitude: 0.0)

    assert Query.filters?(east, query)
    assert Query.filters?(west, query)
    refute Query.filters?(middle, query)
  end
end
