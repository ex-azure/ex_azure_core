defmodule ExAzureCore.Auth do
  alias ExAzureCore.Auth.Errors.TokenServerError

  @doc """
  Starts a credential server.

  This function is typically called via a child spec in a supervision tree.

  ## Options

  See module documentation for available options.

  ## Examples

      {:ok, pid} = ExAzureIdentity.start_link(
        name: :my_credential,
        source: {:client_assertion, %{
          tenant_id: "...",
          client_id: "...",
          scope: "https://graph.microsoft.com/.default",
          provider: :aws_cognito,
          provider_opts: [identity_id: "..."]
        }}
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  defdelegate start_link(opts), to: ExAzureCore.Auth.TokenServer

  @doc """
  Returns a child spec for starting the credential server under a supervisor.

  ## Examples

      children = [
        {ExAzureIdentity,
          name: MyApp.AzureToken,
          source: {:client_assertion, config}}
      ]
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Fetches the current token from a credential server.

  Returns the cached token if available and still valid, otherwise fetches
  a new one from the token source.

  ## Parameters

    * `name` - The name of the credential server

  ## Returns

    * `{:ok, token}` - A map containing the access token and metadata
    * `{:error, reason}` - An error tuple with the failure reason

  ## Examples

      {:ok, token} = ExAzureIdentity.fetch(MyApp.AzureToken)
      token.access_token
      #=> "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ik..."
      token.expires_at
      #=> 1234567890
  """
  @spec fetch(atom()) :: {:ok, map()} | {:error, term()}
  defdelegate fetch(name), to: ExAzureCore.Auth.TokenServer

  @doc """
  Fetches the current token from a credential server, raising on error.

  ## Parameters

    * `name` - The name of the credential server

  ## Returns

  A map containing the access token and metadata.

  ## Raises

  Raises a runtime error if the token cannot be fetched.

  ## Examples

      token = ExAzureIdentity.fetch!(MyApp.AzureToken)
      token.access_token
      #=> "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ik..."
  """
  @spec fetch!(atom()) :: map()
  def fetch!(name) do
    case fetch(name) do
      {:ok, token} ->
        token

      {:error, reason} ->
        raise TokenServerError.exception(type: :fetch_failed, name: name, reason: reason)
    end
  catch
    :exit, reason ->
      raise TokenServerError.exception(type: :fetch_failed, name: name, reason: reason)
  end
end
