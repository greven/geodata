defmodule GeoData.Storage do
  @moduledoc """
  Storage behaviour and dispatcher for `GeoData.Place` records.

  The adapter is selected with the `:storage` configuration option, defaulting
  to `GeoData.Storage.ETS`:

      config :geodata, storage: GeoData.Storage.ETS

  Adapters store places keyed by their canonical `GeoData.ID`.
  """

  @doc """
  Stores a batch of places, keyed by `GeoData.Place.id`.
  """
  @callback put_many([GeoData.Place.t()]) :: :ok

  @doc """
  Fetches a place by canonical id.
  """
  @callback get(id :: String.t()) :: {:ok, GeoData.Place.t()} | {:error, :not_found}

  @doc """
  Deletes a place by canonical id.
  """
  @callback delete(id :: String.t()) :: :ok

  @doc """
  Returns a lazy stream over every stored place.
  """
  @callback stream() :: Enumerable.t()

  @doc """
  Returns the number of stored places.
  """
  @callback count() :: non_neg_integer()

  @doc """
  Removes every stored place.
  """
  @callback reset() :: :ok

  @doc """
  Returns whether the adapter is initialized.
  """
  @callback initialized?() :: boolean()

  @doc """
  Returns candidate place ids for normalized `tokens`, or `nil` when the
  adapter has no text index.

  Optional. When implemented, `GeoData.Search.Memory` uses it to avoid a full
  scan; `match` is one of `:prefix`, `:token` or `:exact`. The returned ids
  must be a superset of the places that can match, so callers still verify.
  """
  @callback candidates(tokens :: [String.t()], match :: atom()) :: [String.t()] | nil

  @doc """
  Fetches a place together with its precomputed, normalized search terms.

  Optional. Adapters that maintain a search index return `{:ok, place, terms}`
  where `terms` is the map built by `GeoData.Search.Query.terms/1`; adapters
  without one return `nil` terms and callers normalize on the fly.
  """
  @callback get_with_terms(id :: String.t()) ::
              {:ok, GeoData.Place.t(), map() | nil} | {:error, :not_found}

  @doc """
  Returns a lazy stream over `{place, terms}` pairs.

  Optional. See `get_with_terms/1`; falls back to `stream/0` with `nil` terms.
  """
  @callback stream_with_terms() :: Enumerable.t()

  @optional_callbacks candidates: 2, get_with_terms: 1, stream_with_terms: 0

  @storage_mod Application.compile_env(:geodata, :storage, GeoData.Storage.ETS)

  @doc """
  Returns the configured storage adapter module.
  """
  def storage_mod, do: @storage_mod

  def put_many(places), do: storage_mod().put_many(places)
  def get(id), do: storage_mod().get(id)
  def delete(id), do: storage_mod().delete(id)
  def stream, do: storage_mod().stream()
  def count, do: storage_mod().count()
  def reset, do: storage_mod().reset()
  def initialized?, do: storage_mod().initialized?()

  @doc """
  Dispatches to the adapter's text index, when it has one.
  """
  def candidates(tokens, match) do
    mod = storage_mod()

    if function_exported?(mod, :candidates, 2),
      do: :erlang.apply(mod, :candidates, [tokens, match]),
      else: nil
  end

  @doc """
  Fetches a place and its normalized terms, falling back to `get/1`.
  """
  def get_with_terms(id) do
    mod = storage_mod()

    if function_exported?(mod, :get_with_terms, 1) do
      :erlang.apply(mod, :get_with_terms, [id])
    else
      case mod.get(id) do
        {:ok, place} -> {:ok, place, nil}
        error -> error
      end
    end
  end

  @doc """
  Streams `{place, terms}` pairs, falling back to `stream/0`.
  """
  def stream_with_terms do
    mod = storage_mod()

    if function_exported?(mod, :stream_with_terms, 0) do
      :erlang.apply(mod, :stream_with_terms, [])
    else
      Stream.map(mod.stream(), &{&1, nil})
    end
  end
end
