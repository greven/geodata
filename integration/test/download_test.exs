defmodule GeodataIntegration.DownloadTest do
  @moduledoc """
  Exercises the real download pipeline against the upstream iso-codes mirror.

  This needs network access, so it is tagged `:integration` and excluded by
  default. Opt in with:

      mix test --include integration

  """

  use GeodataIntegration.EctoCase, async: false

  @moduletag :integration

  test "downloads and ingests the base dataset from upstream", %{
    storage_path: storage_path,
    source_path: source_path
  } do
    assert :ok =
             Mix.Tasks.Geodata.Ingest.run([
               "--dataset",
               "base",
               "--source-path",
               source_path,
               "--storage-path",
               storage_path,
               "--reset"
             ])

    assert GeoData.count() > 4_000
    assert {:ok, %GeoData.Place{iso_3166_1: "PT"}} = GeoData.country("PT")
    assert File.exists?(Path.join(source_path, "sources.lock"))
  end
end
