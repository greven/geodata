defmodule GeoData.PostalNetworkTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias GeoData.Postal

  setup do
    root =
      Path.join(System.tmp_dir!(), "geodata_postal_net_#{System.unique_integer([:positive])}")

    Postal.reset()

    on_exit(fn ->
      Postal.reset()
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "fetches real patterns and validates their examples", %{root: root} do
    assert {:ok, info} =
             Postal.fetch(
               postal_countries: ["PT", "GB", "CA", "NL", "US"],
               source_path: root
             )

    assert Enum.sort(info.countries) == ["CA", "GB", "NL", "PT", "US"]

    assert Postal.valid?("1000-001", :pt)
    assert Postal.valid?("SW1A 1AA", "GB")
    assert Postal.valid?("W1A 0AX", "GB")
    assert Postal.valid?("K1A 0B1", :ca)
    assert Postal.valid?("1234 AB", :nl)
    assert Postal.valid?("12345-6789", :us)

    refute Postal.valid?("1000 001", :pt)
    refute Postal.valid?("1945SS", :nl)
    assert Postal.validate("SW1A 1AA", :us) == {:error, :invalid}
  end
end
