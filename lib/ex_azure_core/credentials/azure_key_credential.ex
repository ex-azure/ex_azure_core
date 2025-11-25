defmodule ExAzureCore.Credentials.AzureKeyCredential do
  @moduledoc """
  Credential type for API key authentication.

  Stores a single API key that can be used with services requiring
  `api-key`, `Ocp-Apim-Subscription-Key`, or similar header-based authentication.

  ## Example

      {:ok, credential} = AzureKeyCredential.new("my-secret-key")
      credential.key
      #=> "my-secret-key"

      # Update returns a new credential (immutable)
      {:ok, updated} = AzureKeyCredential.update(credential, "new-key")
  """

  alias ExAzureCore.Credentials.Errors.CredentialError

  @enforce_keys [:key]
  defstruct [:key]

  @type t :: %__MODULE__{key: String.t()}

  @doc """
  Creates a new key credential.

  Returns `{:ok, credential}` if the key is a non-empty string,
  or `{:error, CredentialError}` otherwise.
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, CredentialError.t()}
  def new(key) when is_binary(key) and byte_size(key) > 0 do
    {:ok, %__MODULE__{key: key}}
  end

  def new(_) do
    {:error, CredentialError.exception(type: :invalid_key)}
  end

  @doc """
  Creates a new key credential, raising on invalid input.
  """
  @spec new!(String.t()) :: t()
  def new!(key) do
    case new(key) do
      {:ok, credential} -> credential
      {:error, error} -> raise error
    end
  end

  @doc """
  Updates the key value, returning a new credential.

  This is immutable - returns a new struct rather than modifying in-place.
  """
  @spec update(t(), String.t()) :: {:ok, t()} | {:error, CredentialError.t()}
  def update(%__MODULE__{}, new_key), do: new(new_key)
end
