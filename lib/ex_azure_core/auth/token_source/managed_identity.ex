defmodule ExAzureCore.Auth.TokenSource.ManagedIdentity do
  @moduledoc """
  Managed Identity token source for Azure workloads.

  Fetches tokens directly from Azure identity endpoints for workloads running
  in Azure VMs, App Service, Functions, Container Instances, etc.

  This source supports automatic environment detection or explicit provider selection.

  ## Configuration

    * `:resource` (required) - The Azure resource URI (e.g., "https://management.azure.com/")
    * `:client_id` (optional) - Client ID for user-assigned managed identity
    * `:provider` (optional) - Force specific provider: `:auto`, `:imds`, `:app_service` (default: `:auto`)

  ## Examples

      # System-assigned identity with auto-detection
      config = %{resource: "https://management.azure.com/"}

      # User-assigned identity
      config = %{
        resource: "https://vault.azure.net/",
        client_id: "user-assigned-client-id"
      }

      # Force IMDS provider
      config = %{
        resource: "https://storage.azure.com/",
        provider: :imds
      }

  ## Environment Detection

  When `:provider` is `:auto` (default), the source detects the environment:

  1. App Service - if `IDENTITY_ENDPOINT` and `IDENTITY_HEADER` are set
  2. IMDS - probes the IMDS endpoint at 169.254.169.254

  For AKS Workload Identity (federated tokens), use `TokenSource.WorkloadIdentity` instead.
  """

  @behaviour ExAzureCore.Auth.TokenSource

  alias ExAzureCore.Auth.Errors.ManagedIdentityError
  alias ExAzureCore.Auth.ManagedIdentity.AppServiceProvider
  alias ExAzureCore.Auth.ManagedIdentity.EnvironmentDetector
  alias ExAzureCore.Auth.ManagedIdentity.ImdsProvider

  @impl true
  def fetch_token(config) when is_map(config) do
    provider = Map.get(config, :provider, :auto)
    fetch_with_provider(provider, config)
  end

  defp fetch_with_provider(:auto, config) do
    case detect_provider() do
      :app_service ->
        AppServiceProvider.fetch_token(config)

      :imds ->
        ImdsProvider.fetch_token(config)

      :workload_identity ->
        {:error,
         ManagedIdentityError.exception(
           type: :provider_error,
           provider: :managed_identity,
           reason:
             "Workload Identity detected but requires TokenSource.WorkloadIdentity, not ManagedIdentity"
         )}
    end
  end

  defp fetch_with_provider(:imds, config) do
    ImdsProvider.fetch_token(config)
  end

  defp fetch_with_provider(:app_service, config) do
    AppServiceProvider.fetch_token(config)
  end

  defp fetch_with_provider(unknown, _config) do
    {:error,
     ManagedIdentityError.exception(
       type: :provider_error,
       provider: :managed_identity,
       reason: "unknown provider: #{inspect(unknown)}"
     )}
  end

  defp detect_provider do
    cond do
      EnvironmentDetector.app_service_available?() ->
        :app_service

      EnvironmentDetector.workload_identity_available?() ->
        :workload_identity

      true ->
        :imds
    end
  end
end
