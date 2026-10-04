defmodule GeoData.Source do
  @moduledoc """
  Behaviour for an ingestion source.

  A source declares the remote files it needs and knows how to turn the
  locally cached copies into `GeoData.Place` records. Fetching and caching are
  handled by `GeoData.Fetch`; orchestration by `GeoData.Ingest`.

  A source implementer provides:

    * `source/0` - the source name, e.g. `:iso_codes`
    * `files/1` - the files to fetch, as `GeoData.Source.File` structs
    * `parse/2` - builds places from a map of `%{file_key => local_path}`

  """

  alias GeoData.Source.File, as: SourceFile

  @tiers %{
    base: [:iso_codes],
    cities: [:iso_codes, :geonames],
    all: [:iso_codes, :geonames]
  }

  @registry %{
    iso_codes: GeoData.Source.IsoCodes,
    geonames: GeoData.Source.Geonames
  }

  @doc """
  Returns the source names that have a registered adapter.
  """
  def available, do: Map.keys(@registry)

  @doc """
  Resolves the configured sources for the dataset tier.

  Returns `{:ok, source_modules}` or `{:error, %GeoData.IngestError{}}` when a
  requested source has no registered adapter.
  """
  def resolve(opts) do
    keys =
      @tiers
      |> Map.fetch!(opts[:dataset])
      |> Enum.filter(&(&1 in opts[:sources]))

    case Enum.reject(keys, &Map.has_key?(@registry, &1)) do
      [] -> {:ok, Enum.map(keys, &Map.fetch!(@registry, &1))}
      [key | _] -> {:error, %GeoData.IngestError{source: key, reason: :source_not_available}}
    end
  end

  @doc """
  Returns the source name.
  """
  @callback source() :: atom()

  @doc """
  Returns the files the source needs, as `GeoData.Source.File` structs.
  """
  @callback files(keyword()) :: [SourceFile.t()]

  @doc """
  Parses the locally cached files into `GeoData.Place` records.

  Receives a map of `%{file_key => local_path}` and returns `{:ok, places}` or
  `{:error, exception}`.
  """
  @callback parse(%{atom() => String.t()}, keyword()) ::
              {:ok, Enumerable.t()} | {:error, Exception.t()}

  @doc """
  Returns the source's attribution metadata.

  The map has `:name`, `:url`, `:license` and `:attribution` keys describing
  the source and the notice redistributors must carry. It is written to the
  dataset's attribution manifest by `GeoData.Attribution`.
  """
  @callback attribution() :: map()
end
