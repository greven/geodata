if Code.ensure_loaded?(Postgrex) do
  defmodule GeodataIntegration.ExplainTaskTest do
    use ExUnit.Case, async: false

    @moduletag :postgres

    use GeodataIntegration.PostgresCase

    import ExUnit.CaptureIO

    alias GeoData.Place

    setup do
      GeoData.put_many([
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
          sources: [:geonames]
        ),
        Place.new!(id: "ISO:PT", kind: :country, iso_3166_1: "PT", name: "Portugal"),
        Place.new!(id: "ISO:BR", kind: :country, iso_3166_1: "BR", name: "Brazil")
      ])

      :ok
    end

    test "prints EXPLAIN plans for a search" do
      output = capture_io(fn -> Mix.Tasks.Geodata.Explain.run(["lisbon"]) end)

      assert output =~ "search returned 1 place"
      assert output =~ "## Query 1/2 — total count"
      assert output =~ "## Query 2/2 — page"
      assert output =~ "geodata_places"
      assert output =~ "Execution Time"
    end

    test "--no-count explains only the page query" do
      output =
        capture_io(fn -> Mix.Tasks.Geodata.Explain.run(["lisbon", "--no-count"]) end)

      assert output =~ "## Query 1/1 — page"
      refute output =~ "total count"
    end

    test "warns about a sequential scan on an unindexed-sized table" do
      output =
        capture_io(fn -> Mix.Tasks.Geodata.Explain.run(["lisbon", "--no-count"]) end)

      assert output =~ "WARNING: sequential scan"
    end

    test "--help prints usage without touching the database" do
      output = capture_io(fn -> Mix.Tasks.Geodata.Explain.run(["--help"]) end)

      assert output =~ "mix geodata.explain lisbon"
    end
  end
end
