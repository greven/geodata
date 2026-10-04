defmodule GeoData.Storage.Ecto.TestRepo do
  @moduledoc false

  use Ecto.Repo, otp_app: :geodata, adapter: Ecto.Adapters.SQLite3
end

defmodule GeoData.Storage.Ecto.TestRepo.Migrations.CreateGeoDataPlaces do
  @moduledoc false

  use Ecto.Migration

  def up, do: GeoData.Storage.Ecto.Migrations.up()
  def down, do: GeoData.Storage.Ecto.Migrations.down()
end
