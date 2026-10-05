# GeoData usage rules

GeoData is a Geo data library for Elixir. Country/subdivision identity comes from
Debian iso-codes and place data from GeoNames, all normalized into a single
`%GeoData.Place{}`. Read `README.md` (rendered as the `GeoData` moduledoc) before
using the API; these rules only cover the parts agents most often get wrong.

## Data is not bundled

- GeoData ships **no data**. Nothing is queryable until sources are downloaded and
  ingested locally: `mix geodata.download` then `mix geodata.ingest --dataset base`.
- Datasets: `:base` (ISO countries + subdivisions only), `:cities` (+ GeoNames
  `cities1000`), `:all` (+ every GeoNames populated place and feature).
- GeoNames-enriched **filters** — `:continent`, `:population`, `:timezone` — match
  **nothing** on a `:base` store. Country fields such as `:capital`,
  `:neighbours` and `:languages` are only populated by enrichment and are read
  off the place; they are not search filters.
- Geographic features (`kind: :feature`, mountains/lakes/etc.) exist **only** in
  the `:all` dataset.
- `GeoData.Ingest.run/1` is the runtime equivalent of the download/ingest tasks.
- `mix geodata` lists the available `mix geodata.*` tasks.

## API shape

- Every read returns `{:ok, place_or_list}` or `{:error, exception}`; bang variants
  (`country!/1`, `place!/1`, `fetch!/1`, ...) raise. Codes are case-insensitive and
  accept strings or atoms.
- Main reads: `GeoData.country/1`, `subdivision/1`, `place/1` (by GeoNames id),
  `search/2`, `stream/2`, `features/1`, `countries/1`, `subdivisions/2`,
  `nearest/3`, `near/2`, `display_name/3`.
- `GeoData.put_many/1` is the write side used by ingestion; application code
  normally never writes places.
- Do not call internal modules such as `GeoData.Storage.Ecto.Postgres` or
  `GeoData.Source.*`. Public entry points are the `GeoData` functions plus
  `GeoData.Feature`, `GeoData.Distance`, `GeoData.Stats`, `GeoData.Postal`,
  `GeoData.Currency`, `GeoData.Language`.
- Exceptions are structured; use `reason_atoms/0` for matching and `message/1`
  for humans.

## Storage

- Defaults to `GeoData.Storage.ETS`, which suits `:base`/`:cities`. Use `DETS` to
  persist and `GeoData.Storage.Ecto` for the `:all` tier.
- ETS is **not persisted** — re-ingest after a restart. DETS `:eager` mirrors into
  RAM and builds the text index; DETS `:lazy` serves id/code lookups only and
  scans disk for text search.
- Ecto storage needs `ecto_sql` + a driver, `config :geodata, GeoData.Storage.Ecto,
repo: MyApp.Repo`, and the bundled migration
  `GeoData.Storage.Ecto.Migrations.up()`.
- `mix geodata.install --repo MyApp.Repo [--driver postgres|mysql|sqlite]` (or
  `mix igniter.install geodata`) automates the Ecto setup: adds `ecto_sql` and the
  driver, writes `storage: GeoData.Storage.Ecto` + `search: GeoData.Search.Ecto`
  and the repo config, and generates the migration. It never downloads or ingests
  data. Requires Igniter.

## Search

- Pick `:search` to match `:storage`: `GeoData.Search.Memory` (the default) with
  ETS/DETS, `GeoData.Search.Ecto` with `GeoData.Storage.Ecto`. The ETS/DETS
  adapters don't populate the SQL tables, so `Search.Ecto` requires `Storage.Ecto`.
- `GeoData.search/2` takes text and/or `where:` filters, `order_by:`, `limit:`
  (`:infinity` allowed); `GeoData.stream/2` is the lazy variant. Pass
  `count: false` to skip the total (`Search.Ecto` then skips an extra
  `count(*)`; `result.total` is `nil`).
- `match:` is one of `:exact | :prefix | :token | :contains | :fuzzy` (default
  `:prefix`); `match: :fuzzy` also takes `fuzziness` (max edits, default `1`, up
  to `2`).
- `GeoData.Search.Ecto` pushes text search, `:near` and `{:distance, point}` into
  SQL; its `match: :fuzzy` path requires PostgreSQL with `pg_trgm` (the bundled
  migration installs the extension and GIN indexes; other engines return a
  validation error).
- `mix geodata.explain TEXT [--match MODE] [--no-count] [filters]` prints
  `EXPLAIN (ANALYZE, BUFFERS)` for the SQL `Search.Ecto` generates, warning on
  sequential scans; use it to diagnose search performance on a real database.
- `:feature_code` accepts raw GeoNames codes **or** semantic groups, and
  `:feature_class` accepts raw class letters **or** aliases, both defined by
  `GeoData.Feature`. List them with `GeoData.feature_groups/0` and
  `GeoData.feature_classes/0`; never hardcode code lists.
- `features/1` / `stream_features/1` default `kind` to `[:feature, :locality]` and
  order by name.
- Matching is accent/case insensitive across primary, ASCII and alternate names.

## Postal codes

- Validation is opt-in. Set `config :geodata, postal_countries: ["PT", "GB"]` (or
  `:all`) and load patterns via `mix geodata.ingest`/`geodata.update`, or
  `mix geodata.postal --countries PT,GB` / `--all`.
- Distinguish the failure modes: `{:error, :not_loaded}` means the country's
  pattern was never fetched; `{:error, :invalid}` means the code failed the loaded
  pattern. `valid?/2` returns false for both.
- `normalize/1` is pure (upper-case, alphanumeric comparison key) and always
  available. `format/2` only has grouping rules for `PT`, `NL`, `CA`, `GB`, `JP`,
  `BR`, `PL`, `CZ`, `SK`, `SE`, `IE`, `MT`; elsewhere it returns the normalized
  code.

## Boundaries

- Containment is opt-in. Set `config :geodata, boundaries: [:country, :subdivision]`
  (or `:all`) and load polygons via `mix geodata.ingest`/`geodata.update`, or
  `mix geodata.boundaries --levels country,subdivision`. Until loaded,
  `GeoData.containing/3` returns `{:ok, []}`.
- `GeoData.containing(lat, lon, opts)` returns `{:ok, [%Place{}]}` ordered coarse
  to fine (country before subdivision); `opts` accepts `:kind`/`:kinds`. Ocean or
  unmatched points yield `{:ok, []}`.
- Geometry lives in `GeoData.Boundary` as a `%Geo.Polygon{}`/`%Geo.MultiPolygon{}`.
  Use `GeoData.boundary/1`, `GeoData.boundaries/1`, `GeoData.stream_boundaries/1`,
  `GeoData.within?/2`, and the predicates `contains?/2`/`intersects?/2`/`bbox/1`.
  Predicates take a `{latitude, longitude}` tuple; `bbox/1` returns
  `{min_lat, min_lon, max_lat, max_lon}`, matching the `where: [bbox: ...]` filter.
- `:boundary_detail` controls the **country** scale: `:low` (Natural Earth
  1:50m, the default) or `:high` (1:10m). Subdivisions always use 1:10m. The
  simplified 1:50m coastline can drop a coastal/estuarine point into the water
  (downtown Lisbon `38.72, -9.13` is in the carved-out Tagus estuary), so use
  `:high` for coastal accuracy. Coordinates are validated (latitude -90..90,
  longitude -180..180); a border point matches through `Topo.intersects?/2`.
  Boundaries do not draw maps.

## Localization

- Display names resolve at read time via Localize: `GeoData.display_name/3`
  (accepts a place or canonical id, defaults to `Localize.get_locale()`).
- Localize ships only `:en`. Configure `config :localize, otp_app: :my_app` and run
  `mix localize.download_locales <locale>` for others; unknown locales silently
  fall back to the canonical name.
- `place.names` holds GeoNames alternate names — search-only, untagged, not used
  for display.

## Verifying changes

- `mix test` for the unit suite; `mix test.all` also runs the `integration/`
  consumer project.
- Postgres-only behavior (fuzzy pushdown, migrations) is exercised in
  `integration/` with `mix test.integration --include postgres` against an
  ephemeral PostgreSQL.
