defmodule GeoData.PostalTest do
  use ExUnit.Case, async: false

  alias GeoData.Postal

  doctest GeoData.Postal

  setup do
    root = Path.join(System.tmp_dir!(), "geodata_postal_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "postal"))
    previous = Application.get_env(:geodata, :source_path)
    Application.put_env(:geodata, :source_path, Path.join(root, "unloaded"))
    Postal.reset()

    on_exit(fn ->
      Postal.reset()

      if previous do
        Application.put_env(:geodata, :source_path, previous)
      else
        Application.delete_env(:geodata, :source_path)
      end

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  describe "before patterns are loaded" do
    test "validation reports :not_loaded and nothing is supported" do
      refute Postal.valid?("1000-001", :pt)
      assert Postal.validate("1000-001", :pt) == {:error, :not_loaded}
      refute Postal.supported?(:pt)
      assert Postal.countries() == []
    end

    test "normalization and formatting still work" do
      assert Postal.normalize("sw1a 1aa") == "SW1A1AA"
      assert Postal.format("1234123", :pt) == "1234-123"
    end
  end

  describe "fetch/1" do
    test "loads the requested countries and validates against their patterns", %{root: root} do
      fixture(root, "PT", ~S"\d{4}-\d{3}")
      fixture(root, "US", ~S"(\d{5})(?:[ \-](\d{4}))?")

      assert {:ok, info} =
               Postal.fetch(postal_countries: ["PT", "US"], source_path: root)

      assert info.countries == ["PT", "US"]
      assert Postal.countries() == ["PT", "US"]

      assert Postal.valid?("1000-001", :pt)
      assert Postal.valid?("12345", "US")
      assert Postal.valid?("12345-6789", "US")
      refute Postal.valid?("1000 001", :pt)
      refute Postal.valid?("1234", "US")
      assert Postal.validate("999", :pt) == {:error, :invalid}
      assert Postal.supported?(:pt)
    end

    test "accepts atoms and lower-case codes", %{root: root} do
      fixture(root, "PT", ~S"\d{4}-\d{3}")
      assert {:ok, _info} = Postal.fetch(postal_countries: [:pt], source_path: root)
      assert Postal.valid?("1000-001", "pt")
    end

    test "does not load countries that were not requested", %{root: root} do
      fixture(root, "PT", ~S"\d{4}-\d{3}")
      assert {:ok, _info} = Postal.fetch(postal_countries: ["PT"], source_path: root)

      refute Postal.valid?("SW1A 1AA", "GB")
      assert Postal.validate("SW1A 1AA", :gb) == {:error, :not_loaded}
    end

    test "resolves :all from the index, skipping countries without a pattern", %{root: root} do
      index(root, ~w(PT US AE))
      fixture(root, "PT", ~S"\d{4}-\d{3}")
      fixture(root, "US", ~S"\d{5}")
      fixture(root, "AE", nil)

      assert {:ok, info} = Postal.fetch(postal_countries: :all, source_path: root)

      assert info.countries == ["PT", "US"]
      assert Postal.supported?("PT")
      refute Postal.supported?("AE")
    end

    test "loads a GB-style pattern and rejects trailing characters", %{root: root} do
      fixture(root, "GB", ~S"GIR ?0AA|[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}")

      assert {:ok, _info} = Postal.fetch(postal_countries: ["GB"], source_path: root)

      assert Postal.valid?("W1A 0AX", :gb)
      assert Postal.valid?("SW1A 1AA", :gb)
      refute Postal.valid?("WC2H 7LTa", :gb)
    end

    test "is idempotent and reuses cached files", %{root: root} do
      fixture(root, "PT", ~S"\d{4}-\d{3}")

      assert {:ok, first} = Postal.fetch(postal_countries: ["PT"], source_path: root)
      assert {:ok, second} = Postal.fetch(postal_countries: ["PT"], source_path: root)

      assert first.countries == ["PT"]
      assert second.countries == ["PT"]
    end
  end

  describe "reset/0" do
    test "clears the loaded patterns", %{root: root} do
      fixture(root, "PT", ~S"\d{4}-\d{3}")
      assert {:ok, _info} = Postal.fetch(postal_countries: ["PT"], source_path: root)
      assert Postal.valid?("1000-001", :pt)

      Postal.reset()
      assert Postal.validate("1000-001", :pt) == {:error, :not_loaded}
    end
  end

  describe "normalize/1" do
    test "upcases and strips non-alphanumerics" do
      assert Postal.normalize("sw1a 1aa") == "SW1A1AA"
      assert Postal.normalize("1000-001") == "1000001"
      assert Postal.normalize(" VLT 1234 ") == "VLT1234"
      assert Postal.normalize("10115") == "10115"
      assert Postal.normalize(nil) == ""
    end
  end

  describe "format/2" do
    test "renders the canonical grouping for supported countries" do
      assert Postal.format("1234123", :pt) == "1234-123"
      assert Postal.format("k1a0b1", :ca) == "K1A 0B1"
      assert Postal.format("sw1a1aa", :gb) == "SW1A 1AA"
      assert Postal.format("1000001", :jp) == "100-0001"
      assert Postal.format("10000000", :br) == "10000-000"
      assert Postal.format("a65f4e2", :ie) == "A65 F4E2"
      assert Postal.format("vlt1234", :mt) == "VLT 1234"
      assert Postal.format("1235df", :nl) == "1235 DF"
    end

    test "returns the normalized code for countries without a grouping rule" do
      assert Postal.format("10115", :de) == "10115"
      assert Postal.format(" 00100 ", :fi) == "00100"
    end

    test "falls back to the normalized code when the mask does not fit" do
      assert Postal.format("6250", :pt) == "6250"
      assert Postal.format("ABC", :gb) == "ABC"
      assert Postal.format(nil, :pt) == ""
    end
  end

  defp fixture(root, country, zip) do
    data = if zip, do: %{"zip" => zip, "zipex" => "1000-001"}, else: %{"id" => "data/#{country}"}
    File.write!(Path.join([root, "postal", "#{country}.json"]), JSON.encode!(data))
  end

  defp index(root, countries) do
    body = %{"countries" => Enum.join(countries, "~")}
    File.write!(Path.join([root, "postal", "_index.json"]), JSON.encode!(body))
  end
end
