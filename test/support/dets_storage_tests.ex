defmodule GeoData.DETSStorageTests do
  @moduledoc false

  defmacro __using__(opts) do
    mode = Keyword.fetch!(opts, :memory_mode)

    quote do
      use ExUnit.Case, async: false

      alias GeoData.Storage.DETS

      setup do
        dir = Path.join(System.tmp_dir!(), "geodata-dets-#{System.unique_integer([:positive])}")
        File.mkdir_p!(dir)
        Application.put_env(:geodata, :storage_path, dir)
        Application.put_env(:geodata, :memory_mode, unquote(mode))

        start_supervised!(DETS)

        on_exit(fn ->
          Application.delete_env(:geodata, :storage_path)
          Application.delete_env(:geodata, :memory_mode)
          File.rm_rf(dir)
        end)
      end

      use GeoData.StorageTests, adapter: DETS

      test "exposes precomputed search terms" do
        place =
          GeoData.Place.new!(
            id: "GN:9",
            kind: :city,
            name: "São Paulo",
            ascii_name: "Sao Paulo",
            names: ["Sampa"]
          )

        assert :ok = DETS.put_many([place])
        assert {:ok, ^place, terms} = DETS.get_with_terms("GN:9")

        assert terms.name == "sao paulo"
        assert terms.ascii_name == "sao paulo"
        assert terms.names == ["sampa"]

        assert [{^place, ^terms}] = DETS.stream_with_terms() |> Enum.to_list()
      end

      if unquote(mode) == :eager do
        describe "text index" do
          setup do
            DETS.reset()

            DETS.put_many([
              GeoData.Place.new!(
                id: "GN:1",
                kind: :city,
                geonames_id: 1,
                name: "Lisboa",
                ascii_name: "Lisboa",
                names: ["Lisbon"]
              ),
              GeoData.Place.new!(
                id: "GN:2",
                kind: :city,
                geonames_id: 2,
                name: "Porto",
                ascii_name: "Porto"
              ),
              GeoData.Place.new!(id: "ISO:PT", kind: :country, iso_3166_1: "PT", name: "Portugal")
            ])

            :ok
          end

          test "finds candidates by token prefix" do
            assert Enum.sort(DETS.candidates(["lis"], :prefix)) == ["GN:1"]
            assert Enum.sort(DETS.candidates(["por"], :prefix)) == ["GN:2", "ISO:PT"]
          end

          test "finds candidates by full token" do
            assert Enum.sort(DETS.candidates(["lisbon"], :token)) == ["GN:1"]
            assert DETS.candidates(["lisb"], :token) == []
          end

          test "indexes ISO codes and geonames ids" do
            assert DETS.candidates(["pt"], :prefix) == ["ISO:PT"]
            assert DETS.candidates(["1"], :prefix) == ["GN:1"]
          end

          test "finds fuzzy candidates by shared trigrams" do
            assert "GN:1" in DETS.candidates(["lisbom"], :fuzzy)
            assert DETS.candidates(["zzzzz"], :fuzzy) == []
          end

          test "updating a place replaces its index entries" do
            DETS.put_many([GeoData.Place.new!(id: "GN:1", kind: :city, name: "Porto")])

            assert DETS.candidates(["lis"], :prefix) == []
            assert Enum.sort(DETS.candidates(["por"], :prefix)) == ["GN:1", "GN:2", "ISO:PT"]
          end

          test "delete/1 and reset/0 clear index entries" do
            DETS.delete("GN:1")
            assert DETS.candidates(["lis"], :prefix) == []

            DETS.reset()
            assert DETS.candidates(["por"], :prefix) == []
          end

          test "rebuilds the index from disk on startup" do
            :ok = stop_supervised(DETS)
            start_supervised!(DETS)

            assert DETS.candidates(["lis"], :prefix) == ["GN:1"]
            assert Enum.sort(DETS.candidates(["por"], :prefix)) == ["GN:2", "ISO:PT"]
          end
        end
      else
        test "candidates/2 is unavailable without an index" do
          assert DETS.candidates(["lis"], :prefix) == nil
        end
      end
    end
  end
end
