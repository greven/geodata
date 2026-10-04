defmodule GeoData.StorageTest do
  use ExUnit.Case, async: false

  alias GeoData.Place
  alias GeoData.Storage

  setup do
    Storage.reset()
    :ok
  end

  test "storage_mod/0 returns the configured adapter" do
    assert Storage.storage_mod() == GeoData.Storage.ETS
  end

  test "delegates to the configured adapter" do
    place = Place.new!(id: "GN:1", kind: :city, name: "Lisbon")

    assert :ok = Storage.put_many([place])
    assert {:ok, ^place} = Storage.get("GN:1")
    assert Storage.count() == 1

    assert :ok = Storage.delete("GN:1")
    assert {:error, :not_found} = Storage.get("GN:1")
  end
end
