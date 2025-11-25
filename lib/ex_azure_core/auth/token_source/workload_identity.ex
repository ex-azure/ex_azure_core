defmodule ExAzureCore.Auth.TokenSource.WorkloadIdentity do
  @moduledoc """
  Workload Identity token source for AKS (Azure Kubernetes Service).

  Fetches tokens using the AKS Workload Identity flow, which reads a projected
  service account token from disk and exchanges it for an Azure AD access token.

  ## How It Works

  1. Kubernetes projects a service account token to a file in the pod
  2. This source reads the JWT from that file
  3. Exchanges it with Azure AD using the OAuth2 federated credential flow
  4. Returns an Azure AD access token

  ## Environment Variables

  AKS automatically sets these environment variables when Workload Identity is enabled:

    * `AZURE_FEDERATED_TOKEN_FILE` - Path to the projected service account token
    * `AZURE_CLIENT_ID` - Client ID of the Azure AD application or managed identity
    * `AZURE_TENANT_ID` - Azure AD tenant ID
    * `AZURE_AUTHORITY_HOST` - (optional) Authority host URL

  ## Configuration

  Configuration can be provided explicitly or read from environment variables:

    * `:scope` (required) - Token scope (e.g., "https://management.azure.com/.default")
    * `:tenant_id` (optional) - Azure AD tenant ID (defaults to AZURE_TENANT_ID)
    * `:client_id` (optional) - Client ID (defaults to AZURE_CLIENT_ID)
    * `:token_file_path` (optional) - Token file path (defaults to AZURE_FEDERATED_TOKEN_FILE)
    * `:cloud` (optional) - Azure cloud: `:public`, `:government`, `:china`, `:germany`

  ## Examples

      # Auto-detect from environment variables
      config = %{scope: "https://management.azure.com/.default"}

      # Explicit configuration
      config = %{
        scope: "https://vault.azure.net/.default",
        tenant_id: "my-tenant-id",
        client_id: "my-client-id",
        token_file_path: "/var/run/secrets/azure/tokens/azure-identity-token"
      }
  """

  @behaviour ExAzureCore.Auth.TokenSource

  alias ExAzureCore.Auth.Errors.ManagedIdentityError
  alias ExAzureCore.Auth.OAuth2

  @impl true
  def fetch_token(config) when is_map(config) do
    with {:ok, scope} <- get_config_value(config, :scope, nil, required: true),
         {:ok, tenant_id} <- get_config_value(config, :tenant_id, "AZURE_TENANT_ID"),
         {:ok, client_id} <- get_config_value(config, :client_id, "AZURE_CLIENT_ID"),
         {:ok, token_file} <-
           get_config_value(config, :token_file_path, "AZURE_FEDERATED_TOKEN_FILE"),
         {:ok, assertion} <- read_token_file(token_file) do
      cloud = Map.get(config, :cloud, :public)
      OAuth2.get_token(tenant_id, client_id, assertion, scope, cloud)
    end
  end

  defp get_config_value(config, key, env_var, opts \\ []) do
    required = Keyword.get(opts, :required, false)

    value =
      case Map.fetch(config, key) do
        {:ok, v} when is_binary(v) and v != "" -> v
        _ when is_binary(env_var) -> System.get_env(env_var)
        _ -> nil
      end

    case {value, required} do
      {nil, true} ->
        {:error,
         ManagedIdentityError.exception(
           type: :provider_error,
           provider: :workload_identity,
           reason: "missing required field: #{key}"
         )}

      {nil, false} ->
        {:error,
         ManagedIdentityError.exception(
           type: :provider_error,
           provider: :workload_identity,
           reason: "#{key} not provided and #{env_var} environment variable not set"
         )}

      {"", _} ->
        {:error,
         ManagedIdentityError.exception(
           type: :provider_error,
           provider: :workload_identity,
           reason: "#{key} cannot be empty"
         )}

      {v, _} ->
        {:ok, v}
    end
  end

  defp read_token_file(path) do
    case File.read(path) do
      {:ok, content} ->
        token = String.trim(content)

        if token == "" do
          {:error,
           ManagedIdentityError.exception(
             type: :token_file_read_error,
             provider: :workload_identity,
             reason: "token file is empty"
           )}
        else
          {:ok, token}
        end

      {:error, :enoent} ->
        {:error,
         ManagedIdentityError.exception(
           type: :token_file_not_found,
           provider: :workload_identity,
           reason: path
         )}

      {:error, reason} ->
        {:error,
         ManagedIdentityError.exception(
           type: :token_file_read_error,
           provider: :workload_identity,
           reason: reason
         )}
    end
  end
end
