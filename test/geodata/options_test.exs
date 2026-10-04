defmodule GeoData.OptionsTest do
  use ExUnit.Case, async: true

  alias GeoData.Options

  describe "config_options/1" do
    test "schema returns the unvalidated NimbleOptions struct" do
      assert %NimbleOptions{} = Options.config_schema()
    end

    test "returns the correct default options" do
      expected =
        [
          storage: GeoData.Storage.ETS,
          storage_path: "priv/geodata",
          source_path: "priv/geodata/sources",
          files: %{},
          force: false,
          reset: false,
          dataset: :base,
          memory_mode: :eager,
          search: GeoData.Search.Memory,
          sources: [:iso_codes, :geonames],
          postal_countries: [],
          boundaries: [],
          boundary_detail: :low
        ]
        |> Enum.sort()

      actual = Options.config_options() |> Enum.sort()
      assert expected == actual
    end

    test "merges custom options" do
      opts =
        Options.config_options(
          dataset: :cities,
          memory_mode: :lazy,
          sources: [:iso_codes]
        )

      assert opts[:dataset] == :cities
      assert opts[:memory_mode] == :lazy
      assert opts[:sources] == [:iso_codes]
    end

    test "validates option values" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Options.config_options(dataset: :bogus)
      end

      assert_raise NimbleOptions.ValidationError, fn ->
        Options.config_options(memory_mode: :bogus)
      end

      assert_raise NimbleOptions.ValidationError, fn ->
        Options.config_options(sources: [:bogus])
      end

      assert_raise NimbleOptions.ValidationError, fn ->
        Options.config_options(postal_countries: "PT")
      end
    end
  end

  describe "validate/1" do
    test "returns {:ok, options} for valid input" do
      assert {:ok, opts} = Options.validate(dataset: :cities)
      assert opts[:dataset] == :cities
    end

    test "returns a validation error instead of raising" do
      assert {:error, %GeoData.ValidationError{reason: :invalid_option}} =
               Options.validate(dataset: :bogus)
    end
  end
end
