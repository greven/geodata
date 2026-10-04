defmodule GeoData.Stats.Country do
  @moduledoc """
  Statistics for a single country and the places stored under it.

  Returned by `GeoData.Stats.country/2`.

  ## Fields

    * `:place` - the country `GeoData.Place`
    * `:subdivisions` - number of stored subdivisions
    * `:cities` - number of stored cities
    * `:localities` - number of stored localities
    * `:population` - country population from GeoNames, when known
    * `:largest_cities` - the country's most populous cities
    * `:neighbours` - bordering countries as `GeoData.Place` records

  """

  defstruct place: nil,
            subdivisions: 0,
            cities: 0,
            localities: 0,
            population: nil,
            largest_cities: [],
            neighbours: []
end
