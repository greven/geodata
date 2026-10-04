defmodule GeoData.Source.File do
  @moduledoc """
  A file belonging to a `GeoData.Source`.

  ## Fields

    * `:key` - logical key used to reference the file, e.g. `:iso_3166_1`
    * `:filename` - local filename of the data file under the configured
      `:source_path` (the extracted file for archived sources)
    * `:url` - remote location to download from
    * `:format` - data format, one of `:json`, `:tsv` or `:zip`
    * `:archive` - archive format when `:url` points at an archive to extract,
      e.g. `:zip`
    * `:checksum` - optional lowercase hex SHA-256 of the downloaded file

  """

  defstruct [:key, :filename, :url, :format, :archive, :checksum]
end
