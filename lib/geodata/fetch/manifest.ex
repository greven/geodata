defmodule GeoData.Fetch.Manifest do
  @moduledoc false

  alias GeoData.DownloadError

  @version 1

  def load(path) do
    case File.read(path) do
      {:ok, body} ->
        case JSON.decode(body) do
          {:ok, %{"files" => files}} -> %{version: @version, files: files}
          _ -> empty()
        end

      {:error, _reason} ->
        empty()
    end
  rescue
    _error -> empty()
  end

  def save(path, %{files: files}) do
    body = JSON.encode!(%{"version" => @version, "files" => files})

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, body) do
      :ok
    else
      {:error, reason} ->
        {:error, %DownloadError{path: path, reason: :write_failed, detail: reason}}
    end
  rescue
    error -> {:error, %DownloadError{path: path, reason: :write_failed, detail: error}}
  end

  def entry(%{files: files}, key), do: Map.get(files, key)

  def put(%{files: files} = manifest, key, entry) do
    %{manifest | files: Map.put(files, key, entry)}
  end

  def change(nil, _current), do: :new
  def change(previous, current) when previous == current, do: :unchanged
  def change(_previous, _current), do: :changed

  defp empty, do: %{version: @version, files: %{}}
end
