defmodule ExAzureCore.Credentials.AzureSasCredential do
  @moduledoc """
  Credential type for Shared Access Signature (SAS) authentication.

  Stores a SAS token that can be used with Azure Storage services.
  The signature is automatically normalized (leading "?" is stripped).

  ## Example

      {:ok, credential} = AzureSasCredential.new("sv=2021-06-08&ss=b&srt=sco...")
      credential.signature
      #=> "sv=2021-06-08&ss=b&srt=sco..."

      # Leading "?" is stripped automatically
      {:ok, credential} = AzureSasCredential.new("?sv=2021-06-08&ss=b...")
      credential.signature
      #=> "sv=2021-06-08&ss=b..."
  """

  alias ExAzureCore.Credentials.Errors.CredentialError

  @enforce_keys [:signature]
  defstruct [:signature]

  @type t :: %__MODULE__{signature: String.t()}

  @doc """
  Creates a new SAS credential.

  Returns `{:ok, credential}` if the signature is a non-empty string,
  or `{:error, CredentialError}` otherwise.

  The signature is normalized by stripping any leading "?" character.
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, CredentialError.t()}
  def new(signature) when is_binary(signature) do
    normalized = normalize_signature(signature)

    if byte_size(normalized) > 0 do
      {:ok, %__MODULE__{signature: normalized}}
    else
      {:error, CredentialError.exception(type: :invalid_signature)}
    end
  end

  def new(_) do
    {:error, CredentialError.exception(type: :invalid_signature)}
  end

  @doc """
  Creates a new SAS credential, raising on invalid input.
  """
  @spec new!(String.t()) :: t()
  def new!(signature) do
    case new(signature) do
      {:ok, credential} -> credential
      {:error, error} -> raise error
    end
  end

  @doc """
  Updates the signature value, returning a new credential.

  This is immutable - returns a new struct rather than modifying in-place.
  """
  @spec update(t(), String.t()) :: {:ok, t()} | {:error, CredentialError.t()}
  def update(%__MODULE__{}, new_signature), do: new(new_signature)

  defp normalize_signature(signature) do
    signature
    |> String.trim_leading("?")
    |> String.trim()
  end
end
