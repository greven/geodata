defmodule GeoData.DownloadError do
  @moduledoc """
  Raised or returned by `GeoData.Fetch` when a source file cannot be made
  available locally.

  ## Reasons

    * `:file_missing` - an explicitly provided source file does not exist

    * `:http_error` - the download request failed

    * `:checksum_mismatch` - the downloaded file does not match the expected
      checksum

    * `:extract_failed` - an archive could not be extracted

    * `:write_failed` - the downloaded file could not be written to disk

  """

  @behaviour GeoData.Exception

  defexception [:url, :path, :status, :detail, reason: :http_error]

  @impl true
  def reason_atoms,
    do: [:file_missing, :http_error, :checksum_mismatch, :extract_failed, :write_failed]

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{reason: :file_missing, path: path}) do
    "source file #{inspect(path)} does not exist"
  end

  def message(%__MODULE__{reason: :checksum_mismatch, path: path}) do
    "checksum mismatch for #{inspect(path)}"
  end

  def message(%__MODULE__{reason: :extract_failed, path: path}) do
    "could not extract archive #{inspect(path)}"
  end

  def message(%__MODULE__{reason: :write_failed, path: path}) do
    "could not write source file #{inspect(path)}"
  end

  def message(%__MODULE__{reason: :http_error, url: url, status: nil}) do
    "failed to download #{url}"
  end

  def message(%__MODULE__{reason: :http_error, url: url, status: status}) do
    "failed to download #{url} (status #{status})"
  end
end
