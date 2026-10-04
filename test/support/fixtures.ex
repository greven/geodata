defmodule GeoData.Fixtures do
  @moduledoc false

  @dir Path.expand("../fixtures", __DIR__)

  def path(name), do: Path.join(@dir, name)

  def iso_3166_paths do
    %{
      iso_3166_1: path("iso_3166-1.json"),
      iso_3166_2: path("iso_3166-2.json"),
      iso_3166_3: path("iso_3166-3.json")
    }
  end

  def geonames_paths do
    %{
      geonames_country_info: path("geonames/countryInfo.txt"),
      geonames_places: path("geonames/cities1000.txt")
    }
  end

  def all_paths, do: Map.merge(iso_3166_paths(), geonames_paths())
end
