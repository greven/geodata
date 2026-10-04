if Code.ensure_loaded?(Postgrex) do
  defmodule GeodataIntegration.PgTrgmTest do
    use ExUnit.Case, async: false

    @moduletag :postgres

    use GeodataIntegration.PostgresCase

    alias GeoData.Place

    defp places do
      [
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
      ]
    end

    setup do
      GeoData.put_many(places())
      :ok
    end

    test "the migration installs pg_trgm and its GIN indexes" do
      %{rows: rows} =
        Repo.query!("SELECT indexname FROM pg_indexes WHERE tablename = 'geodata_places'")

      names = List.flatten(rows)

      assert "geodata_places_search_name_trgm" in names
      assert "geodata_places_search_ascii_trgm" in names
      assert "geodata_places_search_alternates_trgm" in names

      # Indexed so the exact code/GeoNames `OR` arms in every search query stay
      # indexable; without them the whole `OR` becomes a sequential scan.
      assert "geodata_places_iso_3166_2_index" in names
      assert "geodata_places_geonames_id_index" in names
    end

    test "search queries use indexes rather than a sequential scan" do
      # `enable_seqscan = off` only forces the planner to prefer indexes; it
      # cannot rescue an `OR` that has an unindexed arm, which still degrades to
      # a sequential scan. So this fails if the code/GeoNames indexes go away.
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL enable_seqscan = off")

        for sql <- [
              "SELECT id FROM geodata_places WHERE search_name LIKE 'lis%' " <>
                "OR search_ascii LIKE 'lis%' OR search_alternates LIKE 'lis%' " <>
                "OR (kind = 'country' AND iso_3166_1 = 'LIS') OR iso_3166_2 = 'LIS'",
              "SELECT id FROM geodata_places WHERE 'lisbom' <% search_name " <>
                "OR 'lisbom' <% search_ascii OR 'lisbom' <% search_alternates " <>
                "OR (kind = 'country' AND iso_3166_1 = 'LISBOM') OR iso_3166_2 = 'LISBOM'"
            ] do
          %{rows: rows} = Repo.query!("EXPLAIN #{sql}")
          plan = rows |> List.flatten() |> Enum.join("\n")

          assert plan =~ "BitmapOr", "expected a BitmapOr plan, got:\n#{plan}"
        end
      end)
    end

    test "the name and search columns are unbounded text" do
      %{rows: rows} =
        Repo.query!(
          "SELECT column_name, data_type FROM information_schema.columns " <>
            "WHERE table_name = 'geodata_places'"
        )

      types = Map.new(rows, fn [column, type] -> {column, type} end)

      for column <- ~w(name ascii_name search_name search_ascii search_alternates) do
        assert types[column] == "text", "expected #{column} to be text, got #{types[column]}"
      end
    end

    test "stores places with long names and alternates" do
      long_name = String.duplicate("n", 500)
      long_alternate = String.duplicate("a", 4_000)

      place =
        Place.new!(
          id: "GN:long",
          kind: :city,
          name: long_name,
          ascii_name: long_name,
          names: [long_alternate]
        )

      assert :ok = GeoData.put_many([place])

      assert {:ok, %Place{name: ^long_name} = stored} = GeoData.Storage.get("GN:long")
      assert long_alternate in stored.names
    end

    test "fuzzy search finds a typo" do
      assert {:ok, result} =
               GeoData.search("lisbom", match: :fuzzy, search: GeoData.Search.Ecto)

      assert Enum.map(result.places, & &1.id) == ["GN:2267057"]
      assert result.total == 1
    end

    test "fuzziness controls the similarity threshold" do
      assert {:ok, %{places: []}} =
               GeoData.search("lisbom", match: :fuzzy, fuzziness: 0, search: GeoData.Search.Ecto)

      assert {:ok, %{places: [place]}} =
               GeoData.search("lisbom", match: :fuzzy, fuzziness: 1, search: GeoData.Search.Ecto)

      assert place.id == "GN:2267057"
    end

    test "exact and prefix matching still work" do
      assert {:ok, result} = GeoData.search("lisbon", search: GeoData.Search.Ecto)
      assert Enum.map(result.places, & &1.id) == ["GN:2267057"]
    end
  end
end
