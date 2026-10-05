if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Geodata.Install do
    use Igniter.Mix.Task

    @shortdoc "Installs GeoData with Ecto storage into an application"
    @moduledoc """
    Configures a host application to use GeoData with `GeoData.Storage.Ecto`.

    The default in-memory `GeoData.Storage.ETS` adapter needs no setup, so this
    installer only covers the database-backed path. It:

      * adds `ecto_sql` (and a database driver, when `--driver` is given)
      * sets `config :geodata, storage: GeoData.Storage.Ecto` and
        `config :geodata, search: GeoData.Search.Ecto`
      * points `config :geodata, GeoData.Storage.Ecto, repo:` at your repo
      * generates a migration that calls
        `GeoData.Storage.Ecto.Migrations.up/0`

    It never downloads or ingests data; run `mix geodata.download` and
    `mix geodata.ingest` yourself afterwards.

    ## Options

      * `--repo` - the Ecto repo module to use, e.g. `--repo MyApp.Repo`. When
        omitted, the repo is detected from the project.
      * `--driver` - one of `postgres`, `mysql`, `sqlite`. Adds the matching
        driver dependency when it is not already present.
      * `--migrate` / `--no-migrate` - generate the GeoData migration (default
        `--migrate`).

    ## Example

        mix geodata.install --repo MyApp.Repo --driver postgres
    """

    @drivers %{
      "postgres" => {:postgrex, "~> 0.19 or ~> 1.0"},
      "sqlite" => {:ecto_sqlite3, "~> 0.25"},
      "mysql" => {:myxql, "~> 0.7"}
    }

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :geodata,
        positional: [],
        composes: [],
        schema: [
          repo: :string,
          driver: :string,
          migrate: :boolean
        ],
        defaults: [migrate: true],
        aliases: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options

      case resolve_repo(igniter, options[:repo]) do
        {igniter, nil} ->
          igniter

        {igniter, repo} ->
          igniter
          |> validate_driver(options[:driver])
          |> Igniter.Project.Deps.add_dep({:ecto_sql, "~> 3.14"}, on_exists: :skip)
          |> maybe_add_driver(options[:driver])
          |> configure(repo)
          |> maybe_generate_migration(repo, options[:migrate])
          |> add_next_steps(repo)
      end
    end

    defp resolve_repo(igniter, nil) do
      case Igniter.Libs.Ecto.select_repo(igniter) do
        {igniter, nil} ->
          Igniter.add_issue(igniter, """
          Could not find an Ecto repo in this project.

          Add one, or re-run with `--repo MyApp.Repo`.
          """)

        {igniter, repo} ->
          {igniter, repo}
      end
    end

    defp resolve_repo(igniter, repo), do: {igniter, Igniter.Project.Module.parse(repo)}

    defp validate_driver(igniter, nil), do: igniter

    defp validate_driver(igniter, driver) do
      if Map.has_key?(@drivers, driver) do
        igniter
      else
        Igniter.add_issue(igniter, """
        Unknown driver #{inspect(driver)}. Expected one of: #{Enum.join(Map.keys(@drivers), ", ")}.
        """)
      end
    end

    defp maybe_add_driver(igniter, nil) do
      if Enum.any?(Map.values(@drivers), fn {dep, _} ->
           Igniter.Project.Deps.has_dep?(igniter, dep)
         end) do
        igniter
      else
        Igniter.add_warning(igniter, """
        No Ecto database driver was found. Add one (for example `{:postgrex, "~> 0.19"}`), \
        or re-run with `--driver postgres|mysql|sqlite`.
        """)
      end
    end

    defp maybe_add_driver(igniter, driver) do
      case Map.fetch(@drivers, driver) do
        {:ok, dep} -> Igniter.Project.Deps.add_dep(igniter, dep, on_exists: :skip)
        :error -> igniter
      end
    end

    defp configure(igniter, repo) do
      igniter
      |> Igniter.Project.Config.configure(
        "config.exs",
        :geodata,
        [:storage],
        GeoData.Storage.Ecto
      )
      |> Igniter.Project.Config.configure("config.exs", :geodata, [:search], GeoData.Search.Ecto)
      |> Igniter.Project.Config.configure(
        "config.exs",
        :geodata,
        [GeoData.Storage.Ecto, :repo],
        repo
      )
    end

    defp maybe_generate_migration(igniter, _repo, false), do: igniter

    defp maybe_generate_migration(igniter, repo, true) do
      Igniter.Libs.Ecto.gen_migration(igniter, repo, "AddGeoData",
        body: """
        def up, do: GeoData.Storage.Ecto.Migrations.up()

        def down, do: GeoData.Storage.Ecto.Migrations.down()
        """,
        on_exists: :skip
      )
    end

    defp add_next_steps(igniter, repo) do
      Igniter.add_notice(igniter, """
      GeoData is configured to use Ecto storage with #{inspect(repo)}.

      Next steps:
        1. Run `mix ecto.migrate` to create the `geodata_places` table.
        2. Download and ingest data:
             mix geodata.download && mix geodata.ingest --dataset base

      `config :geodata, :storage` is read at compile time, so recompile after \
      changing it.
      """)
    end
  end
else
  defmodule Mix.Tasks.Geodata.Install do
    use Mix.Task

    @shortdoc "Installs GeoData with Ecto storage into an application"
    @moduledoc false

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task "geodata.install" requires igniter. Please install igniter and try again.

      For more information, see: https://igniter.hexdocs.pm/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
