# AGENTS.md

Repository-level instructions for coding agents working on the GeoData library.

## Keep `usage-rules.md` in sync with the docs

`usage-rules.md` is the agent-facing distillation of the user documentation and is
shipped in the Hex package. Whenever public behavior, APIs, options, tasks or
documentation change, update `usage-rules.md` in the **same change** so it never
drifts. Review it whenever any of these change:

- `README.md` (also the `GeoData` moduledoc)
- Public function docs in `lib/geodata.ex` and other public modules
- Options in `lib/geodata/options.ex`
- Mix tasks under `lib/mix/tasks/`

If a change alters how a consumer should use the library, the corresponding rule
belongs in `usage-rules.md`, not just the README.

## Code conventions

- No `@spec` or `@type`; the project intentionally omits them (`@callback` only).
- Structured exceptions: expose `reason_atoms/0` for matching and keep prose in
  `message/1`.
- No runtime `config/config.exs` in this library; defaults come from
  `Application.compile_env(:geodata, key, default)`. The sole exception is the
  dev-only `:git_ops` tooling config in `config/config.exs`: it is not shipped
  and is not loaded by consumers.
- Payloads are structs (e.g. `Search.Result`, `Ingest.Report`, `Stats.Summary`).
- Do not add code comments unless explicitly asked.
- File paths mirror module names (`GeoData.Storage.Ecto.Postgres` ->
  `lib/geodata/storage/ecto/postgres.ex`).

## Commit messages and releases

Commit messages follow [Conventional Commits](https://conventionalcommits.org):
`<type>(<scope>): <description>`, e.g. `feat(search): add bbox filter`. The
version and `CHANGELOG.md` are managed by [`git_ops`](https://hex.pm/packages/git_ops).

- Types come from the `git_ops` defaults: `feat`, `fix`, `improvement`, `perf`,
  `refactor`, `style`, `docs`, `test`, `ci`, `chore`, `build`.
- Mark breaking changes with `!` after the type/scope (`feat(search)!: ...`).
- Preview a release with `mix git_ops.release --dry-run`; release with
  `mix git_ops.release`, then push with `git push --follow-tags`.
- Contributors can enforce the format locally with `mix git_ops.message_hook`,
  which installs a `commit-msg` hook.

## Verification

Run before considering a change done:

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix test`
- `mix credo` (pre-existing issues in `lib/geodata/fuzzy.ex` and
  `test/geodata/distance_test.exs` are known)
- `mix test.all` when touching the `integration/` consumer project
- PostgreSQL behavior (fuzzy `pg_trgm` pushdown, migrations): run the `integration/`
  suite with `mix test.integration --include postgres` against an ephemeral
  PostgreSQL.
