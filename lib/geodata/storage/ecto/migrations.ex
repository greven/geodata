if Code.ensure_loaded?(Ecto.Migration) do
  defmodule GeoData.Storage.Ecto.Migrations.V01 do
    @moduledoc false

    use Ecto.Migration

    @trigram_columns ~w(search_name search_ascii search_alternates)

    def up(opts \\ []) do
      prefix = Keyword.get(opts, :prefix)

      create_if_not_exists table(:geodata_places, primary_key: false, prefix: prefix) do
        add(:id, :string, primary_key: true)
        add(:kind, :string)
        add(:iso_3166_1, :string)
        add(:iso_3166_2, :string)
        add(:name, :text)
        add(:ascii_name, :text)
        add(:search_name, :text)
        add(:search_ascii, :text)
        add(:search_alternates, :text)
        add(:latitude, :float)
        add(:longitude, :float)
        add(:elevation, :integer)
        add(:population, :integer)
        add(:geonames_id, :integer)
        add(:feature_class, :string)
        add(:feature_code, :string)
        add(:parent_id, :string)
        add(:continent, :string)
        add(:timezone, :string)
        add(:updated_at, :date)
        add(:data, :binary)
      end

      create_if_not_exists(index(:geodata_places, [:search_name], prefix: prefix))
      create_if_not_exists(index(:geodata_places, [:search_ascii], prefix: prefix))
      create_if_not_exists(index(:geodata_places, [:kind], prefix: prefix))
      create_if_not_exists(index(:geodata_places, [:iso_3166_1, :kind], prefix: prefix))
      create_if_not_exists(index(:geodata_places, [:iso_3166_2], prefix: prefix))
      create_if_not_exists(index(:geodata_places, [:geonames_id], prefix: prefix))
      create_if_not_exists(index(:geodata_places, [:parent_id], prefix: prefix))
      create_if_not_exists(index(:geodata_places, [:continent], prefix: prefix))
      create_if_not_exists(index(:geodata_places, [:population], prefix: prefix))

      if postgres?(), do: install_trigrams(prefix)
    end

    def down(opts \\ []) do
      drop_if_exists(table(:geodata_places, prefix: Keyword.get(opts, :prefix)))
    end

    # PostgreSQL-only: install pg_trgm and GIN trigram indexes on the search
    # columns so `GeoData.Search.Ecto` can push fuzzy matching down.
    defp install_trigrams(prefix) do
      execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

      Enum.each(@trigram_columns, fn column ->
        execute(
          "CREATE INDEX IF NOT EXISTS #{index_name(prefix, column)} " <>
            "ON #{table_name(prefix)} USING gin (#{column} gin_trgm_ops)"
        )
      end)
    end

    defp postgres?, do: repo().__adapter__() == Ecto.Adapters.Postgres

    defp table_name(nil), do: "geodata_places"
    defp table_name(prefix), do: "#{prefix}.geodata_places"

    defp index_name(nil, column), do: "geodata_places_#{column}_trgm"
    defp index_name(prefix, column), do: "#{prefix}.geodata_places_#{column}_trgm"
  end

  defmodule GeoData.Storage.Ecto.Migrations do
    @moduledoc """
    Versioned Ecto migrations for the `geodata_places` table.

    Reference it from a single Ecto migration instead of writing the DDL by
    hand:

        defmodule MyApp.Repo.Migrations.AddGeoData do
          use Ecto.Migration

          def up, do: GeoData.Storage.Ecto.Migrations.up()
          def down, do: GeoData.Storage.Ecto.Migrations.down()
        end

    Migrations are additive and idempotent, so future GeoData releases add a
    new version and existing installs apply just the delta with a new Ecto
    migration, e.g. `GeoData.Storage.Ecto.Migrations.up(version: 2)`.

    On PostgreSQL, `up/1` also installs the `pg_trgm` extension and adds GIN
    trigram indexes on the search columns, which enables fuzzy search pushdown.
    It is a no-op on other backends.

    ## Options

      * `:version` - apply up to this schema version, default `current_version/0`
      * `:prefix` - database prefix/schema for the table and indexes

    """

    @current_version 1

    @versions %{1 => GeoData.Storage.Ecto.Migrations.V01}

    @doc """
    Returns the latest schema version.
    """
    def current_version, do: @current_version

    @doc """
    Applies every migration up to `:version` (default the current version).
    """
    def up(opts \\ []) do
      target = Keyword.get(opts, :version, @current_version)

      Enum.each(1..target, fn version -> module(version).up(opts) end)
      :ok
    end

    @doc """
    Reverses migrations down to `:version` (default `1`).
    """
    def down(opts \\ []) do
      target = Keyword.get(opts, :version, 1)

      target..1//-1
      |> Enum.each(fn version -> module(version).down(opts) end)

      :ok
    end

    defp module(version), do: Map.fetch!(@versions, version)
  end
end
