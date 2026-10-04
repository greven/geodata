defmodule GeoData.Storage.DETS do
  @shards 64

  @moduledoc """
  DETS-backed `GeoData.Storage` adapter.

  Places are persisted across restarts in sharded DETS tables under the
  configured `:storage_path`. The dataset is spread over #{@shards} tables by a
  hash of the id, so no single file approaches the 2 GB DETS limit and the
  `:all` tier can be stored.

  Rows also carry the place's normalized search terms (built once with
  `GeoData.Search.Query.terms/1`) so `stream_with_terms/0` and
  `get_with_terms/1` can serve `GeoData.Search.Memory` without re-normalizing.
  Rows written by an older version (without terms) are read with `nil` terms and
  still work, re-ingest to add the terms.

  `:memory_mode` controls how much of the dataset is kept in memory:

    * `:eager` (default) - the full dataset is mirrored into ETS at startup;
      reads never touch disk, and the in-memory text index
      (`GeoData.Storage.Index`) is built so `candidates/2` can resolve text
      queries from candidates instead of scanning every row.
    * `:lazy` - every read goes to disk. Best when RAM is tight and lookups are
      mostly by id; no index is built, so text searches are full disk scans.

  `:storage_path` and `:memory_mode` are read from the application environment
  at startup so they can be set at runtime.
  """

  @behaviour GeoData.Storage

  use GenServer

  alias GeoData.Search.Query
  alias GeoData.Storage.Index

  @eager :geodata_dets_eager
  @eager_index :geodata_dets_eager_index
  @eager_tokens :geodata_dets_eager_tokens
  @eager_trigram_index :geodata_dets_eager_trigram_index
  @eager_trigrams :geodata_dets_eager_trigrams

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    path = Application.get_env(:geodata, :storage_path, "priv/geodata")
    mode = Application.get_env(:geodata, :memory_mode, :eager)
    File.mkdir_p!(path)

    tables = open_shards(path)
    table_tuple = tables |> Enum.map(&elem(&1, 1)) |> List.to_tuple()

    case mode do
      :eager ->
        ensure_eager()
        load_eager(tables)

      :lazy ->
        :ok
    end

    {:ok, %{tables: tables, table_tuple: table_tuple, mode: mode}}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.tables, fn {_i, table} -> :dets.close(table) end)
    :ok
  end

  @impl true
  def put_many(places) when is_list(places), do: GenServer.call(__MODULE__, {:put_many, places})

  @impl true
  def get(id) do
    case get_with_terms(id) do
      {:ok, place, _terms} -> {:ok, place}
      error -> error
    end
  end

  @impl true
  def get_with_terms(id) do
    with true <- initialized?(),
         {:ok, {place, terms}} <- do_get(id) do
      {:ok, place, terms}
    else
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def delete(id), do: GenServer.call(__MODULE__, {:delete, id})

  @impl true
  def stream, do: Stream.map(stream_with_terms(), &elem(&1, 0))

  @impl true
  def stream_with_terms do
    if initialized?() do
      if mode() == :eager, do: stream_eager(), else: stream_dets()
    else
      []
    end
  end

  @impl true
  def count do
    if initialized?() do
      if mode() == :eager do
        :ets.info(@eager, :size)
      else
        Enum.reduce(0..(@shards - 1), 0, fn i, acc -> acc + dets_size(shard_name(i)) end)
      end
    else
      0
    end
  end

  @impl true
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def initialized?, do: Process.whereis(__MODULE__) != nil

  @impl true
  def candidates(tokens, match) do
    if initialized?() and mode() == :eager do
      Index.candidates(:ets, eager_index_names(), tokens, match)
    else
      nil
    end
  end

  @impl true
  def handle_call({:put_many, places}, _from, state) do
    entries = Enum.map(places, fn place -> {place.id, {place, Query.terms(place)}} end)
    group = Enum.group_by(entries, fn {id, _entry} -> shard(id) end)

    Enum.each(group, fn {index, rows} ->
      :dets.insert(elem(state.table_tuple, index), rows)
    end)

    write_memory(state.mode, entries)
    {:reply, :ok, state}
  end

  def handle_call({:delete, id}, _from, state) do
    :dets.delete(elem(state.table_tuple, shard(id)), id)
    delete_memory(state.mode, id)
    {:reply, :ok, state}
  end

  def handle_call(:reset, _from, state) do
    Enum.each(state.tables, fn {_i, table} -> :dets.delete_all_objects(table) end)
    if :ets.whereis(@eager) != :undefined, do: :ets.delete_all_objects(@eager)
    if :ets.whereis(@eager_index) != :undefined, do: :ets.delete_all_objects(@eager_index)
    if :ets.whereis(@eager_tokens) != :undefined, do: :ets.delete_all_objects(@eager_tokens)

    if :ets.whereis(@eager_trigram_index) != :undefined,
      do: :ets.delete_all_objects(@eager_trigram_index)

    if :ets.whereis(@eager_trigrams) != :undefined, do: :ets.delete_all_objects(@eager_trigrams)

    {:reply, :ok, state}
  end

  defp do_get(id) do
    case mode() do
      :eager -> lookup_eager(id)
      :lazy -> lookup_dets(id)
    end
  end

  defp lookup_eager(id) do
    case :ets.lookup(@eager, id) do
      [{^id, entry}] -> {:ok, decode_row(entry)}
      _ -> :error
    end
  end

  defp lookup_dets(id) do
    case :dets.lookup(table_for(id), id) do
      [{^id, entry}] -> {:ok, decode_row(entry)}
      _ -> :error
    end
  end

  defp write_memory(:eager, entries) do
    :ets.insert(@eager, entries)

    Enum.each(entries, fn {_id, {place, terms}} ->
      Index.put(:ets, eager_index_names(), place, terms)
    end)
  end

  defp write_memory(:lazy, _entries), do: :ok

  defp delete_memory(:eager, id) do
    :ets.delete(@eager, id)
    Index.delete(:ets, eager_index_names(), id)
  end

  defp delete_memory(:lazy, _id), do: :ok

  defp stream_eager do
    @eager
    |> :ets.first()
    |> Stream.unfold(fn
      :"$end_of_table" -> nil
      key -> {key, :ets.next(@eager, key)}
    end)
    |> Stream.map(fn key ->
      case :ets.lookup(@eager, key) do
        [{^key, entry}] -> decode_row(entry)
        _ -> nil
      end
    end)
    |> Stream.reject(&is_nil/1)
  end

  defp stream_dets do
    0..(@shards - 1)
    |> Stream.flat_map(fn i -> stream_table(shard_name(i)) end)
  end

  defp stream_table(table) do
    Stream.resource(
      fn -> :dets.first(table) end,
      fn
        :"$end_of_table" -> {:halt, :done}
        key -> {[entry_at(table, key)], :dets.next(table, key)}
      end,
      fn _ -> :ok end
    )
    |> Stream.reject(&is_nil/1)
  end

  defp entry_at(table, key) do
    case :dets.lookup(table, key) do
      [{^key, entry}] -> decode_row(entry)
      _ -> nil
    end
  end

  defp decode_row({place, terms}), do: {place, terms}
  defp decode_row(place), do: {place, nil}

  defp open_shards(path) do
    for i <- 0..(@shards - 1) do
      name = shard_name(i)
      file = path |> Path.join("places-#{i}.dets") |> String.to_charlist()
      {:ok, ^name} = :dets.open_file(name, file: file, type: :set)
      {i, name}
    end
  end

  defp ensure_eager do
    ensure_table(@eager, [:set, :named_table, :protected, read_concurrency: true])
    ensure_table(@eager_index, [:ordered_set, :named_table, :protected, read_concurrency: true])
    ensure_table(@eager_tokens, [:set, :named_table, :protected, read_concurrency: true])

    ensure_table(@eager_trigram_index, [
      :ordered_set,
      :named_table,
      :protected,
      read_concurrency: true
    ])

    ensure_table(@eager_trigrams, [:set, :named_table, :protected, read_concurrency: true])
  end

  defp ensure_table(name, opts) do
    if :ets.whereis(name) == :undefined, do: :ets.new(name, opts)
  end

  defp load_eager(tables) do
    Enum.each(tables, fn {_i, table} ->
      :dets.foldl(
        fn {id, entry}, _acc ->
          {place, terms} = decode_row(entry)
          :ets.insert(@eager, {id, {place, terms}})
          Index.put(:ets, eager_index_names(), place, terms)
          :ok
        end,
        :ok,
        table
      )
    end)
  end

  defp dets_size(table) do
    case :dets.info(table, :size) do
      size when is_integer(size) -> size
      _ -> 0
    end
  end

  defp mode, do: Application.get_env(:geodata, :memory_mode, :eager)

  defp eager_index_names do
    %{
      index: @eager_index,
      tokens: @eager_tokens,
      trigram_index: @eager_trigram_index,
      trigrams: @eager_trigrams
    }
  end

  defp shard(id), do: :erlang.phash2(id, @shards)

  defp table_for(id), do: shard_name(shard(id))

  defp shard_name(index), do: String.to_atom("geodata_dets_#{index}")
end
