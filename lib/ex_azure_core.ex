defmodule ExAzureCore do
  @moduledoc """
  Azure SDK for Elixir.

  ExAzureCore provides a unified interface for making Azure API requests,
  following the pattern established by ExAws.

  ## Usage

  Service modules (like ExAzureStorage, ExAzureKeyVault) build operations
  that are executed via `ExAzureCore.request/2`:

      # Service module builds an operation
      operation = ExAzureStorage.list_containers()

      # ExAzureCore executes it
      {:ok, result} = ExAzureCore.request(operation)

      # With per-request configuration overrides
      {:ok, result} = ExAzureCore.request(operation, account: "other-account")

      # Raise on error
      result = ExAzureCore.request!(operation)

      # Stream paginated results
      stream = ExAzureCore.stream!(operation)

  ## Configuration

  Configuration is merged from multiple sources (lowest to highest priority):

  1. Service defaults (API versions, hosts, etc.)
  2. Global config from `config :ex_azure_core`
  3. Service-specific config from `config :ex_azure_core, :service_name`
  4. Per-request overrides

  ### Example Configuration

      # config/config.exs

      # Global defaults
      config :ex_azure_core,
        timeout: 30_000,
        max_retries: 3

      # Storage service
      config :ex_azure_core, :storage,
        account: {:system, "AZURE_STORAGE_ACCOUNT"},
        credential: my_storage_credential

      # Key Vault service
      config :ex_azure_core, :keyvault,
        vault_name: "my-vault",
        credential: :azure_default_credential

  ## Authentication

  ExAzureCore supports multiple authentication methods via credentials:

  - `AzureKeyCredential` - API key authentication (Cognitive Services, etc.)
  - `AzureSasCredential` - SAS token authentication (Storage)
  - `AzureNamedKeyCredential` - Shared key authentication (Storage, Cosmos DB)
  - TokenServer name (atom) - OAuth2 bearer token (Management, Key Vault, Graph)

  ## Telemetry

  ExAzureCore emits telemetry events for observability:

  - `[:ex_azure_core, :request, :start]` - Request started
  - `[:ex_azure_core, :request, :stop]` - Request completed
  - `[:ex_azure_core, :request, :exception]` - Request raised exception

  See `ExAzureCore.Telemetry` for details.
  """

  alias ExAzureCore.Config
  alias ExAzureCore.Operation
  alias ExAzureCore.Telemetry

  @doc """
  Executes an Azure operation.

  Takes an operation struct built by a service module and executes it
  using the merged configuration.

  ## Parameters

  - `operation` - An operation struct implementing `ExAzureCore.Operation` protocol
  - `config_overrides` - Optional keyword list of configuration overrides

  ## Returns

  - `{:ok, result}` - Successful response (parsed by operation's parser)
  - `{:error, error}` - Error response

  ## Examples

      # Basic request
      operation = ExAzureStorage.list_containers()
      {:ok, containers} = ExAzureCore.request(operation)

      # With overrides
      {:ok, containers} = ExAzureCore.request(operation, account: "staging")

      # Manual operation
      operation = %ExAzureCore.Operation.REST{
        service: :keyvault,
        http_method: :get,
        path: "/secrets/my-secret",
        parser: fn resp -> resp.body end
      }
      {:ok, secret} = ExAzureCore.request(operation, vault_name: "my-vault")
  """
  @spec request(Operation.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def request(operation, config_overrides \\ []) do
    config = Config.new(operation.service, config_overrides)

    Telemetry.span(operation, config, fn ->
      Operation.perform(operation, config)
    end)
  end

  @doc """
  Executes an Azure operation, raising on error.

  Same as `request/2` but raises the error instead of returning `{:error, _}`.

  ## Examples

      containers = ExAzureCore.request!(ExAzureStorage.list_containers())

  ## Raises

  Raises the error returned by the operation.
  """
  @spec request!(Operation.t(), keyword()) :: term()
  def request!(operation, config_overrides \\ []) do
    case request(operation, config_overrides) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns a stream for paginated Azure resources.

  The operation must support streaming (have a `stream_builder` function).

  ## Parameters

  - `operation` - An operation struct that supports streaming
  - `config_overrides` - Optional keyword list of configuration overrides

  ## Returns

  An `Enumerable.t()` that lazily fetches pages.

  ## Examples

      # Stream all blobs in a container
      ExAzureStorage.list_blobs("my-container")
      |> ExAzureCore.stream!()
      |> Enum.take(100)

      # Process in batches
      ExAzureStorage.list_blobs("my-container")
      |> ExAzureCore.stream!()
      |> Stream.chunk_every(50)
      |> Enum.each(&process_batch/1)

  ## Raises

  Raises `ArgumentError` if the operation does not support streaming.
  """
  @spec stream!(Operation.t(), keyword()) :: Enumerable.t()
  def stream!(operation, config_overrides \\ []) do
    config = Config.new(operation.service, config_overrides)
    Operation.stream!(operation, config)
  end
end
