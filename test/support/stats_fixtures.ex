defmodule GeoData.StatsFixtures do
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
        neighbours: ["ES"],
        sources: [:iso_codes, :geonames]
      ),
      Place.new!(
        id: "ISO:ES",
        kind: :country,
        iso_3166_1: "ES",
        name: "Spain",
        capital: "Madrid",
        continent: "EU",
        population: 47_000_000,
        neighbours: ["PT", "FR"],
        sources: [:iso_codes, :geonames]
      ),
      Place.new!(
        id: "ISO:FR",
        kind: :country,
        iso_3166_1: "FR",
        name: "France",
        capital: "Paris",
        continent: "EU",
        population: 67_000_000,
        neighbours: ["ES"],
        sources: [:iso_codes, :geonames]
      ),
      Place.new!(
        id: "ISO:PT-11",
        kind: :subdivision,
        iso_3166_1: "PT",
        iso_3166_2: "PT-11",
        name: "Lisboa",
        parent_id: "ISO:PT",
        ancestor_ids: ["ISO:PT"],
        sources: [:iso_codes]
      ),
      Place.new!(
        id: "ISO:ES-MD",
        kind: :subdivision,
        iso_3166_1: "ES",
        iso_3166_2: "ES-MD",
        name: "Madrid",
        parent_id: "ISO:ES",
        ancestor_ids: ["ISO:ES"],
        sources: [:iso_codes]
      ),
      Place.new!(
        id: "GN:2267057",
        kind: :city,
        geonames_id: 2_267_057,
        iso_3166_1: "PT",
        name: "Lisbon",
        latitude: 38.71667,
        longitude: -9.13333,
        population: 548_703,
        feature_class: "P",
        feature_code: "PPLC",
        sources: [:geonames]
      ),
      Place.new!(
        id: "GN:2267058",
        kind: :locality,
        geonames_id: 2_267_058,
        iso_3166_1: "PT",
        name: "Parque das Nações",
        latitude: 38.767,
        longitude: -9.095,
        population: 21_000,
        feature_class: "P",
        feature_code: "PPLX",
        sources: [:geonames]
      ),
      Place.new!(
        id: "GN:3117735",
        kind: :city,
        geonames_id: 3_117_735,
        iso_3166_1: "ES",
        name: "Madrid",
        latitude: 40.4165,
        longitude: -3.70256,
        population: 3_255_944,
        feature_class: "P",
        feature_code: "PPLC",
        sources: [:geonames]
      ),
      Place.new!(
        id: "GN:3128760",
        kind: :city,
        geonames_id: 3_128_760,
        iso_3166_1: "ES",
        name: "Barcelona",
        latitude: 41.38879,
        longitude: 2.15899,
        population: 1_620_809,
        feature_class: "P",
        feature_code: "PPLA",
        sources: [:geonames]
      ),
      Place.new!(
        id: "GN:2988507",
        kind: :city,
        geonames_id: 2_988_507,
        iso_3166_1: "FR",
        name: "Paris",
        latitude: 48.85341,
        longitude: 2.3488,
        population: 2_138_551,
        feature_class: "P",
        feature_code: "PPLC",
        sources: [:geonames]
      )
    ]
  end
end
