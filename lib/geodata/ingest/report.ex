defmodule GeoData.Ingest.Report do
  @moduledoc """
  Summary of a completed ingestion run.

  ## Fields

    * `:sources` - the source names that were ingested
    * `:files` - resolved files as `%{source => %{file_key => %{path:, status:}}}`
    * `:attribution` - path to the written attribution manifest
    * `:total` - number of unique places written
    * `:by_kind` - place counts by `:kind`
    * `:by_source` - place counts by contributing source

  """

  defstruct sources: [], files: %{}, attribution: nil, total: 0, by_kind: %{}, by_source: %{}

  @doc false
  def new(sources, files, stats, attribution) do
    %__MODULE__{
      sources: Enum.map(sources, & &1.source()),
      files: files,
      attribution: attribution,
      total: stats.total,
      by_kind: stats.by_kind,
      by_source: stats.by_source
    }
  end
end
