if Code.ensure_loaded?(Ecto.Query) do
  defmodule GeoData.Storage.Ecto.Place do
    @moduledoc false

    use Ecto.Schema

    @primary_key {:id, :string, autogenerate: false}

    schema "geodata_places" do
      field(:kind, :string)
      field(:iso_3166_1, :string)
      field(:iso_3166_2, :string)
      field(:name, :string)
      field(:ascii_name, :string)
      field(:search_name, :string)
      field(:search_ascii, :string)
      field(:search_alternates, :string)
      field(:latitude, :float)
      field(:longitude, :float)
      field(:elevation, :integer)
      field(:population, :integer)
      field(:geonames_id, :integer)
      field(:feature_class, :string)
      field(:feature_code, :string)
      field(:parent_id, :string)
      field(:continent, :string)
      field(:timezone, :string)
      field(:updated_at, :date)
      field(:data, :binary)

      belongs_to(:parent, __MODULE__,
        foreign_key: :parent_id,
        references: :id,
        define_field: false
      )

      has_many(:children, __MODULE__, foreign_key: :parent_id)
    end
  end

  defmodule GeoData.Storage.Ecto do
    @moduledoc """
    Ecto-backed `GeoData.Storage` adapter.

    Works with any Ecto SQL backend (PostgreSQL, MySQL, SQLite, ...) through a
    user-provided repo. Point GeoData at it:

        config :geodata, storage: GeoData.Storage.Ecto
        config :geodata, GeoData.Storage.Ecto, repo: MyApp.Repo

    Each place is stored as a row in the `geodata_places` table: the commonly
    queried attributes are real columns, and the complete `GeoData.Place` is
    kept in an opaque `data` column so no field is lost regardless of backend.

    Create the table with the bundled versioned migration:

        defmodule MyApp.Repo.Migrations.AddGeoData do
          use Ecto.Migration

          def up, do: GeoData.Storage.Ecto.Migrations.up()
          def down, do: GeoData.Storage.Ecto.Migrations.down()
        end

    ## Querying relationships

    Places form a two-level hierarchy: a city or feature's `parent_id` is its
    country (`"ISO:PT"`), and a subdivision's parent is also its country.
    `iso_3166_1` carries the country code on every place, and both columns are
    indexed, so filtering by country or by parent is cheap. `iso_3166_2` and
    `geonames_id` are indexed too, because `GeoData.Search.Ecto` ORs exact code
    and GeoNames-id lookups into every text query; leaving them unindexed makes
    the whole `OR` fall back to a sequential scan.

        import Ecto.Query
        alias GeoData.Storage.Ecto.Place

        # every city in a country
        from(p in Place, where: p.iso_3166_1 == "PT" and p.kind == "city")

        # every place in a country
        from(p in Place, where: p.iso_3166_1 == "PT")

        # the direct children of a place
        from(p in Place, where: p.parent_id == "ISO:PT")

    The schema also exposes `:parent` and `:children` associations for
    `preload/3`:

        Repo.one(from(p in Place, where: p.id == "ISO:PT", preload: [:children]))

    `search_name`, `search_ascii` and `search_alternates` hold accent-folded,
    lowercased names (the last one the space-joined alternates) used by
    `GeoData.Search.Ecto`; they are written on ingest, so existing rows must be
    re-ingested after adding them. On PostgreSQL, add `text_pattern_ops`
    indexes on the search columns to index `LIKE 'prefix%'` without `pg_trgm`.
    """

    @behaviour GeoData.Storage

    import Ecto.Query

    alias GeoData.Search.Query
    alias GeoData.Storage.Ecto.Place, as: Row

    @batch_size 1_000

    @impl true
    def put_many(places) when is_list(places) do
      places
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn chunk ->
        rows = Enum.map(chunk, &to_row/1)
        repo().insert_all(Row, rows, on_conflict: :replace_all, conflict_target: [:id])
      end)

      :ok
    end

    @impl true
    def get(id) do
      case repo().get(Row, id) do
        nil -> {:error, :not_found}
        row -> {:ok, from_row(row)}
      end
    end

    @impl true
    def delete(id) do
      repo().delete_all(from(row in Row, where: row.id == ^id))
      :ok
    end

    @impl true
    def stream do
      Stream.resource(
        fn -> :start end,
        fn
          :done ->
            {:halt, :done}

          cursor ->
            case fetch_after(cursor) do
              [] -> {:halt, :done}
              rows -> {Enum.map(rows, &from_row/1), List.last(rows).id}
            end
        end,
        fn _ -> :ok end
      )
    end

    @impl true
    def count, do: repo().aggregate(Row, :count)

    @impl true
    def reset do
      repo().delete_all(Row)
      :ok
    end

    @impl true
    def initialized? do
      case repo_config() do
        nil -> false
        repo -> Process.whereis(repo) != nil
      end
    end

    defp fetch_after(:start) do
      repo().all(from(row in Row, order_by: [asc: row.id], limit: @batch_size))
    end

    defp fetch_after(cursor) do
      repo().all(
        from(row in Row,
          where: row.id > ^cursor,
          order_by: [asc: row.id],
          limit: @batch_size
        )
      )
    end

    defp to_row(place) do
      %{
        id: place.id,
        kind: to_string(place.kind),
        iso_3166_1: place.iso_3166_1,
        iso_3166_2: place.iso_3166_2,
        name: place.name,
        ascii_name: place.ascii_name,
        search_name: Query.normalize(place.name),
        search_ascii: Query.normalize(place.ascii_name),
        search_alternates: search_alternates(place),
        latitude: place.latitude,
        longitude: place.longitude,
        elevation: place.elevation,
        population: place.population,
        geonames_id: place.geonames_id,
        feature_class: place.feature_class,
        feature_code: place.feature_code,
        parent_id: place.parent_id,
        continent: place.continent,
        timezone: place.timezone,
        updated_at: place.updated_at,
        data: :erlang.term_to_binary(place)
      }
    end

    defp from_row(%Row{data: data}) when is_binary(data),
      do: :erlang.binary_to_term(data, [:safe])

    defp search_alternates(place) do
      place.names
      |> Enum.map(&Query.normalize/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.join(" ")
    end

    defp repo_config, do: Keyword.get(Application.get_env(:geodata, __MODULE__, []), :repo)

    defp repo do
      case repo_config() do
        nil ->
          raise ArgumentError,
                "no Ecto repo configured; set config :geodata, #{inspect(__MODULE__)}, repo: MyApp.Repo"

        repo ->
          repo
      end
    end
  end
end
