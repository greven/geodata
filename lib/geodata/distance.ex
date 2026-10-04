defmodule GeoData.Distance do
  @moduledoc """
  Great-circle (spherical) distance and bearing between coordinates.

  Calculations use the haversine formula on a sphere of mean radius
  `6_371_008.8` metres (the value used by GeoNames and Turf.js). This is
  accurate to a few tenths of a percent versus a WGS84 ellipsoid, which is
  more than enough for search, ranking and proximity. It is not a surveying
  library.

  A point is any of:

    * a `{latitude, longitude}` tuple in decimal degrees
    * a `GeoData.Place` with numeric `:latitude` / `:longitude`
    * a map with numeric `:latitude` / `:longitude`

  Distances default to metres and accept a `:unit` option (`:m`, `:km`, `:mi`
  or `:nm`). Invalid points or units raise `ArgumentError`.

  ## Examples

  ```elixir
  GeoData.Distance.between({48.8566, 2.3522}, {51.5074, -0.1278})
  #=> 343_556.0   (Paris to London, metres)

  GeoData.Distance.between({0.0, 0.0}, {0.0, 1.0}, unit: :km)
  #=> 111.195

  GeoData.Distance.bearing({0.0, 0.0}, {0.0, 1.0})
  #=> 90.0

  GeoData.Distance.within?({0.0, 0.0}, {0.0, 1.0}, 120_000)
  #=> true
  ```

  Places carrying coordinates compose directly, so a point fetched by code can
  be measured without unwrapping it:

  ```elixir
  {:ok, lisbon} = GeoData.place(2_267_057)
  {:ok, nyc} = GeoData.place(5_128_581)
  GeoData.Distance.between(lisbon, nyc)
  ```

  Countries and subdivisions from `iso-codes` have no location and raise
  `ArgumentError`; use a GeoNames place (or `GeoData.near/2`) instead.

  """

  alias GeoData.Place

  @earth_radius 6_371_008.8

  @units %{m: 1.0, km: 1_000.0, mi: 1_609.344, nm: 1_852.0}

  @doc """
  Returns the great-circle distance between two points.

  The result is in metres unless `:unit` is given.

  ## Options

    * `:unit` - `:m` (default), `:km`, `:mi` or `:nm`

  ## Examples

      GeoData.Distance.between({0.0, 0.0}, {0.0, 1.0})
      #=> 111_195.08

      GeoData.Distance.between({0.0, 0.0}, {0.0, 1.0}, unit: :mi)
      #=> 69.093

  """
  def between(a, b, opts \\ []) do
    {lat1, lon1} = normalize_point(a)
    {lat2, lon2} = normalize_point(b)

    haversine(lat1, lon1, lat2, lon2) / unit_factor(opts)
  end

  @doc """
  Returns the initial great-circle bearing from `a` to `b` in degrees.

  The result is in `[0.0, 360.0)`, where `0.0` is north and `90.0` is east.

  ## Examples

      GeoData.Distance.bearing({0.0, 0.0}, {1.0, 0.0})
      #=> 0.0

      GeoData.Distance.bearing({0.0, 0.0}, {0.0, 1.0})
      #=> 90.0

  """
  def bearing(a, b) do
    {lat1, lon1} = normalize_point(a)
    {lat2, lon2} = normalize_point(b)

    phi1 = radians(lat1)
    phi2 = radians(lat2)
    delta_lon = radians(lon2 - lon1)

    y = :math.sin(delta_lon) * :math.cos(phi2)

    x =
      :math.cos(phi1) * :math.sin(phi2) - :math.sin(phi1) * :math.cos(phi2) * :math.cos(delta_lon)

    case degrees(:math.atan2(y, x)) do
      bearing when bearing < 0.0 -> bearing + 360.0
      bearing -> bearing
    end
  end

  @doc """
  Returns the midpoint along the great circle between two points.

  ## Examples

      GeoData.Distance.midpoint({0.0, 0.0}, {0.0, 2.0})
      #=> {0.0, 1.0}

  """
  def midpoint(a, b) do
    {lat1, lon1} = normalize_point(a)
    {lat2, lon2} = normalize_point(b)

    phi1 = radians(lat1)
    lambda1 = radians(lon1)
    phi2 = radians(lat2)
    delta_lon = radians(lon2 - lon1)

    bx = :math.cos(phi2) * :math.cos(delta_lon)
    by = :math.cos(phi2) * :math.sin(delta_lon)

    lat =
      :math.atan2(
        :math.sin(phi1) + :math.sin(phi2),
        :math.sqrt((:math.cos(phi1) + bx) ** 2 + by ** 2)
      )

    lon = lambda1 + :math.atan2(by, :math.cos(phi1) + bx)

    {degrees(lat), normalize_longitude(degrees(lon))}
  end

  @doc """
  Returns the point reached from `a` travelling `distance` on `bearing`.

  `distance` is in metres unless `:unit` is given.

  ## Options

    * `:unit` - `:m` (default), `:km`, `:mi` or `:nm`

  ## Examples

      GeoData.Distance.destination({0.0, 0.0}, 90.0, 111_194.93)
      #=> {0.0, 1.0}

  """
  def destination(a, bearing, distance, opts \\ []) do
    {lat1, lon1} = normalize_point(a)

    delta = distance * unit_factor(opts) / @earth_radius
    theta = radians(bearing)
    phi1 = radians(lat1)
    lambda1 = radians(lon1)

    phi2 =
      :math.asin(
        :math.sin(phi1) * :math.cos(delta) +
          :math.cos(phi1) * :math.sin(delta) * :math.cos(theta)
      )

    lambda2 =
      lambda1 +
        :math.atan2(
          :math.sin(theta) * :math.sin(delta) * :math.cos(phi1),
          :math.cos(delta) - :math.sin(phi1) * :math.sin(phi2)
        )

    {degrees(phi2), normalize_longitude(degrees(lambda2))}
  end

  @doc """
  Returns the bounding box enclosing a circle around `a` with `radius`.

  `radius` is in metres unless `:unit` is given. The result is
  `{min_lat, min_lon, max_lat, max_lon}`. Near a pole the box spans every
  longitude; across the antimeridian `min_lon` is greater than `max_lon` to
  signal the wrap.

  ## Options

    * `:unit` - `:m` (default), `:km`, `:mi` or `:nm`

  ## Examples

      GeoData.Distance.bounding_box({0.0, 0.0}, 111_194.93)
      #=> {-1.0, -1.0, 1.0, 1.0}

  """
  def bounding_box(a, radius, opts \\ []) do
    {lat, lon} = normalize_point(a)

    delta = radius * unit_factor(opts) / @earth_radius
    phi = radians(lat)

    min_lat = degrees(phi - delta)
    max_lat = degrees(phi + delta)

    if min_lat <= -90.0 or max_lat >= 90.0 do
      {max(min_lat, -90.0), -180.0, min(max_lat, 90.0), 180.0}
    else
      delta_lon = degrees(:math.asin(min(:math.sin(delta) / :math.cos(phi), 1.0)))

      {min_lat, normalize_longitude(lon - delta_lon), max_lat,
       normalize_longitude(lon + delta_lon)}
    end
  end

  @doc """
  Returns the coordinate mean of a non-empty list of points.

  This is the average of the latitudes and longitudes, not an area-weighted
  centre.

  ## Examples

      GeoData.Distance.centroid([{0.0, 0.0}, {2.0, 2.0}])
      #=> {1.0, 1.0}

  """
  def centroid(points) when is_list(points) and points != [] do
    {sum_lat, sum_lon, count} =
      Enum.reduce(points, {0.0, 0.0, 0}, fn point, {sum_lat, sum_lon, count} ->
        {lat, lon} = normalize_point(point)
        {sum_lat + lat, sum_lon + lon, count + 1}
      end)

    {sum_lat / count, normalize_longitude(sum_lon / count)}
  end

  def centroid([]), do: raise(ArgumentError, "expected a non-empty list of points")

  @doc """
  Returns whether two points are within `radius` of each other.

  `radius` is in metres unless `:unit` is given.

  ## Options

    * `:unit` - `:m` (default), `:km`, `:mi` or `:nm`

  """
  def within?(a, b, radius, opts \\ []), do: between(a, b, opts) <= radius

  # Formulas

  defp haversine(lat1, lon1, lat2, lon2) do
    phi1 = radians(lat1)
    phi2 = radians(lat2)
    delta_phi = radians(lat2 - lat1)
    delta_lambda = radians(lon2 - lon1)

    a =
      :math.sin(delta_phi / 2) ** 2 +
        :math.cos(phi1) * :math.cos(phi2) * :math.sin(delta_lambda / 2) ** 2

    2 * @earth_radius * :math.asin(:math.sqrt(min(a, 1.0)))
  end

  # Points

  defp normalize_point(%Place{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon),
       do: {lat * 1.0, lon * 1.0}

  defp normalize_point(%Place{} = place),
    do: raise(ArgumentError, "place #{inspect(place.id)} has no coordinates")

  defp normalize_point({lat, lon}) when is_number(lat) and is_number(lon),
    do: {lat * 1.0, lon * 1.0}

  defp normalize_point(%{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon),
       do: {lat * 1.0, lon * 1.0}

  defp normalize_point(point),
    do: raise(ArgumentError, "invalid point: #{inspect(point)}")

  # Units

  defp unit_factor(opts) do
    unit = Keyword.get(opts, :unit, :m)

    case Map.fetch(@units, unit) do
      {:ok, factor} ->
        factor

      :error ->
        raise ArgumentError, "unknown unit: #{inspect(unit)} (expected :m, :km, :mi or :nm)"
    end
  end

  # Maths

  defp radians(degrees), do: degrees * :math.pi() / 180.0
  defp degrees(radians), do: radians * 180.0 / :math.pi()

  defp normalize_longitude(lon) do
    cond do
      lon > 180.0 -> lon - 360.0
      lon < -180.0 -> lon + 360.0
      true -> lon
    end
  end
end
