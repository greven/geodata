defmodule GeoData.Search do
  @moduledoc """
  Search and filtering over stored places.

  Search is delegated to a search engine, selected with the `:search`
  configuration option (or per call):

      config :geodata, search: GeoData.Search.Memory

  The default `GeoData.Search.Memory` engine streams the dataset through
  `GeoData.Storage.stream/0` and applies matching, filtering and ordering in
  memory, so it works with every storage adapter. An Ecto-backed engine can be
  plugged in for server-side queries.

  ## Examples

      GeoData.search("lisbon")
      GeoData.search("sao", where: [kind: [:city]], order_by: {:population, :desc})
      GeoData.search(where: [kind: [:country], continent: "EU"], order_by: :name)

  """

  alias GeoData.Search.Result

  @doc """
  Runs a search and returns `{:ok, result}` or `{:error, exception}`.
  """
  @callback search(text :: String.t() | nil, opts :: keyword()) ::
              {:ok, Result.t()} | {:error, Exception.t()}

  @doc """
  Streams matching places lazily, in storage order.

  Paging and ordering do not apply; use `search/2` for a ranked page.
  """
  @callback stream(text :: String.t() | nil, opts :: keyword()) :: Enumerable.t()

  @doc """
  Returns the configured search engine.
  """
  def search_mod, do: Application.get_env(:geodata, :search, GeoData.Search.Memory)

  @doc """
  Searches stored places.

  See `GeoData.Search.Memory` for the supported options. The text argument is
  optional, so a keyword list of options may be passed on its own.

  ## Examples

      GeoData.Search.search("lisbon")
      GeoData.Search.search(where: [kind: [:country]], order_by: :name)

  """
  def search(text \\ nil, opts \\ [])

  def search(text, opts) when is_binary(text) or is_nil(text) do
    {mod, opts} = adapter(opts)
    mod.search(text, opts)
  end

  def search(opts, extra) when is_list(opts) do
    search(nil, Keyword.merge(opts, extra))
  end

  @doc """
  Same as `search/2` but returns the result directly or raises.
  """
  def search!(text \\ nil, opts \\ [])

  def search!(text, opts) when is_binary(text) or is_nil(text) do
    case search(text, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def search!(opts, extra) when is_list(opts) do
    search!(nil, Keyword.merge(opts, extra))
  end

  @doc """
  Streams matching places lazily.
  """
  def stream(text \\ nil, opts \\ [])

  def stream(text, opts) when is_binary(text) or is_nil(text) do
    {mod, opts} = adapter(opts)
    mod.stream(text, opts)
  end

  def stream(opts, extra) when is_list(opts) do
    stream(nil, Keyword.merge(opts, extra))
  end

  defp adapter(opts) do
    {mod, opts} = Keyword.pop(opts, :search, search_mod())
    {mod, opts}
  end
end
