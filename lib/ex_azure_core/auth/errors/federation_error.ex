defmodule ExAzureCore.Auth.Errors.FederationError do
  @moduledoc """
  Error for federated token provider operations.

  Used when fetching tokens from external identity providers (AWS Cognito, etc.)
  fails or when an unknown provider is specified.
  """
  use Splode.Error, fields: [:type, :provider, :reason], class: :external

  @type t() :: %__MODULE__{
          type: :token_fetch_failed | :unknown_provider,
          provider: atom(),
          reason: term()
        }

  @impl true
  def message(%{type: :token_fetch_failed, provider: provider, reason: reason}) do
    "Failed to fetch token from federation provider #{provider}: #{inspect(reason)}"
  end

  def message(%{type: :unknown_provider, provider: provider, reason: _reason}) do
    "Unknown federation provider: #{inspect(provider)}"
  end
end
