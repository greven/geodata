defmodule GeodataIntegration.EctoCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias GeodataIntegration.Repo
  alias GeodataIntegration.Repo.Migrations.CreateGeoDataPlaces, as: Migration

  using do
    quote do
      alias GeodataIntegration.Repo
    end
  end

  setup do
    dir =
      Path.join(System.tmp_dir!(), "geodata-integration-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    Application.put_env(:geodata_integration, Repo,
      database: Path.join(dir, "test.db"),
      pool_size: 1,
      log: false
    )

    start_supervised!(Repo)
    Ecto.Migrator.up(Repo, 20_240_101_000_000, Migration, log: false)

    on_exit(fn ->
      Application.delete_env(:geodata_integration, Repo)
      File.rm_rf(dir)
    end)

    {:ok, storage_path: dir, source_path: Path.join(dir, "sources")}
  end
end
