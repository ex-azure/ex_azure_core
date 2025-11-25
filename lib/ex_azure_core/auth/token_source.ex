defmodule ExAzureCore.Auth.TokenSource do
  @moduledoc """
  Behavior for token sources.

  A token source is responsible for fetching access tokens from a specific
  authentication mechanism. Different sources implement different authentication
  flows (client assertion, managed identity, refresh token, etc.).

  ## Implementing a Source

  To implement a new source, create a module that implements the `fetch_token/1`
  callback:

      defmodule MyApp.CustomSource do
        @behaviour ExAzureIdentity.Source

        @impl true
        def fetch_token(config) do
          # Fetch token using custom logic
          {:ok, %{
            access_token: "...",
            expires_at: System.system_time(:second) + 3600,
            token_type: "Bearer",
            scope: "..."
          }}
        end
      end

  ## Token Format

  The token map returned by `fetch_token/1` must include:

    * `:access_token` - The access token string
    * `:expires_at` - Unix timestamp (seconds) when token expires
    * `:token_type` - Token type (usually "Bearer")
    * `:scope` - Optional scope string
  """

  @doc """
  Fetches an access token from the source.

  ## Parameters

    * `config` - Source-specific configuration map

  ## Returns

    * `{:ok, token}` - A map containing the token and metadata
    * `{:error, reason}` - An error tuple with the failure reason
  """
  @callback fetch_token(config :: keyword()) :: {:ok, map()} | {:error, term()}
end
