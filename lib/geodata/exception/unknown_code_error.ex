defmodule GeoData.UnknownCodeError do
  @moduledoc """
  Returned by `GeoData.Currency.get/2` and `GeoData.Language.get/2`, and raised
  by their bang variants, when no currency or language exists for the given
  code.

  ## Reasons

    * `:unknown_code` - no currency or language is known for the given code

  """

  @behaviour GeoData.Exception

  defexception [:field, :value, reason: :unknown_code]

  @impl true
  def reason_atoms, do: [:unknown_code]

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{field: :currency, value: value}) do
    "unknown currency code #{inspect(value)}"
  end

  def message(%__MODULE__{field: :language, value: value}) do
    "unknown language code #{inspect(value)}"
  end

  def message(%__MODULE__{field: field, value: value}) do
    "unknown #{field} code #{inspect(value)}"
  end
end
