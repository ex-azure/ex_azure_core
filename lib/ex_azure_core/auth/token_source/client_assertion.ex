defmodule ExAzureCore.Auth.TokenSource.ClientAssertion do
  @moduledoc """
  Client assertion token source using Workload Identity Federation.

  This source exchanges external identity tokens (from AWS Cognito, GitHub Actions,
  Kubernetes, etc.) for Azure AD access tokens using the OAuth2 client credentials
  flow with JWT bearer token assertion.

  ## Configuration

  The configuration map must include:

    * `:tenant_id` (required) - Azure AD tenant ID
    * `:client_id` (required) - Azure AD application (client) ID
    * `:scope` (required) - Token scope (e.g., "https://graph.microsoft.com/.default")
    * `:provider` (required) - Federated token provider (:aws_cognito, etc.)
    * `:provider_opts` (optional) - Provider-specific options
    * `:cloud` (optional) - Azure cloud environment (:public, :government, :china, :germany)

  ## Examples

      config = %{
        tenant_id: "12345678-1234-1234-1234-123456789012",
        client_id: "87654321-4321-4321-4321-210987654321",
        scope: "https://graph.microsoft.com/.default",
        provider: :aws_cognito,
        provider_opts: [
          identity_id: "us-west-2:12345678-1234-1234-1234-123456789012",
          auth_type: :basic
        ],
        cloud: :public
      }

      {:ok, token} = ExAzureIdentity.Sources.ClientAssertion.fetch_token(config)
  """

  @behaviour ExAzureCore.Auth.TokenSource

  alias ExAzureCore.Auth.Errors.ConfigurationError
  alias ExAzureCore.Auth.FederatedTokenProvider
  alias ExAzureCore.Auth.OAuth2

  @impl true
  def fetch_token(config) when is_map(config) do
    with {:ok, tenant_id} <- fetch_required(config, :tenant_id),
         {:ok, client_id} <- fetch_required(config, :client_id),
         {:ok, scope} <- fetch_required(config, :scope),
         {:ok, provider} <- fetch_required(config, :provider),
         {:ok, assertion} <- get_federated_token(provider, config),
         {:ok, token} <- exchange_token(tenant_id, client_id, assertion, scope, config) do
      {:ok, token}
    end
  end

  defp fetch_required(config, key) do
    case Map.fetch(config, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        {:error, ConfigurationError.exception(type: :missing_required, key: key, value: nil)}
    end
  end

  defp get_federated_token(provider, config) do
    provider_opts = Map.get(config, :provider_opts, [])
    FederatedTokenProvider.get_token(provider, provider_opts)
  end

  defp exchange_token(tenant_id, client_id, assertion, scope, config) do
    cloud = Map.get(config, :cloud, :public)
    OAuth2.get_token(tenant_id, client_id, assertion, scope, cloud)
  end
end
