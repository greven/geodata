defmodule GeoData.Storage.ETSTest do
  use ExUnit.Case, async: false

  use GeoData.StorageTests, adapter: GeoData.Storage.ETS

  alias GeoData.Place
  alias GeoData.Storage.ETS

  describe "text index" do
    setup do
      ETS.reset()

      ETS.put_many([
        Place.new!(
          id: "GN:1",
          kind: :city,
          geonames_id: 1,
          name: "Lisboa",
          ascii_name: "Lisboa",
          names: ["Lisbon"]
        ),
        Place.new!(id: "GN:2", kind: :city, geonames_id: 2, name: "Porto", ascii_name: "Porto"),
        Place.new!(id: "ISO:PT", kind: :country, iso_3166_1: "PT", name: "Portugal")
      ])

      :ok
    end

    test "finds candidates by token prefix" do
      assert Enum.sort(ETS.candidates(["lis"], :prefix)) == ["GN:1"]
      assert Enum.sort(ETS.candidates(["por"], :prefix)) == ["GN:2", "ISO:PT"]
    end

    test "finds candidates by full token" do
      assert Enum.sort(ETS.candidates(["lisbon"], :token)) == ["GN:1"]
      assert ETS.candidates(["lisb"], :token) == []
    end

    test "intersects multiple tokens" do
      assert Enum.sort(ETS.candidates(["por"], :prefix)) == ["GN:2", "ISO:PT"]
      assert ETS.candidates(["por", "iso"], :prefix) == []
    end

    test "indexes ISO codes and geonames ids" do
      assert ETS.candidates(["pt"], :prefix) == ["ISO:PT"]
      assert ETS.candidates(["1"], :prefix) == ["GN:1"]
    end

    test "finds fuzzy candidates by shared trigrams" do
      assert "GN:1" in ETS.candidates(["lisbom"], :fuzzy)
      assert "GN:1" in ETS.candidates(["lisbno"], :fuzzy)
      assert ETS.candidates(["zzzzz"], :fuzzy) == []
    end

    test "intersects fuzzy candidates across tokens" do
      assert ETS.candidates(["lisbom", "porto"], :fuzzy) == []
    end

    test "delete/1 and reset/0 clear fuzzy index entries" do
      ETS.delete("GN:1")
      refute "GN:1" in ETS.candidates(["lisbom"], :fuzzy)

      ETS.reset()
      assert ETS.candidates(["lisbom"], :fuzzy) == []
    end

    test "updating a place replaces its index entries" do
      ETS.put_many([Place.new!(id: "GN:1", kind: :city, name: "Porto")])

      assert ETS.candidates(["lis"], :prefix) == []
      assert Enum.sort(ETS.candidates(["por"], :prefix)) == ["GN:1", "GN:2", "ISO:PT"]
    end

    test "delete/1 and reset/0 clear index entries" do
      ETS.delete("GN:1")
      assert ETS.candidates(["lis"], :prefix) == []

      ETS.reset()
      assert ETS.candidates(["por"], :prefix) == []
    end

    test "exposes precomputed search terms" do
      assert {:ok, place, terms} = ETS.get_with_terms("GN:1")
      assert place.name == "Lisboa"
      assert terms.name == "lisboa"
      assert terms.ascii_name == "lisboa"
      assert terms.names == ["lisbon"]

      entries = ETS.stream_with_terms() |> Enum.map(fn {p, _t} -> p.id end) |> Enum.sort()
      assert entries == ["GN:1", "GN:2", "ISO:PT"]
    end
  end

  describe "fuzzy recall" do
    @words ~w(lisbon portugal munchen london berlin paris)

    test "trigram candidates include every single-edit variant of a long token" do
      places =
        @words
        |> Enum.with_index()
        |> Enum.map(fn {word, index} ->
          Place.new!(
            id: "GN:#{index}",
            kind: :city,
            name: String.capitalize(word),
            ascii_name: word,
            geonames_id: index
          )
        end)

      ETS.reset()
      ETS.put_many(places)

      for {word, index} <- Enum.with_index(@words),
          variant <- variants(word),
          String.length(variant) >= 5 do
        assert "GN:#{index}" in ETS.candidates([variant], :fuzzy),
               "trigram candidates missed #{inspect(variant)} for #{word}"
      end
    end

    defp variants(word) do
      chars = String.graphemes(word)
      last = length(chars) - 1
      letters = Enum.map(?a..?z, &<<&1>>)

      substitutions =
        for i <- 0..last, letter <- letters, letter != Enum.at(chars, i) do
          chars |> List.replace_at(i, letter) |> Enum.join()
        end

      deletions = for i <- 0..last, do: chars |> List.delete_at(i) |> Enum.join()

      insertions =
        for i <- 0..length(chars), letter <- letters do
          chars |> List.insert_at(i, letter) |> Enum.join()
        end

      transpositions =
        for i <- 0..(last - 1) do
          chars
          |> List.replace_at(i, Enum.at(chars, i + 1))
          |> List.replace_at(i + 1, Enum.at(chars, i))
          |> Enum.join()
        end

      Enum.uniq(substitutions ++ deletions ++ insertions ++ transpositions)
    end
  end
end
