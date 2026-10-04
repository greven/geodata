defmodule GeodataIntegration.IngestTaskTest do
  @moduledoc """
  Runs `mix geodata.ingest` the way a host application would, pointing at local
  files so the run stays offline, and checks both the resulting dataset and the
  attribution manifest it writes.
  """

  use GeodataIntegration.EctoCase, async: false

  alias GeodataIntegration.Fixtures

  test "mix geodata.ingest loads storage and writes the attribution manifest", %{
    storage_path: storage_path,
    source_path: source_path
  } do
    argv =
      [
        "--dataset",
        "base",
        "--sources",
        "iso_codes",
        "--source-path",
        source_path,
        "--storage-path",
        storage_path,
        "--reset"
      ] ++ file_args(Fixtures.iso_codes())

    assert :ok = Mix.Tasks.Geodata.Ingest.run(argv)

    assert GeoData.count() == 6
    assert {:ok, %GeoData.Place{iso_3166_1: "PT"}} = GeoData.country("PT")

    # `sources.lock` records the files that fed the run.
    assert File.exists?(Path.join(source_path, "sources.lock"))

    manifest =
      storage_path
      |> Path.join("attribution.json")
      |> File.read!()
      |> JSON.decode!()

    assert manifest["dataset"] == "base"

    assert [source] = manifest["sources"]
    assert source["name"] == "iso-codes"
    assert source["license"] == "LGPL-2.1-or-later"
  end

  defp file_args(files) do
    Enum.flat_map(files, fn {key, path} -> ["--file", "#{key}=#{path}"] end)
  end
end
