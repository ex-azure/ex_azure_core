defmodule ExAzureCore.Auth.ManagedIdentity.EnvironmentDetector do
  @moduledoc """
  Detects the Azure environment for managed identity authentication.

  Detection order:
  1. AKS Workload Identity (AZURE_FEDERATED_TOKEN_FILE + AZURE_CLIENT_ID)
  2. App Service (IDENTITY_ENDPOINT + IDENTITY_HEADER)
  3. IMDS probe (169.254.169.254 reachable)
  """

  alias ExAzureCore.Auth.Errors.ManagedIdentityError

  @imds_endpoint "http://169.254.169.254"
  @imds_probe_timeout 1000

  @type environment :: :workload_identity | :app_service | :imds
  @type detection_result :: {:ok, environment()} | {:error, ManagedIdentityError.t()}

  @doc """
  Detects the current Azure environment.

  Returns the detected environment type or an error if no Azure environment is detected.

  ## Options

    * `:probe_timeout` - Timeout in ms for IMDS probe (default: 1000)
    * `:skip_imds_probe` - Skip IMDS network probe, useful for testing (default: false)
  """
  @spec detect(keyword()) :: detection_result()
  def detect(opts \\ []) do
    cond do
      workload_identity_available?() ->
        {:ok, :workload_identity}

      app_service_available?() ->
        {:ok, :app_service}

      imds_available?(opts) ->
        {:ok, :imds}

      true ->
        {:error, ManagedIdentityError.exception(type: :environment_not_detected, provider: nil)}
    end
  end

  @doc """
  Checks if AKS Workload Identity environment is available.

  Requires both AZURE_FEDERATED_TOKEN_FILE and AZURE_CLIENT_ID environment variables.
  """
  @spec workload_identity_available?() :: boolean()
  def workload_identity_available? do
    token_file = System.get_env("AZURE_FEDERATED_TOKEN_FILE")
    client_id = System.get_env("AZURE_CLIENT_ID")

    not is_nil(token_file) and not is_nil(client_id) and File.exists?(token_file)
  end

  @doc """
  Checks if App Service environment is available.

  Requires both IDENTITY_ENDPOINT and IDENTITY_HEADER environment variables.
  """
  @spec app_service_available?() :: boolean()
  def app_service_available? do
    endpoint = System.get_env("IDENTITY_ENDPOINT")
    header = System.get_env("IDENTITY_HEADER")

    not is_nil(endpoint) and not is_nil(header)
  end

  @doc """
  Checks if IMDS endpoint is reachable.

  Makes a lightweight probe request to the IMDS endpoint.
  """
  @spec imds_available?(keyword()) :: boolean()
  def imds_available?(opts \\ []) do
    if Keyword.get(opts, :skip_imds_probe, false) do
      false
    else
      probe_imds(opts)
    end
  end

  defp probe_imds(opts) do
    timeout = Keyword.get(opts, :probe_timeout, @imds_probe_timeout)

    case Req.get("#{@imds_endpoint}/metadata/instance",
           headers: [{"Metadata", "true"}],
           params: [{"api-version", "2021-02-01"}],
           receive_timeout: timeout,
           retry: false
         ) do
      {:ok, %{status: status}} when status in 200..499 ->
        true

      _ ->
        false
    end
  end

  @doc """
  Returns environment variables for the detected environment.

  Useful for debugging and logging.
  """
  @spec get_environment_info() :: map()
  def get_environment_info do
    %{
      azure_federated_token_file: System.get_env("AZURE_FEDERATED_TOKEN_FILE"),
      azure_client_id: System.get_env("AZURE_CLIENT_ID"),
      azure_tenant_id: System.get_env("AZURE_TENANT_ID"),
      azure_authority_host: System.get_env("AZURE_AUTHORITY_HOST"),
      identity_endpoint: System.get_env("IDENTITY_ENDPOINT"),
      identity_header: redact_if_present(System.get_env("IDENTITY_HEADER"))
    }
  end

  defp redact_if_present(nil), do: nil
  defp redact_if_present(_value), do: "[REDACTED]"
end
