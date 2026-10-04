defmodule GeoData.NotFoundError do
  @moduledoc """
  Returned by `GeoData.fetch/1` and raised by `GeoData.fetch!/1` when no place
  exists for the given canonical id.

  ## Reasons

    * `:not_found` - no place is stored under the given id

  """

  @behaviour GeoData.Exception

  defexception [:id, reason: :not_found]

  @impl true
  def reason_atoms, do: [:not_found]

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{id: id}) do
    "no place found for id #{inspect(id)}"
  end
end
