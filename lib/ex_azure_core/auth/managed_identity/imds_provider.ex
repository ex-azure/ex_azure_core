defmodule ExAzureCore.Auth.ManagedIdentity.ImdsProvider do
  @moduledoc """
  IMDS (Instance Metadata Service) provider for Azure Managed Identity.

  Fetches tokens from the Azure IMDS endpoint for VMs, AKS pods (legacy pod identity),
  Container Instances, and other Azure compute resources.

  ## IMDS Details

  Endpoint: `http://169.254.169.254/metadata/identity/oauth2/token`
  Required headers: `Metadata: true`
  API Version: `2019-08-01`
  """

  alias ExAzureCore.Auth.Errors.ManagedIdentityError
  alias ExAzureCore.Errors.NetworkError

  @imds_endpoint "http://169.254.169.254/metadata/identity/oauth2/token"
  @api_version "2019-08-01"
  @default_timeout 5_000
  @max_retries 5
  @initial_retry_delay 500
  @max_retry_delay 5_000

  @type config :: %{
          required(:resource) => String.t(),
          optional(:client_id) => String.t(),
          optional(:object_id) => String.t(),
          optional(:mi_res_id) => String.t(),
          optional(:timeout) => non_neg_integer()
        }

  @doc """
  Fetches an access token from Azure IMDS.

  ## Configuration

    * `:resource` (required) - The Azure resource URI (e.g., "https://management.azure.com/")
    * `:client_id` (optional) - Client ID for user-assigned managed identity
    * `:object_id` (optional) - Object ID for user-assigned managed identity
    * `:mi_res_id` (optional) - Resource ID for user-assigned managed identity
    * `:timeout` (optional) - Request timeout in milliseconds (default: 5000)

  ## Examples

      # System-assigned identity
      {:ok, token} = ImdsProvider.fetch_token(%{resource: "https://management.azure.com/"})

      # User-assigned identity
      {:ok, token} = ImdsProvider.fetch_token(%{
        resource: "https://vault.azure.net/",
        client_id: "user-assigned-client-id"
      })
  """
  @spec fetch_token(config()) :: {:ok, map()} | {:error, term()}
  def fetch_token(config) when is_map(config) do
    with {:ok, resource} <- fetch_required(config, :resource) do
      url = build_url(resource, config)
      timeout = Map.get(config, :timeout, @default_timeout)
      request_with_retry(url, timeout, 0)
    end
  end

  defp fetch_required(config, key) do
    case Map.fetch(config, key) do
      {:ok, value} when is_binary(value) and value != "" ->
        {:ok, value}

      {:ok, _} ->
        {:error,
         ManagedIdentityError.exception(
           type: :provider_error,
           provider: :imds,
           reason: "#{key} cannot be empty"
         )}

      :error ->
        {:error,
         ManagedIdentityError.exception(
           type: :provider_error,
           provider: :imds,
           reason: "missing required field: #{key}"
         )}
    end
  end

  defp build_url(resource, config) do
    params =
      [
        {"api-version", @api_version},
        {"resource", resource}
      ]
      |> maybe_add_identity_param(config)
      |> URI.encode_query()

    "#{@imds_endpoint}?#{params}"
  end

  defp maybe_add_identity_param(params, config) do
    cond do
      client_id = Map.get(config, :client_id) ->
        params ++ [{"client_id", client_id}]

      object_id = Map.get(config, :object_id) ->
        params ++ [{"object_id", object_id}]

      mi_res_id = Map.get(config, :mi_res_id) ->
        params ++ [{"mi_res_id", mi_res_id}]

      true ->
        params
    end
  end

  defp request_with_retry(url, timeout, attempt) when attempt < @max_retries do
    headers = [{"Metadata", "true"}]

    case Req.get(url, headers: headers, receive_timeout: timeout, retry: false) do
      {:ok, %{status: 200, body: body}} ->
        parse_response(body)

      {:ok, %{status: status, headers: headers}} when status in [429, 503] ->
        delay = get_retry_delay(attempt, headers)
        Process.sleep(delay)
        request_with_retry(url, timeout, attempt + 1)

      {:ok, %{status: status, body: body}} when status in 400..599 ->
        handle_error_response(status, body)

      {:error, reason} ->
        if attempt < @max_retries - 1 do
          delay = calculate_backoff(attempt)
          Process.sleep(delay)
          request_with_retry(url, timeout, attempt + 1)
        else
          {:error,
           NetworkError.exception(
             service: :azure_imds,
             endpoint: @imds_endpoint,
             reason: reason
           )}
        end
    end
  end

  defp request_with_retry(_url, _timeout, _attempt) do
    {:error,
     ManagedIdentityError.exception(
       type: :imds_unavailable,
       provider: :imds,
       reason: "max retries exceeded"
     )}
  end

  defp parse_response(body) when is_map(body) do
    with {:ok, access_token} <- Map.fetch(body, "access_token"),
         {:ok, expires_on} <- get_expiry(body) do
      token_type = Map.get(body, "token_type", "Bearer")
      resource = Map.get(body, "resource")

      {:ok,
       %{
         access_token: access_token,
         expires_at: expires_on,
         expires_in: max(expires_on - System.system_time(:second), 0),
         token_type: token_type,
         scope: resource
       }}
    else
      :error ->
        {:error,
         ManagedIdentityError.exception(
           type: :invalid_response,
           provider: :imds,
           reason: body
         )}
    end
  end

  defp parse_response(body) do
    {:error,
     ManagedIdentityError.exception(
       type: :invalid_response,
       provider: :imds,
       reason: body
     )}
  end

  defp get_expiry(body) do
    cond do
      expires_on = Map.get(body, "expires_on") ->
        {:ok, parse_timestamp(expires_on)}

      expires_in = Map.get(body, "expires_in") ->
        {:ok, System.system_time(:second) + parse_int(expires_in)}

      true ->
        :error
    end
  end

  defp parse_timestamp(value) when is_integer(value), do: value

  defp parse_timestamp(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> System.system_time(:second) + 3600
    end
  end

  defp parse_timestamp(_), do: System.system_time(:second) + 3600

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 3600
    end
  end

  defp parse_int(_), do: 3600

  defp handle_error_response(status, body) when is_map(body) do
    error_desc = Map.get(body, "error_description", "Unknown IMDS error")
    error_code = Map.get(body, "error", "unknown")

    {:error,
     ManagedIdentityError.exception(
       type: :provider_error,
       provider: :imds,
       reason: "#{error_code}: #{error_desc}",
       status: status
     )}
  end

  defp handle_error_response(status, body) do
    {:error,
     ManagedIdentityError.exception(
       type: :provider_error,
       provider: :imds,
       reason: inspect(body),
       status: status
     )}
  end

  defp get_retry_delay(attempt, headers) do
    case get_retry_after_header(headers) do
      {:ok, seconds} -> seconds * 1000
      :error -> calculate_backoff(attempt)
    end
  end

  defp get_retry_after_header(headers) do
    headers
    |> Enum.find(fn {name, _} -> String.downcase(name) == "retry-after" end)
    |> case do
      {_, value} ->
        case Integer.parse(value) do
          {seconds, _} -> {:ok, seconds}
          :error -> :error
        end

      nil ->
        :error
    end
  end

  defp calculate_backoff(attempt) do
    delay = @initial_retry_delay * :math.pow(2, attempt)
    min(round(delay), @max_retry_delay)
  end
end
