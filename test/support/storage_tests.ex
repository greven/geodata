defmodule GeoData.StorageTests do
  @moduledoc false

  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)

    quote do
      @adapter unquote(adapter)

      setup do
        @adapter.reset()
        :ok
      end

      test "put_many/1 and get/1 round-trip" do
        place = place("GN:1", "Lisbon")

        assert :ok = @adapter.put_many([place])
        assert {:ok, ^place} = @adapter.get("GN:1")
      end

      test "get/1 returns {:error, :not_found} for a missing id" do
        assert {:error, :not_found} = @adapter.get("GN:missing")
      end

      test "put_many/1 upserts by id" do
        assert :ok = @adapter.put_many([place("GN:1", "Lisbon")])
        assert :ok = @adapter.put_many([place("GN:1", "Lisboa")])

        assert {:ok, %GeoData.Place{name: "Lisboa"}} = @adapter.get("GN:1")
        assert @adapter.count() == 1
      end

      test "delete/1 removes a place" do
        assert :ok = @adapter.put_many([place("GN:1", "Lisbon")])
        assert :ok = @adapter.delete("GN:1")
        assert {:error, :not_found} = @adapter.get("GN:1")
      end

      test "count/0 returns the number of places" do
        assert @adapter.count() == 0

        assert :ok =
                 @adapter.put_many([place("GN:1", "A"), place("GN:2", "B")])

        assert @adapter.count() == 2
      end

      test "stream/0 yields every place" do
        assert :ok =
                 @adapter.put_many([place("GN:1", "A"), place("GN:2", "B")])

        names = @adapter.stream() |> Enum.map(& &1.name) |> Enum.sort()
        assert names == ["A", "B"]
      end

      test "put_many/1 stores long names and alternates" do
        long_name = String.duplicate("n", 500)
        long_alternate = String.duplicate("a", 4_000)

        place =
          GeoData.Place.new!(
            id: "GN:long",
            kind: :city,
            name: long_name,
            ascii_name: long_name,
            names: [long_alternate]
          )

        assert :ok = @adapter.put_many([place])
        assert {:ok, %GeoData.Place{name: ^long_name} = stored} = @adapter.get("GN:long")
        assert long_alternate in stored.names
      end

      test "reset/0 removes every place" do
        assert :ok = @adapter.put_many([place("GN:1", "A")])
        assert :ok = @adapter.reset()
        assert @adapter.count() == 0
      end

      test "initialized?/0 is true once started" do
        assert @adapter.initialized?()
      end

      defp place(id, name) do
        GeoData.Place.new!(id: id, kind: :city, name: name)
      end
    end
  end
end
