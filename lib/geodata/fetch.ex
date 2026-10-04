defmodule GeoData.Fetch do
  @moduledoc """
  Makes source files available locally, reusing cached copies when possible.

  For every file declared by a `GeoData.Source`:

    1. an explicit override from the `:files` option is used as-is, bypassing
       the network entirely;
    2. otherwise an existing file at `:source_path/filename` is reused;
    3. otherwise the file is downloaded to a temporary path, verified and
       atomically renamed into place.

  Files with an `:archive` format (e.g. GeoNames `.zip` downloads) are cached
  as the archive and extracted to `:source_path/filename`; the extracted file
  is what gets reused on later runs.

  Every resolved file is hashed and recorded in a `sources.lock` manifest under
  `:source_path`, so each file is reported as `:new`, `:unchanged` or
  `:changed` relative to the previous run. This is advisory: it never blocks a
  download, but it makes upstream drift and corruption visible.

  Set `:force` to re-download even when a cached copy is present. The
  `:downloader` option overrides the default HTTP downloader and is intended
  for tests.

  Returns `{:ok, %{source_name => %{file_key => info}}}` where `info` has
  `:path`, `:status` (`:provided`, `:reused` or `:downloaded`), `:checksum`
  and `:change` (`:new`, `:unchanged` or `:changed`).
  """

  alias GeoData.DownloadError
  alias GeoData.Fetch.Manifest
  alias GeoData.Source.File, as: SourceFile

  @user_agent "geodata"
  @manifest "sources.lock"

  @doc """
  Ensures every file of every `source` is available locally.
  """
  def ensure(sources, opts \\ []) do
    source_path = Keyword.fetch!(opts, :source_path)
    overrides = Keyword.get(opts, :files, %{})
    force = Keyword.get(opts, :force, false)
    downloader = Keyword.get(opts, :downloader, &download/3)

    manifest_path = Path.join(source_path, @manifest)
    manifest = Manifest.load(manifest_path)

    case collect(sources, source_path, overrides, force, downloader, opts, manifest) do
      {:ok, results, manifest} ->
        with :ok <- Manifest.save(manifest_path, manifest), do: {:ok, results}

      {:error, error, _manifest} ->
        {:error, error}
    end
  end

  @doc """
  Returns how many resolved files are `:new`, `:changed` or `:unchanged`.
  """
  def change_counts(resolved) do
    resolved
    |> Enum.flat_map(fn {_source, files} ->
      Enum.map(files, fn {_key, info} -> info.change end)
    end)
    |> Enum.frequencies()
  end

  @doc """
  Formats `change_counts/1` as a human-readable string.
  """
  def format_changes(resolved) do
    counts = change_counts(resolved)

    Enum.map_join([:new, :changed, :unchanged], ", ", fn key ->
      "#{Map.get(counts, key, 0)} #{key}"
    end)
  end

  defp collect(sources, source_path, overrides, force, downloader, opts, manifest) do
    Enum.reduce_while(sources, {:ok, %{}, manifest}, fn source, {:ok, acc, manifest} ->
      case ensure_source(source, source_path, overrides, force, downloader, opts, manifest) do
        {:ok, files, manifest} ->
          {:cont, {:ok, Map.put(acc, source.source(), files), manifest}}

        {:error, error, manifest} ->
          {:halt, {:error, error, manifest}}
      end
    end)
  end

  defp ensure_source(source, source_path, overrides, force, downloader, opts, manifest) do
    source.files(opts)
    |> Enum.reduce_while({:ok, %{}, manifest}, fn file, {:ok, acc, manifest} ->
      case ensure_file(
             file,
             source.source(),
             source_path,
             overrides,
             force,
             downloader,
             opts,
             manifest
           ) do
        {:ok, info, manifest} ->
          {:cont, {:ok, Map.put(acc, file.key, info), manifest}}

        {:error, error, manifest} ->
          {:halt, {:error, error, manifest}}
      end
    end)
  end

  defp ensure_file(file, source, source_path, overrides, force, downloader, opts, manifest) do
    case resolve_file(file, source_path, overrides, force, downloader, opts) do
      {:ok, path, status} ->
        checksum = sha256(path)
        key = "#{source}/#{file.key}"
        change = Manifest.change(prior_checksum(manifest, key), checksum)

        entry = %{
          "url" => file.url,
          "sha256" => checksum,
          "bytes" => file_size(path),
          "checked_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        info = %{path: path, status: status, checksum: checksum, change: change}
        {:ok, info, Manifest.put(manifest, key, entry)}

      {:error, error} ->
        {:error, error, manifest}
    end
  end

  defp resolve_file(file, source_path, overrides, force, downloader, opts) do
    case Map.fetch(overrides, file.key) do
      {:ok, path} ->
        if File.exists?(path) do
          {:ok, path, :provided}
        else
          {:error, %DownloadError{url: file.url, path: path, reason: :file_missing}}
        end

      :error ->
        path = Path.join(source_path, file.filename)

        if File.exists?(path) and not force do
          {:ok, path, :reused}
        else
          case downloader.(file, path, opts) do
            {:ok, %{path: downloaded, status: status}} -> {:ok, downloaded, status}
            {:error, error} -> {:error, error}
          end
        end
    end
  end

  defp prior_checksum(manifest, key) do
    case Manifest.entry(manifest, key) do
      %{"sha256" => checksum} -> checksum
      _ -> nil
    end
  end

  defp download(%SourceFile{archive: nil} = file, path, _opts) do
    with :ok <- fetch_to(file, path) do
      {:ok, %{path: path, status: :downloaded}}
    end
  end

  defp download(%SourceFile{archive: _format} = file, path, opts) do
    archive = Path.join(Path.dirname(path), Path.basename(file.url))
    force = Keyword.get(opts, :force, false)

    with {:ok, status} <- ensure_archive(file, archive, force),
         :ok <- extract(file, archive, Path.dirname(path)),
         :ok <- check_extracted(path) do
      {:ok, %{path: path, status: status}}
    end
  end

  defp ensure_archive(file, archive, false) do
    if File.exists?(archive), do: {:ok, :reused}, else: fetch_archive(file, archive)
  end

  defp ensure_archive(file, archive, true), do: fetch_archive(file, archive)

  defp fetch_archive(file, archive) do
    with :ok <- fetch_to(file, archive) do
      {:ok, :downloaded}
    end
  end

  defp fetch_to(file, dest) do
    tmp = dest <> ".tmp"

    with :ok <- mkdir(dest),
         {:ok, response} <- get(file.url, tmp),
         :ok <- check_status(file, response, tmp),
         :ok <- verify(file, tmp) do
      rename(tmp, dest)
    end
  end

  defp extract(%SourceFile{archive: :zip}, archive, dir) do
    case :zip.extract(String.to_charlist(archive), cwd: String.to_charlist(dir)) do
      {:ok, _files} ->
        :ok

      {:error, reason} ->
        {:error, %DownloadError{path: archive, reason: :extract_failed, detail: reason}}
    end
  end

  defp check_extracted(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, %DownloadError{path: path, reason: :extract_failed}}
    end
  end

  defp mkdir(path) do
    case File.mkdir_p(Path.dirname(path)) do
      :ok -> :ok
      {:error, reason} -> write_error(path, reason)
    end
  end

  defp get(url, tmp) do
    options = [
      headers: [{"user-agent", @user_agent}],
      into: File.stream!(tmp),
      decode_body: false
    ]

    case Req.get(url, options) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, %DownloadError{url: url, path: tmp, reason: :http_error, detail: reason}}
    end
  end

  defp check_status(_file, %{status: status}, _tmp) when status in 200..299, do: :ok

  defp check_status(file, %{status: status}, tmp) do
    _ = File.rm(tmp)
    {:error, %DownloadError{url: file.url, path: tmp, status: status, reason: :http_error}}
  end

  defp verify(%SourceFile{checksum: nil}, _path), do: :ok

  defp verify(%SourceFile{checksum: expected}, path) do
    if String.downcase(expected) == sha256(path) do
      :ok
    else
      _ = File.rm(path)
      {:error, %DownloadError{path: path, reason: :checksum_mismatch}}
    end
  end

  defp rename(tmp, path) do
    case File.rename(tmp, path) do
      :ok ->
        :ok

      {:error, reason} ->
        _ = File.rm(tmp)
        write_error(path, reason)
    end
  end

  defp write_error(path, reason) do
    {:error, %DownloadError{path: path, reason: :write_failed, detail: reason}}
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end

  defp sha256(path) do
    path
    |> File.stream!(2048, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
