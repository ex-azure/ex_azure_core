defmodule ExAzureCore.Auth.FederationTokenProvider.AwsCognito do
  @moduledoc """
  AWS Cognito implementation for federated token provider.

  Supports both basic and enhanced authentication flows for retrieving
  identity tokens from AWS Cognito Identity pools.

  ## Authentication flows

    * `:basic` - calls `GetOpenIdToken` with an existing Cognito `IdentityId`.
    * `:enhanced` - calls `GetOpenIdTokenForDeveloperIdentity` with the identity
      pool id and a `:logins` map (developer-authenticated identities).

  ## Pinning a Cognito IdentityId in the enhanced flow

  In the enhanced flow the first argument is the *identity pool id*, not a
  Cognito `IdentityId`. By default `GetOpenIdTokenForDeveloperIdentity` resolves
  the developer-user-identifier from `:logins` to an existing identity, or
  creates a new one when none matches. That implicit resolve-or-create runs on
  every token refresh, so a new identity can be minted whenever resolution
  fails, and the OIDC token's subject (the `IdentityId`) drifts away from the
  one that was federated into Azure.

  Pass `:cognito_identity_id` to pin the exact identity established at setup. It
  is forwarded as the `IdentityId` argument so Cognito reuses that identity
  instead of resolving or creating one per refresh:

      AwsCognito.get_token(pool_id,
        auth_type: :enhanced,
        logins: %{"your-developer-provider" => client_id},
        cognito_identity_id: "us-east-1:12345678-1234-1234-1234-123456789012"
      )
  """
  @behaviour ExAzureCore.Auth.FederatedTokenProvider

  alias ExAws.CognitoIdentity
  alias ExAzureCore.Auth.Errors.ConfigurationError
  alias ExAzureCore.Auth.Errors.FederationError

  @impl true
  def get_token(identity_id, opts) do
    case opts[:auth_type] do
      :basic -> fetch_token_using_basic_auth(identity_id)
      :enhanced -> fetch_token_using_enhanced_auth(identity_id, opts)
    end
  end

  defp fetch_token_using_basic_auth(identity_id) do
    CognitoIdentity.get_open_id_token(identity_id)
    |> ExAws.request()
    |> handle_response()
  end

  defp fetch_token_using_enhanced_auth(pool_id, opts) do
    with {:ok, logins} <- parse_logins(opts) do
      CognitoIdentity.get_open_id_token_for_developer_identity(
        pool_id,
        logins,
        identity_opts(opts)
      )
      |> ExAws.request()
      |> handle_response()
    end
  end

  defp identity_opts(opts) do
    case Keyword.get(opts, :cognito_identity_id) do
      nil -> []
      cognito_identity_id -> [identity_id: cognito_identity_id]
    end
  end

  defp handle_response({:ok, %{"Token" => token}}), do: {:ok, token}

  defp handle_response({:error, err}) do
    {:error,
     FederationError.exception(type: :token_fetch_failed, provider: :aws_cognito, reason: err)}
  end

  defp parse_logins(opts) do
    case Keyword.get(opts, :logins) do
      nil ->
        {:error, ConfigurationError.exception(type: :missing_required, key: :logins, value: nil)}

      logins when is_map(logins) ->
        {:ok, logins}

      logins when is_binary(logins) ->
        {:ok, split_logins(logins)}

      logins ->
        {:error, ConfigurationError.exception(type: :invalid_value, key: :logins, value: logins)}
    end
  end

  defp split_logins(logins) when is_binary(logins) do
    logins
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn entry ->
      case String.split(entry, "=", parts: 2) do
        [key, value] -> {String.trim(key), String.trim(value)}
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
    |> Enum.into(%{})
  end
end
