defmodule GeoData.SearchTests do
  @moduledoc false

  defmacro __using__(opts) do
    search = Keyword.fetch!(opts, :search)

    quote do
      @search_mod unquote(search)

      alias GeoData.Search.Result
      alias GeoData.ValidationError

      defp search(text \\ nil, opts \\ []) do
        GeoData.search(text, Keyword.put_new(opts, :search, @search_mod))
      end

      defp ids(%Result{places: places}), do: Enum.map(places, & &1.id)

      defp result!(opts) do
        {:ok, result} = search(nil, opts)
        result
      end

      unquote(text_matching_tests())
      unquote(code_and_id_matching_tests())
      unquote(filters_tests())
      unquote(ordering_and_paging_tests())
      unquote(engine_tests())
      unquote(argument_form_tests())
      unquote(validation_tests())
    end
  end

  defp text_matching_tests do
    quote do
      describe "text matching" do
        test "finds a place by name prefix" do
          assert {:ok, %Result{} = result} = search("lis")
          assert ids(result) == ["GN:2267057"]
        end

        test "is accent-insensitive" do
          assert {:ok, result} = search("sao")
          assert ids(result) == ["GN:3448439"]
        end

        test "falls back to ascii names" do
          assert {:ok, result} = search("munich")
          assert ids(result) == ["GN:2867714"]
        end

        test "matches localized alternate names" do
          assert {:ok, result} = search("monaco")
          assert ids(result) == ["GN:2867714"]

          assert {:ok, exact} = search("monaco di baviera", match: :exact)
          assert ids(exact) == ["GN:2867714"]
        end

        test "restricts matching to the selected fields" do
          assert {:ok, %Result{places: []}} = search("monaco", fields: [:name, :ascii_name])

          assert {:ok, result} = search("monaco", fields: [:names])
          assert ids(result) == ["GN:2867714"]
        end

        test "matches multiple words in any order" do
          assert {:ok, first} = search("new york")
          assert {:ok, second} = search("york new")
          assert ids(first) == ["GN:5128581"]
          assert ids(second) == ["GN:5128581"]
        end

        test "supports :exact mode" do
          assert {:ok, result} = search("sao paulo", match: :exact)
          assert ids(result) == ["GN:3448439"]

          assert {:ok, empty} = search("paulo", match: :exact)
          assert empty.places == []
        end

        test "supports :contains mode" do
          assert {:ok, result} = search("ork", match: :contains)
          assert "GN:5128581" in ids(result)
        end

        test "returns an empty result when nothing matches" do
          assert {:ok, result} = search("zzzzz")
          assert result.total == 0
          assert result.places == []
        end

        test "returns nothing for a non-empty query that normalizes to nothing" do
          assert {:ok, result} = search("!!!")
          assert result.total == 0
          assert result.places == []
        end
      end
    end
  end

  defp code_and_id_matching_tests do
    quote do
      describe "code and id matching" do
        test "resolves an ISO 3166-1 country code" do
          assert {:ok, result} = search("PT")
          assert ids(result) == ["ISO:PT"]
        end

        test "resolves an ISO 3166-2 subdivision code" do
          assert {:ok, result} = search("US-CA")
          assert ids(result) == ["ISO:US-CA"]
        end

        test "resolves a GeoNames id" do
          assert {:ok, result} = search("5128581")
          assert ids(result) == ["GN:5128581"]
        end

        test "ranks a code match first" do
          assert {:ok, result} = search("br")
          assert hd(result.places).id == "ISO:BR"
        end
      end
    end
  end

  defp filters_tests do
    quote do
      describe "filters" do
        test "by kind and country" do
          assert {:ok, result} = search(nil, where: [kind: :country])
          assert result.total == 2

          assert {:ok, result} = search(nil, where: [country: "PT"])
          assert ids(result) |> Enum.sort() == ["GN:2267057", "ISO:PT"]
        end

        test "by population range" do
          assert {:ok, result} = search(nil, where: [kind: :city, population: [min: 5_000_000]])
          assert ids(result) |> Enum.sort() == ["GN:3448439", "GN:5128581"]
        end

        test "by bounding box" do
          assert {:ok, result} = search(nil, where: [bbox: {35.0, -10.0, 45.0, 5.0}])
          assert ids(result) == ["GN:2267057"]
        end

        test "by subdivision, continent, feature class/code, timezone, id and geonames id" do
          assert ids(result!(where: [subdivision: ["US-CA"]])) == ["ISO:US-CA"]
          assert ids(result!(where: [continent: "EU"])) == ["ISO:PT"]
          assert ids(result!(where: [kind: :city, feature_class: "P"])) |> length() == 4

          assert result!(where: [feature_code: "PPL"]) |> ids() |> Enum.sort() ==
                   ["GN:2867714", "GN:3448439", "GN:5128581"]

          assert ids(result!(where: [timezone: "Europe/Lisbon"])) == ["GN:2267057"]
          assert ids(result!(where: [id: ["ISO:PT"]])) == ["ISO:PT"]
          assert ids(result!(where: [geonames_id: [5_128_581]])) == ["GN:5128581"]
        end

        test "by feature code group" do
          assert ids(result!(where: [feature_code: :capital])) == ["GN:2267057"]

          assert result!(where: [feature_code: :city]) |> ids() |> Enum.sort() ==
                   ["GN:2267057", "GN:2867714", "GN:3448439", "GN:5128581"]

          assert ids(result!(where: [feature_code: :section])) == []
        end

        test "by semantic feature code group such as :mountain" do
          assert ids(result!(where: [feature_code: :mountain])) == ["GN:1863967"]
          assert ids(result!(where: [feature_code: [:peak, :volcano]])) == []
        end

        test "by feature class alias such as :landforms" do
          assert ids(result!(where: [feature_class: :landforms])) == ["GN:1863967"]
          assert ids(result!(where: [feature_class: "T"])) == ["GN:1863967"]

          assert result!(where: [feature_class: :populated]) |> ids() |> Enum.sort() ==
                   ["GN:2267057", "GN:2867714", "GN:3448439", "GN:5128581"]
        end
      end
    end
  end

  defp ordering_and_paging_tests do
    quote do
      describe "ordering and paging" do
        test "orders by population descending" do
          assert {:ok, result} = search(nil, where: [kind: :city], order_by: {:population, :desc})
          assert ids(result) == ["GN:3448439", "GN:5128581", "GN:2867714", "GN:2267057"]
        end

        test "orders by name" do
          assert {:ok, result} = search(nil, where: [kind: :city], order_by: :name)

          assert Enum.map(result.places, & &1.name) == [
                   "Lisbon",
                   "München",
                   "New York City",
                   "São Paulo"
                 ]
        end

        test "orders places without a population last" do
          assert {:ok, result} = search(nil, order_by: {:population, :desc})
          assert List.last(result.places).id == "GN:1863967"
        end

        test "paginates and reports the total" do
          assert {:ok, result} =
                   search(nil, where: [kind: :city], order_by: :name, limit: 2, offset: 1)

          assert result.total == 4
          assert result.limit == 2
          assert result.offset == 1
          assert Enum.map(result.places, & &1.name) == ["München", "New York City"]
        end

        test "skips the total when count: false" do
          assert {:ok, result} = search(nil, where: [kind: :city], count: false)

          assert result.total == nil
          assert length(result.places) == 4
        end

        test "applies default paging" do
          assert {:ok, result} = search("")
          assert result.total == 8
          assert result.limit == 20
          assert result.offset == 0
        end

        test "supports limit: :infinity" do
          assert {:ok, result} = search(nil, where: [kind: :country], limit: :infinity)
          assert result.total == 2
          assert result.limit == :infinity
          assert length(result.places) == 2
        end
      end
    end
  end

  defp engine_tests do
    quote do
      describe "engines" do
        test "uses an overridden search engine for the call" do
          assert {:ok, %Result{places: [:stub]}} =
                   search("x", search: GeoData.SearchFixtures.Stub)
        end

        test "streams filtered places" do
          names =
            GeoData.stream(nil, where: [kind: :country], search: @search_mod)
            |> Enum.map(& &1.name)
            |> Enum.sort()

          assert names == ["Brazil", "Portugal"]
        end
      end
    end
  end

  defp argument_form_tests do
    quote do
      describe "argument forms" do
        test "accepts options without text" do
          assert {:ok, result} = GeoData.search(where: [kind: [:country]], search: @search_mod)
          assert result.total == 2
        end

        test "accepts filters and order_by as a bare keyword list" do
          assert {:ok, result} =
                   GeoData.search(
                     where: [kind: [:country], continent: "EU"],
                     order_by: :name,
                     search: @search_mod
                   )

          assert Enum.map(result.places, & &1.name) == ["Portugal"]
        end

        test "search!/1 accepts options without text" do
          result = GeoData.search!(where: [kind: [:country]], search: @search_mod)
          assert result.total == 2
        end

        test "stream/1 accepts options without text" do
          names =
            GeoData.stream(where: [kind: [:country]], search: @search_mod)
            |> Enum.map(& &1.name)
            |> Enum.sort()

          assert names == ["Brazil", "Portugal"]
        end
      end
    end
  end

  defp validation_tests do
    quote do
      describe "validation" do
        test "returns validation errors for invalid options" do
          assert {:error, %ValidationError{reason: :invalid_option}} = search("x", match: :bogus)
          assert {:error, %ValidationError{reason: :invalid_option}} = search("x", limit: 0)

          assert {:error, %ValidationError{reason: :invalid_option}} =
                   search("x", where: [bogus: 1])

          assert {:error, %ValidationError{reason: :invalid_kind}} =
                   search("x", where: [kind: :county])
        end

        test "search!/2 returns the result or raises" do
          assert %Result{} = GeoData.search!("lis", search: @search_mod)
          assert_raise ValidationError, fn -> GeoData.search!("x", match: :bogus) end
        end
      end
    end
  end
end
