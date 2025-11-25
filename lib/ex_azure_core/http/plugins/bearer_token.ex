defmodule ExAzureCore.Http.Plugins.BearerToken do
  @moduledoc """
  Req plugin that adds Bearer token authentication to requests.

  Integrates with `ExAzureCore.Auth.TokenServer` to fetch and manage
  access tokens for Azure services.

  ## Options

    * `:credential` - TokenServer name (atom) to fetch tokens from
    * `:token` - Static token string (alternative to credential)

  ## Example

      # Using a TokenServer
      req = Req.new()
      |> ExAzureCore.Http.Plugins.BearerToken.attach(credential: :my_azure_credential)

      # Using a static token
      req = Req.new()
      |> ExAzureCore.Http.Plugins.BearerToken.attach(token: "eyJ...")
  """

  alias ExAzureCore.Auth

  @doc """
  Attaches the bearer token plugin to a Req request.
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts \\ []) do
    request
    |> Req.Request.register_options([:credential, :token])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(bearer_token: &add_bearer_token/1)
  end

  defp add_bearer_token(request) do
    case get_token(request) do
      {:ok, token} ->
        Req.Request.put_header(request, "authorization", "Bearer #{token}")

      {:error, reason} ->
        %{request | private: Map.put(request.private, :bearer_token_error, reason)}
    end
  end

  defp get_token(request) do
    cond do
      token = request.options[:token] ->
        {:ok, token}

      credential = request.options[:credential] ->
        fetch_from_credential(credential)

      true ->
        {:error, :no_credential_configured}
    end
  end

  defp fetch_from_credential(credential) do
    case Auth.fetch(credential) do
      {:ok, %{access_token: token}} ->
        {:ok, token}

      {:ok, token} when is_binary(token) ->
        {:ok, token}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
