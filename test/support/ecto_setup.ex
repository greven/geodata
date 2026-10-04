defmodule GeoData.EctoSetup do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      alias GeoData.Storage.Ecto.TestRepo, as: Repo
      alias GeoData.Storage.Ecto.TestRepo.Migrations.CreateGeoDataPlaces, as: Migration

      setup do
        dir = Path.join(System.tmp_dir!(), "geodata-ecto-#{System.unique_integer([:positive])}")
        File.mkdir_p!(dir)

        Application.put_env(:geodata, Repo,
          database: Path.join(dir, "test.db"),
          pool_size: 1,
          log: false
        )

        Application.put_env(:geodata, GeoData.Storage.Ecto, repo: Repo)

        start_supervised!(Repo)
        Ecto.Migrator.up(Repo, 20_240_101_000_000, Migration, log: false)

        on_exit(fn ->
          Application.delete_env(:geodata, Repo)
          Application.delete_env(:geodata, GeoData.Storage.Ecto)
          File.rm_rf(dir)
        end)

        {:ok, storage_path: dir, source_path: Path.join(dir, "sources")}
      end
    end
  end
end
