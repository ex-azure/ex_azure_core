defmodule ExAzureCore.Auth.ManagedIdentity.AppServiceProvider do
  @moduledoc """
  App Service provider for Azure Managed Identity.

  Fetches tokens from the Azure App Service identity endpoint for
  App Service, Functions, and Logic Apps workloads.

  ## Environment Variables

  The following environment variables must be set by Azure:

    * `IDENTITY_ENDPOINT` - The identity endpoint URL
    * `IDENTITY_HEADER` - Secret header value for authentication

  ## Configuration

    * `:resource` (required) - The Azure resource URI
    * `:client_id` (optional) - Client ID for user-assigned managed identity
  """

  alias ExAzureCore.Auth.Errors.ManagedIdentityError
  alias ExAzureCore.Errors.NetworkError

  @api_version "2019-08-01"
  @default_timeout 5_000

  @type config :: %{
          required(:resource) => String.t(),
          optional(:client_id) => String.t(),
          optional(:timeout) => non_neg_integer()
        }

  @doc """
  Fetches an access token from Azure App Service identity endpoint.

  ## Configuration

    * `:resource` (required) - The Azure resource URI
    * `:client_id` (optional) - Client ID for user-assigned managed identity
    * `:timeout` (optional) - Request timeout in milliseconds (default: 5000)

  ## Examples

      {:ok, token} = AppServiceProvider.fetch_token(%{
        resource: "https://management.azure.com/"
      })
  """
  @spec fetch_token(config()) :: {:ok, map()} | {:error, term()}
  def fetch_token(config) when is_map(config) do
    with {:ok, endpoint} <- get_identity_endpoint(),
         {:ok, header_value} <- get_identity_header(),
         {:ok, resource} <- fetch_required(config, :resource) do
      url = build_url(endpoint, resource, config)
      headers = build_headers(header_value)
      timeout = Map.get(config, :timeout, @default_timeout)

      request_token(url, headers, timeout)
    end
  end

  defp get_identity_endpoint do
    case System.get_env("IDENTITY_ENDPOINT") do
      nil ->
        {:error,
         ManagedIdentityError.exception(
           type: :provider_error,
           provider: :app_service,
           reason: "IDENTITY_ENDPOINT environment variable not set"
         )}

      endpoint ->
        {:ok, endpoint}
    end
  end

  defp get_identity_header do
    case System.get_env("IDENTITY_HEADER") do
      nil ->
        {:error,
         ManagedIdentityError.exception(
           type: :provider_error,
           provider: :app_service,
           reason: "IDENTITY_HEADER environment variable not set"
         )}

      header ->
        {:ok, header}
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
           provider: :app_service,
           reason: "#{key} cannot be empty"
         )}

      :error ->
        {:error,
         ManagedIdentityError.exception(
           type: :provider_error,
           provider: :app_service,
           reason: "missing required field: #{key}"
         )}
    end
  end

  defp build_url(endpoint, resource, config) do
    params =
      [
        {"api-version", @api_version},
        {"resource", resource}
      ]
      |> maybe_add_client_id(config)
      |> URI.encode_query()

    "#{endpoint}?#{params}"
  end

  defp maybe_add_client_id(params, %{client_id: client_id}) when is_binary(client_id) do
    params ++ [{"client_id", client_id}]
  end

  defp maybe_add_client_id(params, _config), do: params

  defp build_headers(header_value) do
    [
      {"X-IDENTITY-HEADER", header_value}
    ]
  end

  defp request_token(url, headers, timeout) do
    case Req.get(url, headers: headers, receive_timeout: timeout, retry: false) do
      {:ok, %{status: 200, body: body}} ->
        parse_response(body)

      {:ok, %{status: status, body: body}} when status in 400..599 ->
        handle_error_response(status, body)

      {:error, reason} ->
        {:error,
         NetworkError.exception(
           service: :azure_app_service_identity,
           endpoint: url,
           reason: reason
         )}
    end
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
           provider: :app_service,
           reason: body
         )}
    end
  end

  defp parse_response(body) do
    {:error,
     ManagedIdentityError.exception(
       type: :invalid_response,
       provider: :app_service,
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
    error_desc = Map.get(body, "error_description", "Unknown error")
    error_code = Map.get(body, "error", "unknown")

    {:error,
     ManagedIdentityError.exception(
       type: :provider_error,
       provider: :app_service,
       reason: "#{error_code}: #{error_desc}",
       status: status
     )}
  end

  defp handle_error_response(status, body) do
    {:error,
     ManagedIdentityError.exception(
       type: :provider_error,
       provider: :app_service,
       reason: inspect(body),
       status: status
     )}
  end
end
