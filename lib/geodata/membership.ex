defmodule GeoData.Membership do
  @moduledoc """
  Country memberships in unions and geographic groupings.

  Membership data comes from the CLDR territory containment graph via
  `Localize.Territory`. It covers political unions such as the European Union
  (`:EU`), the Eurozone (`:EZ`) and the United Nations (`:UN`), as well as the
  UN M49 macro-regions and subregions (e.g. `:"150"` Europe, `:"039"` Southern
  Europe).

  Groupings that are not part of CLDR are not covered, such as the European
  Economic Area, the Schengen Area, NATO or the Commonwealth.

  ## Examples

      iex> GeoData.Membership.member_of?(:PT, :EU)
      true

      iex> GeoData.Membership.member_of?(:NO, :EU)
      false

      iex> {:ok, groups} = GeoData.Membership.groups(:PT)
      iex> :EU in groups
      true

  """

  alias Localize.Territory

  @doc """
  Returns the immediate groups a territory belongs to.

  Returns `{:ok, groups}` or `{:error, exception}` when the territory is
  unknown.
  """
  def groups(territory), do: Territory.parent(territory)

  @doc """
  Same as `groups/1` but raises on error.
  """
  def groups!(territory), do: Territory.parent!(territory)

  @doc """
  Checks whether `territory` belongs to `group`.

  Returns `false` when either the territory or the group is unknown.
  """
  def member_of?(territory, group), do: Territory.contains?(group, territory)

  @doc """
  Returns the localized display name of a group.

  ## Options

    * `:locale` - the locale to render the name in, defaults to the current
      locale
    * `:style` - one of `:standard`, `:short` or `:variant`

  """
  def group_name(group, opts \\ []), do: Territory.display_name(group, opts)
end
