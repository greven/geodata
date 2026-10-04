defmodule GeoData.Exception do
  @moduledoc """
  Conventions shared by GeoData's structured exceptions.

  Exceptions that distinguish between multiple failure categories declare
  `@behaviour GeoData.Exception` and implement `reason_atoms/0`, the closed set
  of atoms permitted in their `:reason` field.

  ## Fields

    * `:reason` holds a documented atom from a closed set. Callers can
      pattern-match on it without parsing the rendered message.

    * Structural fields hold structured values (atoms, paths, structs), not
      free-form sentences. `message/1` is the single place a user-facing
      sentence is assembled.

    * `exception/1` is implemented with `struct!/2` so unknown bindings raise
      rather than being silently discarded.

  """

  @doc """
  Returns the closed set of atoms permitted in this exception's `:reason` field.
  """
  @callback reason_atoms() :: [atom()]
end
