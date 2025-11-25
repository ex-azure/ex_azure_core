defmodule ExAzureCore.Credentials do
  @moduledoc """
  Azure credential types for authentication.

  Provides credential types matching the Azure Python SDK:

  - `AzureKeyCredential` - Simple API key for Cognitive Services, Search, etc.
  - `AzureSasCredential` - SAS token for Azure Storage
  - `AzureNamedKeyCredential` - Account name + key pair for Storage, Cosmos DB

  ## Usage with HTTP Plugins

      alias ExAzureCore.Credentials

      # API Key for Cognitive Services
      {:ok, key_cred} = Credentials.key_credential("my-api-key")

      Req.new(base_url: "https://myservice.cognitiveservices.azure.com")
      |> ExAzureCore.Http.Plugins.ApiKey.attach(
        api_key: key_cred,
        header_name: "Ocp-Apim-Subscription-Key"
      )

      # SAS for Storage
      {:ok, sas_cred} = Credentials.sas_credential("sv=2021-06-08&ss=b...")

      Req.new(base_url: "https://myaccount.blob.core.windows.net")
      |> ExAzureCore.Http.Plugins.SasToken.attach(sas_token: sas_cred)

      # Named Key for Storage
      {:ok, named_cred} = Credentials.named_key_credential("myaccount", "base64key==")

      Req.new(base_url: "https://myaccount.blob.core.windows.net")
      |> ExAzureCore.Http.Plugins.SharedKey.attach(named_key_credential: named_cred)
  """

  alias ExAzureCore.Credentials.AzureKeyCredential
  alias ExAzureCore.Credentials.AzureNamedKeyCredential
  alias ExAzureCore.Credentials.AzureSasCredential

  @doc """
  Creates a new API key credential.

  ## Example

      {:ok, credential} = ExAzureCore.Credentials.key_credential("my-secret-key")
  """
  @spec key_credential(String.t()) ::
          {:ok, AzureKeyCredential.t()}
          | {:error, ExAzureCore.Credentials.Errors.CredentialError.t()}
  defdelegate key_credential(key), to: AzureKeyCredential, as: :new

  @doc """
  Creates a new SAS credential.

  ## Example

      {:ok, credential} = ExAzureCore.Credentials.sas_credential("sv=2021-06-08&ss=b...")
  """
  @spec sas_credential(String.t()) ::
          {:ok, AzureSasCredential.t()}
          | {:error, ExAzureCore.Credentials.Errors.CredentialError.t()}
  defdelegate sas_credential(signature), to: AzureSasCredential, as: :new

  @doc """
  Creates a new named key credential.

  ## Example

      {:ok, credential} = ExAzureCore.Credentials.named_key_credential("myaccount", "base64key==")
  """
  @spec named_key_credential(String.t(), String.t()) ::
          {:ok, AzureNamedKeyCredential.t()}
          | {:error, ExAzureCore.Credentials.Errors.CredentialError.t()}
  defdelegate named_key_credential(name, key), to: AzureNamedKeyCredential, as: :new
end
