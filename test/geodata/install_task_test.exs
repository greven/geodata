defmodule Mix.Tasks.Geodata.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  defp install(args \\ []) do
    test_project()
    |> Igniter.compose_task("geodata.install", ["--repo", "MyApp.Repo" | args])
  end

  test "adds ecto_sql and the chosen driver" do
    install(["--driver", "postgres"])
    |> assert_has_patch("mix.exs", ~S(+ |      {:ecto_sql, "~> 3.14"}))
    |> assert_has_patch("mix.exs", ~S(+ |      {:postgrex, "~> 0.19 or ~> 1.0"}))
  end

  test "configures Ecto storage, search and repo" do
    install()
    |> assert_creates("config/config.exs", fn content ->
      assert content =~ "config :geodata, storage: GeoData.Storage.Ecto"
      assert content =~ "search: GeoData.Search.Ecto"
      assert content =~ "config :geodata, GeoData.Storage.Ecto, repo: MyApp.Repo"
    end)
  end

  test "generates the GeoData migration" do
    igniter = install()

    assert_creates(igniter, migration_path(igniter), fn content ->
      assert content =~ "defmodule MyApp.Repo.Migrations.AddGeoData"
      assert content =~ "def up, do: GeoData.Storage.Ecto.Migrations.up()"
      assert content =~ "def down, do: GeoData.Storage.Ecto.Migrations.down()"
    end)
  end

  test "skips the migration with --no-migrate" do
    refute migration_path(install(["--no-migrate"]))
  end

  test "warns when no database driver is present" do
    install()
    |> assert_has_warning(&(&1 =~ "No Ecto database driver was found"))
  end

  test "rejects an unknown driver" do
    install(["--driver", "oracle"])
    |> assert_has_issue(&(&1 =~ "Unknown driver"))
  end

  test "is idempotent" do
    igniter =
      install()
      |> Igniter.compose_task("geodata.install", ["--repo", "MyApp.Repo"])
      |> Igniter.compose_task("geodata.install", ["--repo", "MyApp.Repo"])

    assert length(String.split(Igniter.Test.diff(igniter), "ecto_sql")) == 2

    migrations =
      igniter.rewrite.sources
      |> Map.keys()
      |> Enum.filter(&String.ends_with?(&1, "_add_geo_data.exs"))

    assert length(migrations) == 1
  end

  defp migration_path(igniter) do
    igniter.rewrite.sources
    |> Map.keys()
    |> Enum.find(&String.ends_with?(&1, "_add_geo_data.exs"))
  end
end
