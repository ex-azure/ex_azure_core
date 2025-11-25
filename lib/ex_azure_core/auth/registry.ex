defmodule ExAzureCore.Auth.Registry do
  @moduledoc """
  Registry for naming and storing token servers.

  This registry is used to:
  - Register credential server processes with unique names
  - Store tokens in Registry values for efficient lookup
  - Enable process discovery via name lookup
  """

  @doc """
  Returns a child spec for starting the registry under a supervision tree.
  """
  def child_spec(_opts) do
    Registry.child_spec(
      keys: :unique,
      name: __MODULE__
    )
  end
end
