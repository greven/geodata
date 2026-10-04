defmodule GeoData.IngestTest do
  use ExUnit.Case, async: false

  alias GeoData.Fixtures
  alias GeoData.Ingest
  alias GeoData.Storage

  setup do
    Storage.reset()

    dir = Path.join(System.tmp_dir!(), "geodata-ingest-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      Storage.reset()
      File.rm_rf(dir)
    end)

    {:ok, storage_path: Path.join(dir, "storage"), source_path: Path.join(dir, "sources")}
  end

  test "ingests iso-codes from local files", %{
    storage_path: storage_path,
    source_path: source_path
  } do
    opts = [
      dataset: :base,
      sources: [:iso_codes],
      files: Fixtures.iso_3166_paths(),
      storage_path: storage_path,
      source_path: source_path,
      reset: true
    ]

    assert {:ok, report} = Ingest.run(opts)
    assert report.sources == [:iso_codes]
    assert report.total == 6
    assert report.by_kind == %{country: 3, subdivision: 3}
    assert report.by_source == %{iso_codes: 6}

    assert {:ok, pt} = GeoData.country("PT")
    assert pt.name == "Portugal"
    assert Storage.count() == 6

    assert File.exists?(report.attribution)
    assert report.attribution == Path.join(storage_path, "attribution.json")
  end

  test "reports provided file status", %{storage_path: storage_path, source_path: source_path} do
    {:ok, report} =
      Ingest.run(
        dataset: :base,
        sources: [:iso_codes],
        files: Fixtures.iso_3166_paths(),
        storage_path: storage_path,
        source_path: source_path
      )

    assert report.files[:iso_codes][:iso_3166_1].status == :provided
  end

  test "ingests iso-codes and geonames for :cities", %{
    storage_path: storage_path,
    source_path: source_path
  } do
    opts = [
      dataset: :cities,
      sources: [:iso_codes, :geonames],
      files: Fixtures.all_paths(),
      storage_path: storage_path,
      source_path: source_path,
      reset: true
    ]

    assert {:ok, report} = Ingest.run(opts)
    assert report.sources == [:iso_codes, :geonames]
    assert report.total == 12
    assert report.by_kind == %{country: 6, subdivision: 3, city: 2, locality: 1}
    assert report.by_source == %{iso_codes: 6, geonames: 7}

    assert {:ok, pt} = GeoData.country("PT")
    assert pt.name == "Portugal"
    assert pt.capital == "Lisbon"
    assert Enum.sort(pt.sources) == [:geonames, :iso_codes]

    assert {:error, %GeoData.NotFoundError{}} = GeoData.country("AN")

    assert {:ok, xk} = GeoData.country("XK")
    assert xk.name == "Kosovo"
    assert xk.sources == [:geonames]

    assert {:ok, ca} = GeoData.subdivision("US-CA")
    assert ca.iso_3166_2 == "US-CA"
    assert ca.geonames_id == nil
    assert ca.sources == [:iso_codes]

    assert {:ok, pt11} = GeoData.subdivision("PT-11")
    assert pt11.name == "Lisboa"
    assert pt11.ascii_name == nil
    assert pt11.geonames_id == nil
    assert pt11.sources == [:iso_codes]

    assert {:ok, ny} = GeoData.place(5_128_581)
    assert ny.name == "New York City"
    assert ny.kind == :city

    assert Storage.count() == 12

    assert {:ok, lisbon} = GeoData.place(2_267_057)
    assert lisbon.name == "Lisboa"
    assert lisbon.names == ["Lisbon"]
    assert GeoData.display_name(lisbon, :en) == {:ok, "Lisboa"}

    assert {:ok, found} = GeoData.search("Lisbon", where: [kind: :city])
    assert Enum.map(found.places, & &1.id) == ["GN:2267057"]

    manifest = report.attribution |> File.read!() |> JSON.decode!()
    assert manifest["dataset"] == "cities"
    assert Enum.map(manifest["sources"], & &1["name"]) == ["iso-codes", "GeoNames"]
    assert Enum.find(manifest["sources"], &(&1["name"] == "GeoNames"))["license"] == "CC BY 4.0"
  end

  test ":base ignores geonames even when requested", %{
    storage_path: storage_path,
    source_path: source_path
  } do
    opts = [
      dataset: :base,
      sources: [:iso_codes, :geonames],
      files: Fixtures.iso_3166_paths(),
      storage_path: storage_path,
      source_path: source_path,
      reset: true
    ]

    assert {:ok, report} = Ingest.run(opts)
    assert report.sources == [:iso_codes]
    assert report.total == 6
  end

  test "keeps existing storage when a download fails before reset", %{
    storage_path: storage_path,
    source_path: source_path
  } do
    place = GeoData.Place.new!(id: "ISO:PT", kind: :country, iso_3166_1: "PT", name: "Portugal")
    assert :ok = GeoData.put_many([place])
    assert Storage.count() == 1

    downloader = fn file, _path, _opts ->
      {:error, %GeoData.DownloadError{url: file.url, reason: :http_error}}
    end

    assert {:error, %GeoData.DownloadError{}} =
             Ingest.run(
               dataset: :base,
               sources: [:iso_codes],
               storage_path: storage_path,
               source_path: source_path,
               reset: true,
               downloader: downloader
             )

    assert Storage.count() == 1
    assert {:ok, _} = GeoData.country("PT")
  end

  test "returns a validation error for invalid options" do
    assert {:error, %GeoData.ValidationError{reason: :invalid_option}} =
             Ingest.run(dataset: :bogus)
  end
end
