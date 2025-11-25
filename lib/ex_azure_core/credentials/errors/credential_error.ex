defmodule ExAzureCore.Credentials.Errors.CredentialError do
  @moduledoc """
  Error for credential validation failures.

  Used when credential values are invalid, empty, or of wrong type.
  """
  use Splode.Error, fields: [:type], class: :invalid

  @type t() :: %__MODULE__{
          type: :invalid_key | :invalid_signature | :invalid_named_key
        }

  @impl true
  def message(%{type: :invalid_key}) do
    "Invalid API key: must be a non-empty string"
  end

  def message(%{type: :invalid_signature}) do
    "Invalid SAS signature: must be a non-empty string"
  end

  def message(%{type: :invalid_named_key}) do
    "Invalid named key: name and key must be non-empty strings"
  end
end
