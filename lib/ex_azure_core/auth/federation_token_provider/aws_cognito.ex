defmodule ExAzureCore.Auth.FederationTokenProvider.AwsCognito do
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
    case CognitoIdentity.get_open_id_token(identity_id) |> ExAws.request() do
      {:ok, result} ->
        {:ok, result["Token"]}

      {:error, err} ->
        {:error,
         FederationError.exception(type: :token_fetch_failed, provider: :aws_cognito, reason: err)}
    end
  end

  defp fetch_token_using_enhanced_auth(identity_id, opts) do
    with {:ok, logins} <- parse_logins(opts) do
      do_fetch_token_using_enhanced_auth(identity_id, logins)
    end
  end

  defp do_fetch_token_using_enhanced_auth(identity_id, logins) do
    case CognitoIdentity.get_open_id_token_for_developer_identity(identity_id, logins)
         |> ExAws.request() do
      {:ok, result} ->
        {:ok, result["Token"]}

      {:error, err} ->
        {:error,
         FederationError.exception(type: :token_fetch_failed, provider: :aws_cognito, reason: err)}
    end
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
