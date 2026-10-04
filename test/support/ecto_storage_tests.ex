defmodule GeoData.EctoStorageTests do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case, async: false
      use GeoData.EctoSetup
      use GeoData.StorageTests, adapter: GeoData.Storage.Ecto
    end
  end
end
