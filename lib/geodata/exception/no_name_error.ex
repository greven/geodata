defmodule GeoData.NoNameError do
  @moduledoc """
  Returned by `GeoData.Place.display_name/3` and raised by
  `GeoData.Place.display_name!/3` when no name can be resolved for a place in
  the requested locale.

  ## Reasons

    * `:not_found` - no stored name, CLDR name or canonical name was available

  """

  @behaviour GeoData.Exception

  defexception [:place, :locale, reason: :not_found]

  @impl true
  def reason_atoms, do: [:not_found]

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{place: place, locale: locale}) do
    "no name available for place #{inspect(place_id(place))} in locale #{inspect(locale)}"
  end

  defp place_id(%{id: id}) when is_binary(id), do: id
  defp place_id(_place), do: nil
end
