defmodule GeodataIntegration.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :geodata_integration,
    adapter: Ecto.Adapters.SQLite3
end

defmodule GeodataIntegration.Repo.Migrations.CreateGeoDataPlaces do
  @moduledoc false

  use Ecto.Migration

  # Exactly the migration documented in `GeoData.Storage.Ecto`.
  def up, do: GeoData.Storage.Ecto.Migrations.up()
  def down, do: GeoData.Storage.Ecto.Migrations.down()
end

if Code.ensure_loaded?(Postgrex) do
  defmodule GeodataIntegration.PostgresRepo do
    @moduledoc false

    use Ecto.Repo,
      otp_app: :geodata_integration,
      adapter: Ecto.Adapters.Postgres
  end

  defmodule GeodataIntegration.PostgresRepo.Migrations.CreateGeoDataPlaces do
    @moduledoc false

    use Ecto.Migration

    def up, do: GeoData.Storage.Ecto.Migrations.up()
    def down, do: GeoData.Storage.Ecto.Migrations.down()
  end
end
