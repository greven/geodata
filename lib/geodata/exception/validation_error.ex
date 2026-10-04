defmodule GeoData.ValidationError do
  @moduledoc """
  Returned by `GeoData.Place.new/1` and raised by its bang variant when the
  given attributes are invalid.

  ## Reasons

    * `:missing` - a required field is absent
    * `:invalid_kind` - a value is not one of the allowed values
    * `:invalid_type` - a value has the wrong type
    * `:invalid_option` - an option value is invalid
    * `:not_a_country` - a place is not an ISO 3166-1 country

  """

  @behaviour GeoData.Exception

  defexception [:field, :value, :expected, :allowed_values, :reason]

  @impl true
  def reason_atoms, do: [:missing, :invalid_kind, :invalid_type, :invalid_option, :not_a_country]

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{reason: :invalid_option, field: field, expected: expected})
      when is_binary(expected) do
    "invalid option #{inspect(field)}: #{expected}"
  end

  def message(%__MODULE__{reason: :invalid_option, field: field}) do
    "invalid option #{inspect(field)}"
  end

  @impl true
  def message(%__MODULE__{reason: :missing, field: field}) do
    "missing required field #{inspect(field)}"
  end

  def message(%__MODULE__{reason: :not_a_country, value: value}) do
    "#{inspect(value)} is not a country"
  end

  def message(%__MODULE__{
        reason: :invalid_kind,
        field: field,
        value: value,
        allowed_values: allowed_values
      }) do
    "invalid value #{inspect(value)} for field #{inspect(field)} " <>
      "(allowed: #{inspect(allowed_values)})"
  end

  def message(%__MODULE__{reason: :invalid_type, field: field, value: value, expected: expected}) do
    "invalid value #{inspect(value)} for field #{inspect(field)} " <>
      "(expected #{inspect(expected)})"
  end

  def message(%__MODULE__{field: field, value: value}) do
    "invalid value #{inspect(value)} for field #{inspect(field)}"
  end
end
