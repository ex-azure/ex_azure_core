defmodule ExAzureCore.Auth.Errors.InvalidTokenFormat do
  use Splode.Error, fields: [:token], class: :invalid

  @type t() :: %__MODULE__{
          token: String.t() | map()
        }

  @impl true
  def message(%{token: token}) do
    "Invalid token format for token #{inspect(token)}"
  end
end
