defmodule ExAzureCore.Auth.Errors.InvalidTokenFormat do
  @moduledoc """
  Error raised when a token has an invalid or unexpected format.
  """
  use Splode.Error, fields: [:token], class: :invalid

  @type t() :: %__MODULE__{
          token: String.t() | map()
        }

  @impl true
  def message(%{token: token}) do
    "Invalid token format for token #{inspect(token)}"
  end
end
