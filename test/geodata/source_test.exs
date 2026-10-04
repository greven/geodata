defmodule GeoData.SourceTest do
  use ExUnit.Case, async: true

  alias GeoData.Options
  alias GeoData.Source

  test "available/0 lists the registered sources" do
    assert Enum.sort(Source.available()) == [:geonames, :iso_codes]
  end

  test "resolve/1 returns the registered sources for the tier" do
    opts = Options.config_options(dataset: :base, sources: [:iso_codes])
    assert Source.resolve(opts) == {:ok, [GeoData.Source.IsoCodes]}

    opts = Options.config_options(dataset: :cities, sources: [:iso_codes, :geonames])

    assert Source.resolve(opts) == {:ok, [GeoData.Source.IsoCodes, GeoData.Source.Geonames]}
  end

  test "resolve/1 ignores sources outside the tier" do
    opts = Options.config_options(dataset: :base, sources: [:iso_codes, :geonames])
    assert Source.resolve(opts) == {:ok, [GeoData.Source.IsoCodes]}
  end
end
