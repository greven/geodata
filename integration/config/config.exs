import Config

# GeoData is compiled as a dependency of this project, so the options set here
# become its defaults for this application (see `GeoData.Options`). This mirrors
# how a host application configures the library.
config :geodata, storage: GeoData.Storage.Ecto
config :geodata, GeoData.Storage.Ecto, repo: GeodataIntegration.Repo

# The repo belongs to this application. Tests override `:database` with a
# unique temporary file so runs stay isolated.
config :geodata_integration, GeodataIntegration.Repo,
  database: Path.join(System.tmp_dir!(), "geodata_integration.db"),
  pool_size: 1,
  log: false

# PostgreSQL repo, used only by the tests tagged `:postgres` (pg_trgm fuzzy
# search, later PostGIS). Point it at your local server with PG* env vars.
config :geodata_integration, GeodataIntegration.PostgresRepo,
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD"),
  database: System.get_env("PGDATABASE", "geodata_integration_test"),
  pool_size: 2,
  log: false
