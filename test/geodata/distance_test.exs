defmodule GeoData.DistanceTest do
  use ExUnit.Case, async: true

  alias GeoData.Distance
  alias GeoData.Place

  @paris {48.8566, 2.3522}
  @london {51.5074, -0.1278}

  describe "between/3" do
    test "measures a known great-circle distance" do
      assert_in_delta Distance.between(@paris, @london), 343_556.0, 200.0

      assert_in_delta Distance.between({51.4700, -0.4543}, {40.6413, -73.7781}),
                      5_540_019.0,
                      2_000.0

      assert_in_delta Distance.between({0.0, 0.0}, {0.0, 1.0}), 111_195.0, 5.0
    end

    test "is symmetric and zero for the same point" do
      assert Distance.between(@paris, @london) == Distance.between(@london, @paris)
      assert Distance.between(@paris, @paris) == 0.0
    end

    test "converts units" do
      assert_in_delta Distance.between({0.0, 0.0}, {0.0, 1.0}, unit: :km), 111.195, 0.01
      assert_in_delta Distance.between({0.0, 0.0}, {0.0, 1.0}, unit: :mi), 69.093, 0.01
      assert_in_delta Distance.between({0.0, 0.0}, {0.0, 1.0}, unit: :nm), 60.041, 0.01
    end

    test "accepts places and maps" do
      place = Place.new!(kind: :city, latitude: 0.0, longitude: 0.0)
      map = %{latitude: 0.0, longitude: 1.0}

      assert_in_delta Distance.between(place, map), 111_195.0, 5.0
    end

    test "raises for invalid points and units" do
      assert_raise ArgumentError, fn ->
        apply(Distance, :between, [{1.0, 2.0, 3.0}, {0.0, 0.0}])
      end

      assert_raise ArgumentError, fn -> apply(Distance, :between, [:foo, {0.0, 0.0}]) end

      assert_raise ArgumentError, fn ->
        apply(Distance, :between, [{0.0, 0.0}, {0.0, 1.0}, [unit: :parsec]])
      end

      assert_raise ArgumentError, fn ->
        apply(Distance, :between, [Place.new!(kind: :country, iso_3166_1: "PT"), {0.0, 0.0}])
      end
    end
  end

  describe "bearing/2" do
    test "returns compass bearings" do
      assert_in_delta Distance.bearing({0.0, 0.0}, {1.0, 0.0}), 0.0, 0.01
      assert_in_delta Distance.bearing({0.0, 0.0}, {0.0, 1.0}), 90.0, 0.01
      assert_in_delta Distance.bearing({0.0, 0.0}, {-1.0, 0.0}), 180.0, 0.01
      assert_in_delta Distance.bearing({0.0, 0.0}, {0.0, -1.0}), 270.0, 0.01
    end
  end

  describe "midpoint/2" do
    test "returns the point halfway along the great circle" do
      {lat, lon} = Distance.midpoint({0.0, 0.0}, {0.0, 2.0})
      assert_in_delta lat, 0.0, 0.0001
      assert_in_delta lon, 1.0, 0.0001
    end

    test "is symmetric" do
      {a, b} = Distance.midpoint(@paris, @london)
      {c, d} = Distance.midpoint(@london, @paris)

      assert_in_delta a, c, 0.0000001
      assert_in_delta b, d, 0.0000001
    end
  end

  describe "destination/4" do
    test "reaches the expected point travelling east on the equator" do
      {lat, lon} = Distance.destination({0.0, 0.0}, 90.0, 111_195.0)
      assert_in_delta lat, 0.0, 0.001
      assert_in_delta lon, 1.0, 0.001
    end

    test "inverts bearing/2 and between/3" do
      {lat, lon} =
        Distance.destination(
          @paris,
          Distance.bearing(@paris, @london),
          Distance.between(@paris, @london)
        )

      {expected_lat, expected_lon} = @london

      assert_in_delta lat, expected_lat, 0.001
      assert_in_delta lon, expected_lon, 0.001
    end
  end

  describe "bounding_box/3" do
    test "encloses the point" do
      {min_lat, min_lon, max_lat, max_lon} = Distance.bounding_box({0.0, 0.0}, 111_195.0)

      assert_in_delta min_lat, -1.0, 0.01
      assert_in_delta min_lon, -1.0, 0.01
      assert_in_delta max_lat, 1.0, 0.01
      assert_in_delta max_lon, 1.0, 0.01
    end

    test "spans every longitude near a pole" do
      {min_lat, min_lon, max_lat, max_lon} = Distance.bounding_box({89.0, 0.0}, 200_000.0)

      assert max_lat == 90.0
      assert min_lon == -180.0
      assert max_lon == 180.0
      assert min_lat > 80.0
    end

    test "signals an antimeridian wrap with min_lon greater than max_lon" do
      {_min_lat, min_lon, _max_lat, max_lon} = Distance.bounding_box({0.0, 179.9}, 22_239.0)

      assert min_lon > max_lon
    end
  end

  describe "centroid/1" do
    test "averages the coordinates" do
      assert Distance.centroid([{0.0, 0.0}, {2.0, 2.0}]) == {1.0, 1.0}
    end

    test "raises for an empty list" do
      assert_raise ArgumentError, fn -> Distance.centroid([]) end
    end
  end

  describe "within?/4" do
    test "checks a radius in metres" do
      assert Distance.within?(@paris, @london, 344_000.0)
      refute Distance.within?(@paris, @london, 343_000.0)
      assert Distance.within?(@paris, @london, 344.0, unit: :km)
    end
  end
end
