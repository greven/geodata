defmodule GeoData.SearchFixtures do
  @moduledoc false

  alias GeoData.Place

  def places do
    [
      Place.new!(
        id: "ISO:PT",
        kind: :country,
        iso_3166_1: "PT",
        name: "Portugal",
        capital: "Lisbon",
        continent: "EU",
        population: 10_305_598,
        sources: [:iso_codes]
      ),
      Place.new!(
        id: "ISO:BR",
        kind: :country,
        iso_3166_1: "BR",
        name: "Brazil",
        continent: "SA",
        population: 209_469_323,
        sources: [:iso_codes]
      ),
      Place.new!(
        id: "ISO:US-CA",
        kind: :subdivision,
        iso_3166_1: "US",
        iso_3166_2: "US-CA",
        name: "California",
        continent: "NA",
        population: 39_000_000,
        sources: [:iso_codes]
      ),
      Place.new!(
        id: "GN:2267057",
        kind: :city,
        geonames_id: 2_267_057,
        iso_3166_1: "PT",
        name: "Lisbon",
        ascii_name: "Lisbon",
        latitude: 38.71667,
        longitude: -9.13333,
        population: 548_703,
        feature_class: "P",
        feature_code: "PPLC",
        timezone: "Europe/Lisbon",
        sources: [:geonames]
      ),
      Place.new!(
        id: "GN:3448439",
        kind: :city,
        geonames_id: 3_448_439,
        iso_3166_1: "BR",
        name: "São Paulo",
        ascii_name: "Sao Paulo",
        latitude: -23.55052,
        longitude: -46.63331,
        population: 10_021_295,
        feature_class: "P",
        feature_code: "PPL",
        timezone: "America/Sao_Paulo",
        sources: [:geonames]
      ),
      Place.new!(
        id: "GN:5128581",
        kind: :city,
        geonames_id: 5_128_581,
        iso_3166_1: "US",
        name: "New York City",
        ascii_name: "New York City",
        latitude: 40.71427,
        longitude: -74.00597,
        population: 8_175_133,
        feature_class: "P",
        feature_code: "PPL",
        timezone: "America/New_York",
        sources: [:geonames]
      ),
      Place.new!(
        id: "GN:2867714",
        kind: :city,
        geonames_id: 2_867_714,
        iso_3166_1: "DE",
        name: "München",
        ascii_name: "Munich",
        latitude: 48.13743,
        longitude: 11.57549,
        population: 1_260_391,
        feature_class: "P",
        feature_code: "PPL",
        timezone: "Europe/Berlin",
        names: ["Monaco di Baviera"],
        sources: [:geonames]
      ),
      Place.new!(
        id: "GN:1863967",
        kind: :feature,
        geonames_id: 1_863_967,
        iso_3166_1: "JP",
        name: "Mount Fuji",
        ascii_name: "Mount Fuji",
        latitude: 35.36056,
        longitude: 138.72750,
        feature_class: "T",
        feature_code: "MT",
        timezone: "Asia/Tokyo",
        sources: [:geonames]
      )
    ]
  end
end

defmodule GeoData.SearchFixtures.Stub do
  @moduledoc false
  @behaviour GeoData.Search

  @impl true
  def search(_text, _opts) do
    {:ok, %GeoData.Search.Result{places: [:stub], total: 1, limit: 20, offset: 0}}
  end

  @impl true
  def stream(_text, _opts), do: [:stub]
end
