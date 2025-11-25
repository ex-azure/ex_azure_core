defmodule ExAzureCore.Auth.FederatedTokenProvider do
  @moduledoc """
  Behaviour and dispatcher for federated identity token providers.

  Provides a unified interface for obtaining tokens from various federated
  identity providers such as AWS Cognito.
  """
  require Logger

  alias ExAzureCore.Auth.Errors.FederationError

  @callback get_token(identity_id :: String.t(), opts :: Keyword.t()) ::
              {:ok, String.t()} | {:error, String.t()}

  def get_token(provider, opts \\ []) do
    {identity_id, opts} = Keyword.pop(opts, :identity_id, "")

    with {:ok, module} <- provider_module(provider) do
      module.get_token(identity_id, opts)
    end
  end

  defp provider_module(:aws_cognito),
    do: {:ok, ExAzureCore.Auth.FederationTokenProvider.AwsCognito}

  defp provider_module(other) do
    {:error, FederationError.exception(type: :unknown_provider, provider: other, reason: nil)}
  end
end
