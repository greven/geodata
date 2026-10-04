if Code.ensure_loaded?(Postgrex) do
  defmodule GeodataIntegration.PostgresCase do
    @moduledoc false

    # Starts a PostgreSQL repo, creates the database and runs the bundled
    # migration (which installs `pg_trgm` and its GIN indexes), and points
    # GeoData at it for the duration of the test. Used by the `:postgres`
    # tagged integration tests.

    use ExUnit.CaseTemplate

    alias GeodataIntegration.PostgresRepo, as: Repo
    alias GeodataIntegration.PostgresRepo.Migrations.CreateGeoDataPlaces, as: Migration

    using do
      quote do
        alias GeodataIntegration.PostgresRepo, as: Repo
      end
    end

    setup do
      _ = Ecto.Adapters.Postgres.storage_up(Repo.config())

      start_supervised!(Repo)
      Ecto.Migrator.up(Repo, 20_240_103_000_000, Migration, log: false)

      previous = Application.get_env(:geodata, GeoData.Storage.Ecto)
      Application.put_env(:geodata, GeoData.Storage.Ecto, repo: Repo)

      GeoData.Storage.Ecto.Postgres.reset(Repo)
      GeoData.Storage.Ecto.reset()

      on_exit(fn ->
        if previous do
          Application.put_env(:geodata, GeoData.Storage.Ecto, previous)
        else
          Application.delete_env(:geodata, GeoData.Storage.Ecto)
        end
      end)

      :ok
    end
  end
end
