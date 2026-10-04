defmodule GeoData.Storage.ETS do
  @moduledoc """
  ETS-backed `GeoData.Storage` adapter.

  A `:protected`, named ETS table is owned by the storage GenServer.
  Reads go directly to ETS from any process while writes are routed through
  the owner so the table has a single writer.

  The adapter also maintains derived search data outside `GeoData.Place`: a
  text index (built with `GeoData.Storage.Index`) served through
  `candidates/2`, and the normalized search terms returned by
  `get_with_terms/1` and `stream_with_terms/0`, so `GeoData.Search.Memory`
  never normalizes per query for performance reasons.
  """

  @behaviour GeoData.Storage

  use GenServer

  alias GeoData.Search.Query
  alias GeoData.Storage.Index

  @table :geodata_places
  @index :geodata_places_index
  @tokens :geodata_places_tokens
  @terms :geodata_places_terms
  @trigram_index :geodata_places_trigram_index
  @trigrams :geodata_places_trigrams

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    ensure_table()
    {:ok, %{}}
  end

  @impl true
  def put_many(places) when is_list(places) do
    GenServer.call(__MODULE__, {:put_many, places})
  end

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
         [{^id, place}] <- :ets.lookup(@table, id) do
      {:ok, place, terms_at(id)}
    else
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def delete(id) do
    GenServer.call(__MODULE__, {:delete, id})
  end

  @impl true
  def stream do
    Stream.map(stream_with_terms(), &elem(&1, 0))
  end

  @impl true
  def stream_with_terms do
    if initialized?() do
      @table
      |> :ets.first()
      |> Stream.unfold(fn
        :"$end_of_table" -> nil
        key -> {key, :ets.next(@table, key)}
      end)
      |> Stream.map(&entry_at/1)
      |> Stream.reject(&is_nil/1)
    else
      []
    end
  end

  @impl true
  def count do
    if initialized?(), do: :ets.info(@table, :size), else: 0
  end

  @impl true
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def initialized? do
    :ets.whereis(@table) != :undefined
  end

  @impl true
  def candidates([], _match), do: []

  def candidates(tokens, match) do
    if initialized?(), do: Index.candidates(:ets, index_names(), tokens, match), else: []
  end

  @impl true
  def handle_call({:put_many, places}, _from, state) do
    Enum.each(places, &index_put/1)
    :ets.insert(@table, Enum.map(places, fn place -> {place.id, place} end))
    {:reply, :ok, state}
  end

  def handle_call({:delete, id}, _from, state) do
    deindex(id)
    :ets.delete(@table, id)
    {:reply, :ok, state}
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    :ets.delete_all_objects(@index)
    :ets.delete_all_objects(@tokens)
    :ets.delete_all_objects(@terms)
    :ets.delete_all_objects(@trigram_index)
    :ets.delete_all_objects(@trigrams)
    {:reply, :ok, state}
  end

  # Index maintenance

  defp index_put(place) do
    terms = Query.terms(place)
    :ets.insert(@terms, {place.id, terms})
    Index.put(:ets, index_names(), place, terms)
  end

  defp deindex(id) do
    Index.delete(:ets, index_names(), id)
    :ets.delete(@terms, id)
  end

  defp index_names do
    %{
      index: @index,
      tokens: @tokens,
      trigram_index: @trigram_index,
      trigrams: @trigrams
    }
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    end

    if :ets.whereis(@index) == :undefined do
      :ets.new(@index, [:ordered_set, :protected, :named_table, read_concurrency: true])
    end

    if :ets.whereis(@tokens) == :undefined do
      :ets.new(@tokens, [:set, :protected, :named_table, read_concurrency: true])
    end

    if :ets.whereis(@terms) == :undefined do
      :ets.new(@terms, [:set, :protected, :named_table, read_concurrency: true])
    end

    if :ets.whereis(@trigram_index) == :undefined do
      :ets.new(@trigram_index, [:ordered_set, :protected, :named_table, read_concurrency: true])
    end

    if :ets.whereis(@trigrams) == :undefined do
      :ets.new(@trigrams, [:set, :protected, :named_table, read_concurrency: true])
    end
  end

  defp terms_at(id) do
    case :ets.lookup(@terms, id) do
      [{^id, terms}] -> terms
      _ -> nil
    end
  end

  defp entry_at(key) do
    case :ets.lookup(@table, key) do
      [{^key, place}] -> {place, terms_at(key)}
      _ -> nil
    end
  end
end
