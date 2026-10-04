# GeoData integration tests

This is a small, standalone Mix project that consumes GeoData **as an external
dependency** (`{:geodata, path: ".."}`). It exists to test the things a normal
unit test cannot:

- the library compiled and configured inside a host application
- the optional Ecto storage adapter and the bundled migration
- the `mix geodata.*` tasks running for real
- the download/ingest pipeline against upstream (opt-in, needs network)

It is a separate project, so the root `mix test` never runs it and its
dependencies and build are kept apart under `integration/`.

## Running

From the repository root, set it up once (fetches the nested project's deps):

```shell
mix integration.setup
```

Then run the offline suite, the network tests, or the PostgreSQL tests:

```shell
mix test.integration
mix test.integration --include integration
mix test.integration --include postgres
```

`mix test.all` runs the unit suite followed by the integrations suite. The
aliases simply shell into this directory, so you can also work here directly:

```shell
cd integration
mix test --include integration
```

### PostgreSQL tests

Tests tagged `:postgres` need a reachable PostgreSQL server; they create the
`geodata_integration_test` database and run the bundled migration, which
installs the `pg_trgm` extension and its GIN indexes. Point them at a server
with the usual `PG*` variables (defaults: `localhost:5432`, user `postgres`,
database `geodata_integration_test`):

```shell
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=geodata_integration_test \
  mix test.integration --include postgres
```

The connecting role needs permission to `CREATE DATABASE` (for the first run)
and to `CREATE EXTENSION pg_trgm`.

## How files are organized

| Path | Purpose |
| --- | --- |
| `config/config.exs` | Configures GeoData (`storage:`, repo) like a host app |
| `test/support/ecto_case.ex` | Starts a fresh SQLite repo and runs the migration per test |
| `test/support/postgres_case.ex` | Starts a PostgreSQL repo, creates the DB and runs the migration (pg_trgm) |
| `test/support/fixtures.ex` | Reuses the library's fixtures via the dependency path |
| `test/support/repo.ex` | Real SQLite and PostgreSQL repos plus the migration from `GeoData.Storage.Ecto` |
| `test/storage_ecto_test.exs` | Public API against a real Ecto-backed store |
| `test/pg_trgm_test.exs` | `pg_trgm` fuzzy pushdown against PostgreSQL, tagged `:postgres` |
| `test/ingest_task_test.exs` | `mix geodata.ingest` with local files (offline) |
| `test/download_test.exs` | Full upstream download pipeline, tagged `:integration` |

## Tagging

Tests that need the network or another external service carry `@moduletag
:integration`; tests that need PostgreSQL carry `@moduletag :postgres`.
`test/test_helper.exs` excludes both tags by default, so they only run when you
opt in with `--include`. The same convention applies to the root suite.
