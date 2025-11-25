defprotocol ExAzureCore.Operation do
  @moduledoc """
  Protocol for Azure service operations.

  Service modules (like ExAzureStorage, ExAzureKeyVault) implement this protocol
  to define how requests are built and responses are parsed.

  ## Example

      # Service module builds an operation
      operation = ExAzureStorage.list_containers()

      # ExAzureCore executes it
      {:ok, result} = ExAzureCore.request(operation)

  ## Implementing Custom Operations

      defmodule MyOperation do
        defstruct [:service, :path, :method]
      end

      defimpl ExAzureCore.Operation, for: MyOperation do
        def perform(op, config) do
          # Build and execute request
        end

        def stream!(op, config) do
          # Return enumerable for paginated results
        end
      end
  """

  @doc """
  Executes the operation and returns the result.

  The config map contains merged configuration from:
  1. Service defaults
  2. Global application config
  3. Service-specific config
  4. Per-request overrides
  """
  @spec perform(t(), map()) :: {:ok, term()} | {:error, term()}
  def perform(operation, config)

  @doc """
  Returns a stream for paginated Azure resources.

  Raises `ArgumentError` if the operation does not support streaming.
  """
  @spec stream!(t(), map()) :: Enumerable.t()
  def stream!(operation, config)
end
