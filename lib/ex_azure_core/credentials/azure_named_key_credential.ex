defmodule ExAzureCore.Credentials.AzureNamedKeyCredential do
  @moduledoc """
  Credential type for named key authentication.

  Stores both an account name and account key, used with services like
  Azure Storage and Cosmos DB that require both values for authentication.

  ## Example

      {:ok, credential} = AzureNamedKeyCredential.new("myaccount", "base64key==")
      credential.name
      #=> "myaccount"
      credential.key
      #=> "base64key=="

      # Update returns a new credential (immutable)
      {:ok, updated} = AzureNamedKeyCredential.update(credential, "newaccount", "newkey==")
  """

  alias ExAzureCore.Credentials.Errors.CredentialError

  @enforce_keys [:name, :key]
  defstruct [:name, :key]

  @type t :: %__MODULE__{name: String.t(), key: String.t()}

  @doc """
  Creates a new named key credential.

  Returns `{:ok, credential}` if both name and key are non-empty strings,
  or `{:error, CredentialError}` otherwise.
  """
  @spec new(String.t(), String.t()) :: {:ok, t()} | {:error, CredentialError.t()}
  def new(name, key)
      when is_binary(name) and byte_size(name) > 0 and
             is_binary(key) and byte_size(key) > 0 do
    {:ok, %__MODULE__{name: name, key: key}}
  end

  def new(_, _) do
    {:error, CredentialError.exception(type: :invalid_named_key)}
  end

  @doc """
  Creates a new named key credential, raising on invalid input.
  """
  @spec new!(String.t(), String.t()) :: t()
  def new!(name, key) do
    case new(name, key) do
      {:ok, credential} -> credential
      {:error, error} -> raise error
    end
  end

  @doc """
  Updates both name and key values, returning a new credential.

  This is immutable - returns a new struct rather than modifying in-place.
  Both values must be provided together (atomic update).
  """
  @spec update(t(), String.t(), String.t()) :: {:ok, t()} | {:error, CredentialError.t()}
  def update(%__MODULE__{}, new_name, new_key), do: new(new_name, new_key)

  @doc """
  Returns the named key as a tuple `{name, key}`.

  Useful for pattern matching or passing to functions that expect a tuple.
  """
  @spec named_key(t()) :: {String.t(), String.t()}
  def named_key(%__MODULE__{name: name, key: key}), do: {name, key}
end
