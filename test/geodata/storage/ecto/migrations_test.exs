defmodule GeoData.Storage.Ecto.MigrationsTest do
  use ExUnit.Case, async: false
  use GeoData.EctoSetup

  alias GeoData.Storage.Ecto.Migrations
  alias GeoData.Storage.Ecto.TestRepo, as: Repo
  alias GeoData.Storage.Ecto.TestRepo.Migrations.CreateGeoDataPlaces, as: Migration

  test "current_version/0 returns the latest schema version" do
    assert Migrations.current_version() == 1
  end

  test "the migration is idempotent" do
    assert :ok = Ecto.Migrator.up(Repo, 20_240_102_000_000, Migration, log: false)
  end
end
