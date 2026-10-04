defmodule GeoData.Options do
  @moduledoc """
  Options/configuration module for GeoData.
  """

  @datasets [:base, :cities, :all]
  @memory_modes [:eager, :lazy]
  @sources [:iso_codes, :geonames]

  @options [
    storage: [
      type: :atom,
      default: Application.compile_env(:geodata, :storage, GeoData.Storage.ETS),
      doc: "Storage adapter module"
    ],
    storage_path: [
      type: :string,
      default: Application.compile_env(:geodata, :storage_path, "priv/geodata"),
      doc: "Filesystem path used by persistent storage adapters"
    ],
    source_path: [
      type: :string,
      default: Application.compile_env(:geodata, :source_path, "priv/geodata/sources"),
      doc: "Directory where downloaded source files are cached and reused"
    ],
    files: [
      type: :map,
      default: Application.compile_env(:geodata, :files, %{}),
      doc: "Explicit source file overrides keyed by source file key, bypassing downloads"
    ],
    force: [
      type: :boolean,
      default: false,
      doc: "Re-download source files even when a cached copy is present"
    ],
    reset: [
      type: :boolean,
      default: false,
      doc: "Clear storage before ingesting"
    ],
    dataset: [
      type: {:in, @datasets},
      default: Application.compile_env(:geodata, :dataset, :base),
      doc: "Dataset tier: `:base`, `:cities` or `:all`"
    ],
    memory_mode: [
      type: {:in, @memory_modes},
      default: Application.compile_env(:geodata, :memory_mode, :eager),
      doc: "How much of the dataset is kept resident in memory"
    ],
    search: [
      type: :atom,
      default: Application.compile_env(:geodata, :search, GeoData.Search.Memory),
      doc: "Search engine module"
    ],
    sources: [
      type: {:list, {:in, @sources}},
      default: Application.compile_env(:geodata, :sources, @sources),
      doc: "Ingestion sources to use"
    ],
    postal_countries: [
      type: {:or, [{:in, [:all]}, {:list, {:or, [:string, :atom]}}]},
      default: Application.compile_env(:geodata, :postal_countries, []),
      doc: "Postal-code patterns to fetch and enable: a list of ISO 3166-1 codes or `:all`"
    ],
    boundaries: [
      type: {:or, [{:in, [:all]}, {:list, {:in, [:country, :subdivision]}}]},
      default: Application.compile_env(:geodata, :boundaries, []),
      doc: "Boundary levels to fetch and enable: a list of `:country`/`:subdivision` or `:all`"
    ],
    boundary_detail: [
      type: {:in, [:low, :high]},
      default: Application.compile_env(:geodata, :boundary_detail, :low),
      doc: "Natural Earth detail for boundaries: `:low` (1:50m) or `:high` (1:10m)"
    ]
  ]

  @config_schema NimbleOptions.new!(@options)

  def config_schema, do: @config_schema

  @doc """
  Validate and return the configuration options.

  Supported options:\n#{NimbleOptions.docs(@config_schema)}
  """
  def config_options(opts \\ []) do
    NimbleOptions.validate!(opts, @config_schema)
  end

  @doc """
  Same as `config_options/1` but returns `{:ok, options}` or
  `{:error, %GeoData.ValidationError{}}` instead of raising.
  """
  def validate(opts \\ []) do
    {:ok, NimbleOptions.validate!(opts, @config_schema)}
  rescue
    error in [NimbleOptions.ValidationError] -> {:error, to_validation_error(error)}
  end

  defp to_validation_error(%NimbleOptions.ValidationError{} = error) do
    %GeoData.ValidationError{
      field: error.key || :options,
      value: error.value,
      reason: :invalid_option,
      expected: error.message
    }
  end
end
