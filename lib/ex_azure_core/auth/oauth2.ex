defmodule ExAzureCore.Auth.OAuth2 do
  @moduledoc """
  OAuth2 token exchange for Azure AD.
  """

  require Logger

  alias ExAzureCore.Auth.Errors.AzureAdStsError
  alias ExAzureCore.Auth.Errors.InvalidTokenFormat
  alias ExAzureCore.Errors.NetworkError

  @token_endpoint_suffix "/oauth2/v2.0/token"

  @doc """
  Exchanges a client assertion for an access token.
  """
  def get_token(tenant_id, client_id, assertion, scope, cloud \\ :public) do
    endpoint = token_endpoint(tenant_id, cloud)

    body = %{
      "grant_type" => "client_credentials",
      "client_id" => client_id,
      "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      "client_assertion" => assertion,
      "scope" => scope
    }

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    case Req.post(endpoint, form: body, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_token_response(body)

      {:ok, %{status: status, body: body}} when status in 400..599 ->
        AzureAdStsError.handle_error(body)

      {:error, reason} ->
        {:error,
         NetworkError.exception(service: :azure_oauth2, endpoint: endpoint, reason: reason)}
    end
  end

  @doc """
  Builds the token endpoint URL for the given tenant.
  """
  def token_endpoint(tenant_id, cloud \\ :public) do
    base_url = cloud_base_url(cloud)
    "#{base_url}/#{tenant_id}#{@token_endpoint_suffix}"
  end

  @doc """
  Parses a successful token response.
  """
  def parse_token_response(response) when is_map(response) do
    with {:ok, access_token} <- Map.fetch(response, "access_token"),
         {:ok, expires_in} <- Map.fetch(response, "expires_in") do
      token_type = Map.get(response, "token_type", "Bearer")
      scope = Map.get(response, "scope")

      {:ok,
       %{
         access_token: access_token,
         expires_in: expires_in,
         token_type: token_type,
         scope: scope,
         expires_at: calculate_expiry(expires_in)
       }}
    else
      :error ->
        {:error, InvalidTokenFormat.exception(token: response)}
    end
  end

  def parse_token_response(response) do
    {:error, InvalidTokenFormat.exception(token: response)}
  end

  defp cloud_base_url(:public), do: "https://login.microsoftonline.com"
  defp cloud_base_url(:government), do: "https://login.microsoftonline.us"
  defp cloud_base_url(:china), do: "https://login.chinacloudapi.cn"
  defp cloud_base_url(:germany), do: "https://login.microsoftonline.de"
  defp cloud_base_url(custom) when is_binary(custom), do: custom

  defp calculate_expiry(expires_in) when is_integer(expires_in) do
    System.system_time(:second) + expires_in
  end

  defp calculate_expiry(expires_in) when is_binary(expires_in) do
    case Integer.parse(expires_in) do
      {seconds, _} -> System.system_time(:second) + seconds
      :error -> System.system_time(:second) + 3600
    end
  end

  defp calculate_expiry(_), do: System.system_time(:second) + 3600
end
