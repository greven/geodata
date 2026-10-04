# GeoData

A Geo data library for Elixir. ISO 3166 country and subdivision identity is
sourced from the Debian [iso-codes](https://salsa.debian.org/iso-codes-team/iso-codes)
project and complemented with place data from [GeoNames](https://www.geonames.org/).
Locale-aware names and formatting are provided by
[Localize](https://hexdocs.pm/localize).

Everything is normalized into a single `GeoData.Place` structure with broad
search/query capabilities, pluggable storage and tiered memory management.

## Usage

GeoData ships no data: places are ingested once from the upstream sources
(see [Datasets](#datasets)) and then read by code. Application code normally
never writes places.

```elixir
{:ok, portugal} = GeoData.country("PT")
GeoData.display_name!(portugal, :en)          #=> "Portugal"

{:ok, california} = GeoData.subdivision("US-CA")
{:ok, lisbon} = GeoData.place(2_267_057)      # by GeoNames id
```

Codes are case-insensitive and accept strings or atoms, so `GeoData.country("pt")`
and `GeoData.country(:pt)` are equivalent. Text and filter queries live in
[Search](#search); the listing helpers in [Listing places](#listing-places):

```elixir
{:ok, result} = GeoData.search("lisbon", limit: 10)
result.places

GeoData.countries(where: [continent: "EU"])   # ordered by name
GeoData.all()                                 # lazy stream of every stored place
```

Every read returns `{:ok, place}` or `{:error, exception}`, and each has a
raising bang variant (`GeoData.country!/1`, `GeoData.fetch!/1`, ...). Locale
handling is covered in [Names and translations](#names-and-translations).

### Writing places

`GeoData.put_many/1` is the write side used by `mix geodata.ingest` and by
tests; most applications never call it. It is useful to seed a store with your
own data or to try things out in `iex -S mix`:

```elixir
iex> place = GeoData.Place.new!(id: "ISO:PT", kind: :country, iso_3166_1: "PT")
iex> :ok = GeoData.put_many([place])
iex> {:ok, place} = GeoData.country("PT")
iex> GeoData.Place.display_name!(place, :en)
"Portugal"
```

## Installation

```elixir
def deps do
  [
    {:geodata, "~> 0.1.0"}
  ]
end
```

## Datasets

| Tier      | Contents                                   |
| --------- | ------------------------------------------ |
| `:base`   | Countries and all ISO 3166-2 subdivisions  |
| `:cities` | `:base` plus GeoNames `cities1000`         |
| `:all`    | `:base` plus all GeoNames populated places |

`:base` carries ISO identity only. The GeoNames tiers (`:cities` and `:all`)
additionally enrich countries with `:continent`, `:population`, `:capital`,
`:neighbours` and other fields, and add populated places, so filters on those
fields match nothing on a `:base` store. GeoNames also lists codes ISO has
withdrawn (e.g. `AN`, `CS`); those are skipped, while user-assigned codes for
current countries such as `XK` (Kosovo) are kept.

Datasets are not bundled with the library. Run the download and ingestion
tasks to build local storage:

```shell
mix geodata.download
mix geodata.ingest --dataset base
```

Run `mix geodata` to list every GeoData task.

To refresh an existing dataset, `mix geodata.update` re-downloads the source
files (`--force`) and rebuilds storage (`--reset`) in one step:

```shell
mix geodata.update --dataset cities
```

The tasks are thin wrappers over the runtime API, so you can also download and
ingest from code with `GeoData.Ingest.run/1`:

```elixir
GeoData.Ingest.run(dataset: :cities, reset: true)
#=> {:ok, %GeoData.Ingest.Report{total: 176_367}}
```

It resolves the configured sources, downloads and caches any missing files (with
the same SHA-256 manifest) and writes the places to storage.

Downloads record the SHA-256 of each resolved file in a `sources.lock` manifest
under `--source-path`, and `download`/`update` report every file as `new`,
`changed` or `unchanged` relative to the previous run. This is advisory — it
never blocks a download, but it makes upstream drift, corruption and drift
between machines visible.

## Configuration

Options are defined and validated with
[NimbleOptions](https://hexdocs.pm/nimble_options) in `GeoData.Options`. All
settings have code-defined defaults; override only what you need in your
config:

```elixir
config :geodata,
  dataset: :cities,
  memory_mode: :lazy,
  storage: GeoData.Storage.ETS
```

Options can also be passed explicitly at runtime, where they are validated:

```elixir
GeoData.Options.config_options(dataset: :all)
```

| Key                 | Default                   |
| ------------------- | ------------------------- |
| `:storage`          | `GeoData.Storage.ETS`     |
| `:storage_path`     | `"priv/geodata"`          |
| `:source_path`      | `"priv/geodata/sources"`  |
| `:files`            | `%{}`                     |
| `:force`            | `false`                   |
| `:reset`            | `false`                   |
| `:dataset`          | `:base`                   |
| `:memory_mode`      | `:eager`                  |
| `:search`           | `GeoData.Search.Memory`   |
| `:sources`          | `[:iso_codes, :geonames]` |
| `:postal_countries` | `[]`                      |
| `:boundaries`       | `[]`                      |
| `:boundary_detail`  | `:low`                    |

## Choosing storage and search

Storage decides where places live and search decides how a query runs; pick them
together. The default `GeoData.Storage.ETS` + `GeoData.Search.Memory` is right
for small and medium datasets, while large or durable stores want `DETS` or
`Ecto`.

| Tier / use case      | Storage                           | Search                  | Why                                                                                      |
| -------------------- | --------------------------------- | ----------------------- | ---------------------------------------------------------------------------------------- |
| `:base`, tests       | `GeoData.Storage.ETS`             | `GeoData.Search.Memory` | ~5k places, fully in RAM, indexed, sub-millisecond.                                      |
| `:cities`, persists  | `GeoData.Storage.DETS` (`:eager`) | `GeoData.Search.Memory` | Persisted on disk plus a full RAM mirror, so reads stay fast.                            |
| `:cities`, tight RAM | `GeoData.Storage.DETS` (`:lazy`)  | `GeoData.Search.Memory` | No RAM mirror; keep for id/code lookups — text search scans the disk.                    |
| `:all` (millions)    | `GeoData.Storage.Ecto`            | `GeoData.Search.Ecto`   | SQL indexes carry the size; app RAM stays flat.                                          |
| Proximity / distance | `ETS`/`DETS` or `Ecto`            | `Memory` or `Ecto`      | `Memory` evaluates in memory; `Ecto` pushes `:near`/`:distance` as bbox + haversine SQL. |

- **ETS is not persisted** — re-ingest after a restart; use DETS or Ecto when the
  store must survive.
- **DETS `:lazy` has no token index** — it builds none, so text search walks every
  shard from disk; it fits id/code lookups, not search. `:eager` builds the same
  in-memory index as ETS, so text search stays fast alongside the RAM mirror.
- **Proximity works on both engines** — `Search.Memory` evaluates it in memory,
  and `Search.Ecto` pushes `:near`/`{:distance, _}` into SQL as a bounding-box
  prefilter plus a portable haversine expression (works on SQLite, PostgreSQL and
  MySQL; a PostGIS fast path may come later). `GeoData.Distance` works with any
  storage for per-row calculations.
- Pair `Search.Ecto` with `Storage.Ecto`; the ETS/DETS adapters don't populate the
  SQL tables.

## Search

`GeoData.search/2` finds places by text and/or structured filters and returns a
ranked page; `GeoData.stream/2` lazily streams matches.

```elixir
GeoData.search("lisbon", limit: 10)

GeoData.search("sao",
  where: [kind: [:city], country: ["BR", "PT"], population: [min: 100_000]],
  order_by: {:population, :desc}
)

GeoData.search(where: [kind: [:country], continent: "EU"], order_by: :name)
```

Matching is accent and case insensitive and defaults to per-token prefix
(`match: :exact | :prefix | :token | :contains | :fuzzy`). Names, ASCII names
and alternate names (the GeoNames `alternatenames` column, stored as the
`:names` list) are searched; ISO codes and GeoNames ids match exactly and rank
first.

`match: :fuzzy` tolerates typos using a bounded Damerau–Levenshtein distance,
with `fuzziness` (max edits per token, default `1`, up to `2`):

```elixir
GeoData.search("lisbom", match: :fuzzy)          #=> Lisbon
GeoData.search("lisbom", match: :fuzzy, fuzziness: 2)
```

Like the other modes it is index-backed: a trigram index supplies candidates when
every query token is long enough (5+ characters); short tokens and `fuzziness: 2`
fall back to a scan. Fuzzy matching is implemented by `GeoData.Search.Memory`;
`GeoData.Search.Ecto` pushes it to PostgreSQL via `pg_trgm` when the extension is
installed (the bundled migration installs it and adds GIN trigram indexes),
and returns a validation error otherwise.

Filters cover `:kind`, `:country`, `:subdivision`, `:continent`,
`:feature_class`, `:feature_code`, `:timezone`, `:id`, `:geonames_id`,
`:population`, `:bbox`, `:near` and `:has_coordinates`. `:bbox` takes
`{min_lat, min_lon, max_lat, max_lon}`, the same order as
`GeoData.Boundary.bbox/1` and `GeoData.Distance.bounding_box/3`; a box that
crosses the antimeridian uses `min_lon > max_lon`. `:feature_code` accepts
raw GeoNames codes or a semantic group, and `:feature_class` accepts raw class
letters or an alias, both defined by `GeoData.Feature`:

```elixir
GeoData.search(where: [feature_code: :mountain])          #=> MT, MTS
GeoData.search(where: [feature_code: [:lake, :waterfall]])
GeoData.search(where: [feature_class: :landforms])        #=> every "T" feature
```

`:feature_code` groups include the settlement names (`:capital`, `:admin_seat`,
`:city`, `:section`, `:locality`) plus landform, water, vegetation and manmade
names such as `:mountain`, `:peak`, `:volcano`, `:glacier`, `:lake`, `:river`,
`:waterfall`, `:island`, `:beach`, `:forest`, `:park`, `:airport`, `:bridge`
and more. `:feature_class` aliases are `:administrative` (`A`), `:hydrography`
(`H`), `:areas` (`L`), `:populated` (`P`), `:roads` (`R`), `:spots` (`S`),
`:landforms` (`T`), `:undersea` (`U`) and `:vegetation` (`V`). List them with
`GeoData.feature_groups/0` and `GeoData.feature_classes/0`.

Relevance weights a primary name above an ASCII name above alternate names, so the place
actually named after the query ranks first; restrict matching to primary names
with `fields: [:name, :ascii_name]` if you want to drop places that only match
through an alternate name. The default `GeoData.Search.Memory` engine is backed
by a token index built with `GeoData.Storage.Index`: `GeoData.Storage.ETS`
maintains it in ETS, and `GeoData.Storage.DETS` builds the same in-memory index
in `:eager` mode. Both adapters keep the normalized search terms alongside each
place, so text searches resolve from the index and match without re-normalizing
(sub-millisecond on the `:cities` tier).

Adapters without an index (DETS in `:lazy`, or `Ecto` through Memory)
fall back to a normalizing full scan. For large datasets,
`GeoData.Search.Ecto` pushes the query into SQL, using the indexed
`search_name`/`search_ascii`/`search_alternates` columns:

```elixir
config :geodata, search: GeoData.Search.Ecto
```

The SQL engine ranks `:relevance` the same way as the in-memory engine —
code/name match strength first, then population (places without one last), then
name — though it does not reproduce the exact in-memory score values. Ordering
breaks ties by `id` so paginated pages are stable.

To see how PostgreSQL actually runs a search — and catch a sequential scan or a
missing index before it hurts — run `mix geodata.explain` against the configured
repo; it prints `EXPLAIN (ANALYZE, BUFFERS)` for both the page and count queries:

```console
$ mix geodata.explain lisbon
$ mix geodata.explain "sao paulo" --match token --limit 10
$ mix geodata.explain lisbom --match fuzzy --fuzziness 2
```

`GeoData.search/2` also accepts `limit: :infinity` to return every match
instead of one page. By default the result carries an exact `:total`; pass
`count: false` to skip it (the Ecto engine then skips an extra `count(*)`
query) — `total` is `nil` in that case.

## Geographic features

GeoNames classifies every place with a `feature_class` and `feature_code`, and
GeoData stores both. The `:all` dataset includes every feature — mountains,
hills, lakes, rivers, forests, beaches, buildings and more — as
`kind: :feature` places. Instead of memorizing codes, filter by the semantic
names in `GeoData.Feature`:

```elixir
GeoData.features(where: [feature_code: :mountain])
GeoData.features(where: [feature_class: :landforms, country: "PT"])
GeoData.stream_features(where: [feature_code: [:lake, :waterfall]])
```

`features/1` and `stream_features/1` default `kind` to `[:feature, :locality]`
and order by name; they accept the same options as `search/2`.
`GeoData.feature_groups/0` and `GeoData.feature_classes/0` list the available
names, and raw codes/class letters keep working. Geographic features exist only
in the `:all` dataset (`:cities` ingests populated places only).

## Names and translations

Display names are localized at read time via
[Localize](https://hexdocs.pm/localize): countries and subdivisions are translated,
cities and other features use their canonical/ASCII name. GeoData stores only
the canonical (English) name and resolves the rest on demand, so nothing is
pre-translated at ingest.

```elixir
{:ok, de} = GeoData.country("DE")
GeoData.display_name(de, :en)                        #=> {:ok, "Germany"}
GeoData.display_name("ISO:PT", :en)                  #=> {:ok, "Portugal"}
GeoData.display_name("ISO:GB", :en, style: :short)   #=> {:ok, "UK"}
```

`GeoData.display_name/3` accepts a place or a canonical id, defaults to
`Localize.get_locale()` and, for countries, also takes
`style: :short` / `:variant`.

### Enabling other locales

Locale data is owned by Localize, which ships only `:en`. Point it at your app's
cache and download the locales you need:

```elixir
# config/config.exs
config :localize, otp_app: :my_app          # cache under my_app/priv
# config :localize, supported_locales: [:en, :pt]
# config :localize, default_locale: :pt
```

```sh
mix localize.download_locales pt
```

```elixir
GeoData.display_name("ISO:DE", :pt)          #=> {:ok, "Alemanha"}
GeoData.display_name("ISO:GB", :pt)          #=> {:ok, "Reino Unido"}
```

When a locale's data is unavailable, resolution **silently falls back** to the
canonical name rather than erroring.

Places also carry the GeoNames `alternatenames` as a list of strings in
`:names`, so search matches alternate names (e.g. "Lisbon" for Lisboa). Those
are untagged and search-only, i.e., they do not drive display names.

## Currencies and languages

Currency and language names are resolved from CLDR via Localize at read time.
`GeoData.Currency` reads a country's current currency directly from CLDR;
`GeoData.Language` names the languages a country carries from GeoNames
enrichment.

```elixir
{:ok, currency} = GeoData.Currency.get("EUR")
currency.name                        #=> "Euro"
currency.symbol                      #=> "€"

{:ok, [currency]} = GeoData.Currency.for_country("PT")
currency.code                        #=> "EUR"

{:ok, language} = GeoData.Language.get("de")
language.name                        #=> "German"

{:ok, languages} = GeoData.Language.for_country("PT")
Enum.map(languages, & &1.code)       #=> ["pt", "gl"]
```

Both `get/2` functions accept strings or atoms, are case-insensitive, and return
`{:ok, _}` or `{:error, %GeoData.UnknownCodeError{}}`; the `get!` variants
raise. Pass `locale:` to localize names (see
[Enabling other locales](#enabling-other-locales)). `for_country/1` accepts a
place or a country code and returns a list.

CLDR has no country-to-languages mapping, so `GeoData.Language.for_country/1`
relies on the `:languages` GeoNames adds during `:cities`/`:all` ingest and
returns `[]` on a `:base` store. Currencies come from CLDR and work on every
tier.

## Postal codes

`GeoData.Postal` validates, normalizes and formats postal codes.
Normalization and formatting are pure string work; validation uses the
per-territory regexes published by Google's
[libaddressinput](https://github.com/google/libaddressinput) i18n address
metadata (Apache-2.0). Nothing is downloaded unless you opt in with
`:postal_countries`:

```elixir
# config/config.exs
config :geodata, postal_countries: ["PT", "GB", "US"]   # or :all (~250 files)
```

The patterns are then fetched alongside ingestion (`mix geodata.ingest` /
`geodata.update`), or on demand with `mix geodata.postal`:

```shell
mix geodata.postal --countries PT,GB,US
mix geodata.postal --all
```

Until a country's pattern is loaded, validation reports `:not_loaded`:

```elixir
GeoData.Postal.valid?("1000-001", :pt)     #=> true (once PT is fetched)
GeoData.Postal.valid?("1000 001", :pt)     #=> false
GeoData.Postal.valid?("SW1A 1AA", "GB")    #=> true

GeoData.Postal.validate("999", :pt)        #=> {:error, :invalid}
GeoData.Postal.validate("12345", :ae)      #=> {:error, :not_loaded}

GeoData.Postal.normalize("sw1a 1aa")       #=> "SW1A1AA"
GeoData.Postal.format("1234123", :pt)      #=> "1234-123"
GeoData.Postal.format("sw1a1aa", :gb)      #=> "SW1A 1AA"
```

`valid?/2` is case-insensitive and trims/collapses whitespace. `normalize/1`
returns a comparison key (upper-cased, alphanumeric only). `format/2` renders
a best-effort canonical form: grouping is defined for `PT`, `NL`, `CA`, `GB`,
`JP`, `BR`, `PL`, `CZ`, `SK`, `SE`, `IE` and `MT`, and elsewhere the
normalized code is returned. `GeoData.Postal.countries/0` and
`supported?/1` describe the loaded patterns; `reset/0` clears them.

Territories without a postal system have no pattern and are absent from
`countries/0`. Postal-code data ingestion (looking up coordinates for a code)
is not part of the library yet.

## Listing places

```elixir
GeoData.countries()                    # every country, ordered by name
GeoData.countries(where: [continent: "EU"])
GeoData.subdivisions("US")             # subdivisions of a country

GeoData.stream_countries()             # lazy variants
GeoData.stream_subdivisions("US")
```

`:continent` is added by GeoNames enrichment, so the example above returns `[]`
on a `:base` store; the same applies to the other GeoNames-only country fields
(`:population`, `:capital`, `:neighbours`, ...). See [Datasets](#datasets) and
ingest `:cities` or `:all` to filter countries by them.

Listing helpers return a list and default to `limit: :infinity`; the `stream_*`
variants are lazy and unordered.

Codes are case-insensitive and may be strings or atoms: `GeoData.country("pt")`
and `GeoData.country(:pt)` are equivalent, as are
`GeoData.subdivision("us-ca")` / `GeoData.subdivision(:"US-CA")` and
`GeoData.place("5128581")`.

## Statistics and neighbours

`GeoData.Stats` aggregates the stored places and resolves country borders:

```elixir
{:ok, summary} = GeoData.Stats.summary()
summary.total
summary.by_kind         #=> %{country: 249, subdivision: 5046, ...}
summary.by_continent    #=> %{"EU" => 51, ...}

{:ok, country} = GeoData.Stats.country("PT", largest: 5)
country.subdivisions
country.cities
country.largest_cities
country.neighbours      #=> [%GeoData.Place{iso_3166_1: "ES"}, ...]
```

`GeoData.Stats.neighbours/1` returns the bordering countries of a country as
`GeoData.Place` records, and the raw codes are always on `place.neighbours`:

```elixir
GeoData.Stats.neighbours("ES")
#=> {:ok, [%GeoData.Place{iso_3166_1: "PT"}, %GeoData.Place{iso_3166_1: "FR"}]}

GeoData.country!("PT").neighbours
#=> ["ES"]
```

Borders come from the GeoNames `countryInfo` export and are ingested with the
rest of the country metadata, so an existing store must be re-ingested for
`neighbours/1` to return places.

## Distances and proximity

`GeoData.Distance` computes great-circle (spherical, haversine) distance and
bearing between points, which may be `{lat, lon}` tuples, maps or places.
Distances default to metres and accept a `:unit` (`:m`, `:km`, `:mi`, `:nm`):

```elixir
GeoData.Distance.between({48.8566, 2.3522}, {51.5074, -0.1278})
#=> 343_556.53

GeoData.Distance.between({0.0, 0.0}, {0.0, 1.0}, unit: :km)
#=> 111.195

GeoData.Distance.bearing({0.0, 0.0}, {0.0, 1.0})
#=> 90.0
```

It also provides `midpoint/2`, `destination/4`, `bounding_box/3`, `centroid/1`
and `within?/4`.

Fetch a point by code (a GeoNames id) and measure between two places:

```elixir
{:ok, lisbon} = GeoData.place(2_267_057)      # GN:2267057
{:ok, nyc}    = GeoData.place(5_128_581)      # GN:5128581

GeoData.Distance.between(lisbon, nyc)
#=> 5_411_xxx.x
```

Distances use each place's coordinates, so only places that have them work:
GeoNames cities and features do, while countries and subdivisions come from
`iso-codes` and carry no location.

Search understands proximity. Filter with `where: [near: {lat, lon, radius_m}]`
and order nearest-first with `order_by: {:distance, {lat, lon}}`; places
without coordinates are excluded by `:near` and sort last:

```elixir
GeoData.search(where: [near: {38.71667, -9.13333, 50_000}])

GeoData.search(nil,
  where: [kind: :city],
  order_by: {:distance, {38.71667, -9.13333}},
  limit: 10
)
```

`GeoData.nearest/3` wraps the two; `:radius` (metres) is optional and `:limit`
defaults to `5`:

```elixir
GeoData.nearest(38.71667, -9.13333, radius: 50_000, limit: 10)
```

`GeoData.near/2` takes a place or point (a place, `{lat, lon}`, coordinate map
or canonical id) instead of raw coordinates:

```elixir
GeoData.near("GN:2267057")                     # places nearest Lisbon
GeoData.near({38.71667, -9.13333}, radius: 5_000)
GeoData.near(GeoData.place!(2_267_057), limit: 3)
```

Proximity works on both engines. `GeoData.Search.Memory` evaluates it in memory,
and `GeoData.Search.Ecto` pushes `:near` and `{:distance, point}` into SQL as a
bounding-box prefilter plus a haversine expression, so a database-backed store
supports proximity without loading every row. `:fuzzy` matching remains
Memory-only.

## Boundaries and containment

`GeoData.Boundary` resolves which country and subdivision contain a coordinate,
using public-domain [Natural Earth](https://www.naturalearthdata.com/) polygons
and [`topo`](https://hexdocs.pm/topo) for point-in-polygon tests. Like postal
codes, it is opt-in and downloads nothing until configured:

```elixir
# config/config.exs
config :geodata, boundaries: [:country, :subdivision]
```

Boundary files are then fetched alongside ingestion, or on demand:

```shell
mix geodata.boundaries --all
mix geodata.boundaries --levels country
```

```elixir
GeoData.containing(40.20, -8.42)
#=> {:ok, [%GeoData.Place{kind: :country, iso_3166_1: "PT"},
#          %GeoData.Place{kind: :subdivision, iso_3166_2: "PT-06"}]}

GeoData.containing(0.0, 0.0)
#=> {:ok, []}
```

`containing/3` returns the containing `GeoData.Place` records, ordered from
coarse to fine (country before subdivision); pass `kind:` or `kinds:` to
restrict the levels (`kind: :country`). A coordinate that falls on a border is
still matched through `Topo.intersects?/2` rather than strictly contained. An
ocean point, or an area with no ingested place, yields `{:ok, []}`.

The polygon geometry is exposed by `GeoData.Boundary` as a `%Geo.Polygon{}` or
`%Geo.MultiPolygon{}`, with predicates and the bounding box:

```elixir
{:ok, boundary} = GeoData.boundary("ISO:PT")
GeoData.Boundary.contains?(boundary, {40.20, -8.42})   #=> true
GeoData.Boundary.bbox(boundary)                        #=> {min_lat, min_lon, max_lat, max_lon}

GeoData.boundaries(kind: :country)
GeoData.stream_boundaries()
GeoData.within?({40.20, -8.42}, "ISO:PT")
```

`:boundary_detail` selects the Natural Earth scale for **countries**: `:low`
(1:50m, the default) or `:high` (1:10m, more accurate). **Subdivisions always
use 1:10m**. Use `:high` for more accurate country borders too:

```elixir
config :geodata, boundaries: [:country, :subdivision], boundary_detail: :high
```

The simplified 1:50m coastline can drop a coastal or estuarine point into the
water — for example downtown Lisbon (`38.72, -9.13`) sits in the carved-out
Tagus estuary, so the `:low` country polygon does not contain it. Use `:high`
when coastal accuracy matters.

Boundaries are a query dataset: GeoData does not draw maps. Encode the geometry
with `Geo.JSON.encode!/1` if you need to render it.

## Storage and caching

See [Choosing storage and search](#choosing-storage-and-search) for a use-case
table. `:base` and `:cities` fit comfortably in memory with the default `ETS`
adapter. To persist a dataset across restarts, use the sharded `DETS` adapter;
shards are written under `:storage_path` (kept under the 2 GB DETS limit per
file, so `:all` is supported):

```elixir
config :geodata,
  storage: GeoData.Storage.DETS,
  storage_path: "priv/geodata",
  memory_mode: :lazy
```

`:memory_mode` controls dataset residency: `:eager` (the default) mirrors the
whole dataset into ETS at startup and builds the in-memory text index, so reads
and text searches never touch disk; `:lazy` reads from DETS on every access and
builds no index, so text searches fall back to a disk scan per query, which suits
id lookups on a RAM-constrained machine.

For a database-backed store, use `GeoData.Storage.Ecto` with any Ecto SQL repo
(PostgreSQL, MySQL, SQLite, ...). Add `ecto_sql` and a driver for your backend,
then:

```elixir
config :geodata, storage: GeoData.Storage.Ecto
config :geodata, GeoData.Storage.Ecto, repo: MyApp.Repo
```

It keeps one row per place in a `geodata_places` table.
Create it with the bundled versioned migration:

```elixir
defmodule MyApp.Repo.Migrations.AddGeoData do
  use Ecto.Migration

  def up, do: GeoData.Storage.Ecto.Migrations.up()
  def down, do: GeoData.Storage.Ecto.Migrations.down()
end
```

Migrations are additive and idempotent; future GeoData releases add a version
that existing installs apply with `GeoData.Storage.Ecto.Migrations.up(version: N)`.

`iso_3166_1`, `iso_3166_2`, `geonames_id`, `kind` and `parent_id` are indexed,
so the places of a country and the children of a place are cheap to query, and
`GeoData.Search.Ecto` keeps every arm of its exact code/GeoNames `OR` indexable
(the migration installs the indexes). The schema exposes `:parent` /
`:children` associations for `preload/3`:

```elixir
import Ecto.Query
alias GeoData.Storage.Ecto.Place

# cities (or every place) in Portugal
from(p in Place, where: p.iso_3166_1 == "PT" and p.kind == "city")
from(p in Place, where: p.iso_3166_1 == "PT")
from(p in Place, where: p.parent_id == "ISO:PT")

Repo.one(from(p in Place, where: p.id == "ISO:PT", preload: [:children]))
```

## Licensing

The library code is released under the [MIT License](LICENSE). It does not
bundle third-party data. Data downloaded and ingested at build time remains
subject to its source licenses:

- iso-codes: LGPL-2.1-or-later
- GeoNames: CC BY 4.0
- Natural Earth (boundaries): public domain

Every ingestion writes an `attribution.json` manifest to the configured
`:storage_path`, recording each contributing source, its license and the
required attribution so redistributed datasets carry the necessary notices.
