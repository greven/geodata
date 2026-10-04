defmodule GeoData.FetchTest.Source do
  @moduledoc false
  @behaviour GeoData.Source

  @impl true
  def source, do: :fake

  @impl true
  def files(_opts) do
    [
      %GeoData.Source.File{
        key: :a,
        filename: "a.json",
        url: "https://example.com/a.json",
        format: :json
      }
    ]
  end

  @impl true
  def parse(_paths, _opts), do: {:ok, []}

  @impl true
  def attribution do
    %{name: "fake", url: "https://example.com", license: "test", attribution: "test"}
  end
end

defmodule GeoData.FetchTest.ZipSource do
  @moduledoc false
  @behaviour GeoData.Source

  @impl true
  def source, do: :fake_zip

  @impl true
  def files(_opts) do
    [
      %GeoData.Source.File{
        key: :z,
        filename: "data.txt",
        url: "https://example.com/data.zip",
        format: :tsv,
        archive: :zip
      }
    ]
  end

  @impl true
  def parse(_paths, _opts), do: {:ok, []}

  @impl true
  def attribution do
    %{name: "fake_zip", url: "https://example.com", license: "test", attribution: "test"}
  end
end

defmodule GeoData.FetchTest do
  use ExUnit.Case, async: true

  alias GeoData.DownloadError
  alias GeoData.Fetch
  alias GeoData.FetchTest.Source
  alias GeoData.FetchTest.ZipSource

  setup do
    dir = Path.join(System.tmp_dir!(), "geodata-fetch-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  test "uses an explicitly provided file", %{dir: dir} do
    path = Path.join(dir, "custom.json")
    File.write!(path, "{}")

    opts = [source_path: dir, files: %{a: path}]

    assert {:ok, %{fake: %{a: %{path: ^path, status: :provided}}}} = Fetch.ensure([Source], opts)
  end

  test "errors when a provided file is missing", %{dir: dir} do
    opts = [source_path: dir, files: %{a: "/nope/a.json"}]

    assert {:error, %DownloadError{reason: :file_missing, path: "/nope/a.json"}} =
             Fetch.ensure([Source], opts)
  end

  test "reuses an existing cached file without downloading", %{dir: dir} do
    path = Path.join(dir, "a.json")
    File.write!(path, "{}")

    downloader = fn _, _, _ -> raise "should not download" end
    opts = [source_path: dir, downloader: downloader]

    assert {:ok, %{fake: %{a: %{path: ^path, status: :reused}}}} = Fetch.ensure([Source], opts)
  end

  test "downloads when the file is absent", %{dir: dir} do
    downloader = fn _file, path, _opts ->
      File.write!(path, "{}")
      {:ok, %{path: path, status: :downloaded}}
    end

    opts = [source_path: dir, downloader: downloader]

    assert {:ok, %{fake: %{a: %{status: :downloaded}}}} = Fetch.ensure([Source], opts)
  end

  test "forces a download even when the file exists", %{dir: dir} do
    path = Path.join(dir, "a.json")
    File.write!(path, "{}")

    downloader = fn _file, path, _opts ->
      send(self(), :downloaded)
      {:ok, %{path: path, status: :downloaded}}
    end

    opts = [source_path: dir, force: true, downloader: downloader]

    assert {:ok, %{fake: %{a: %{status: :downloaded}}}} = Fetch.ensure([Source], opts)
  end

  test "extracts a cached archive without downloading", %{dir: dir} do
    zip = Path.join(dir, "data.zip")
    assert {:ok, _} = :zip.create(String.to_charlist(zip), [{~c"data.txt", "hello"}])

    assert {:ok, %{fake_zip: %{z: %{path: path, status: :reused}}}} =
             Fetch.ensure([ZipSource], source_path: dir)

    assert path == Path.join(dir, "data.txt")
    assert File.read!(path) == "hello"
  end

  test "records checksums in a manifest and detects changes", %{dir: dir} do
    path = Path.join(dir, "a.json")
    File.write!(path, "{}")

    assert {:ok, %{fake: %{a: %{change: :new, checksum: checksum}}}} =
             Fetch.ensure([Source], source_path: dir)

    assert {:ok, %{fake: %{a: %{change: :unchanged, checksum: ^checksum}}}} =
             Fetch.ensure([Source], source_path: dir)

    File.write!(path, ~s({"x":1}))

    assert {:ok, %{fake: %{a: %{change: :changed}}}} = Fetch.ensure([Source], source_path: dir)

    lock = dir |> Path.join("sources.lock") |> File.read!() |> JSON.decode!()
    assert lock["version"] == 1
    assert is_binary(lock["files"]["fake/a"]["sha256"])
    assert is_binary(lock["files"]["fake/a"]["checked_at"])
  end

  test "summarizes change counts", %{dir: dir} do
    File.write!(Path.join(dir, "a.json"), "{}")

    {:ok, resolved} = Fetch.ensure([Source], source_path: dir)

    assert Fetch.change_counts(resolved) == %{new: 1}
    assert Fetch.format_changes(resolved) == "1 new, 0 changed, 0 unchanged"
  end
end
