defmodule GeoData.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = storage_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: GeoData.Supervisor)
  end

  defp storage_children do
    module = GeoData.Storage.storage_mod()

    if Code.ensure_loaded?(module) and function_exported?(module, :start_link, 1) do
      [{module, []}]
    else
      []
    end
  end
end
