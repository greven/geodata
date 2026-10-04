defmodule GeoData.IngestError do
  @moduledoc """
  Raised or returned by `GeoData.Ingest` when a source cannot be read or
  parsed, or when a requested source is not available.

  ## Reasons

    * `:source_not_available` - the requested source has no registered adapter

    * `:missing_file` - a declared source file is not present locally

    * `:read_failed` - a source file could not be read

    * `:invalid_format` - a source file could not be decoded

    * `:parse_failed` - a source file was decoded but could not be parsed

    * `:attribution_failed` - the attribution manifest could not be written

  """

  @behaviour GeoData.Exception

  defexception [:source, :file, :detail, reason: :parse_failed]

  @impl true
  def reason_atoms,
    do: [
      :source_not_available,
      :missing_file,
      :read_failed,
      :invalid_format,
      :parse_failed,
      :attribution_failed
    ]

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{reason: :source_not_available, source: source}) do
    "source #{inspect(source)} is not available"
  end

  def message(%__MODULE__{reason: :parse_failed, source: source}) do
    "failed to parse source #{inspect(source)}"
  end

  def message(%__MODULE__{reason: :attribution_failed, file: file}) do
    "could not write attribution manifest#{format_file(file)}"
  end

  def message(%__MODULE__{reason: reason, source: source, file: file}) do
    "#{reason} for source #{inspect(source)}#{format_file(file)}"
  end

  defp format_file(nil), do: ""
  defp format_file(file), do: " (#{inspect(file)})"
end
