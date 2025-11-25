defmodule ExAzureCore.Config.Defaults do
  @moduledoc """
  Default configuration for Azure services.

  Provides service-specific defaults including host templates, API versions,
  and OAuth scopes. These are the lowest priority in the configuration
  merging hierarchy.

  ## Adding Custom Service Defaults

  Service modules can register their own defaults at application startup:

      ExAzureCore.Config.Defaults.register(:my_service, %{
        host: "myservice.azure.com",
        api_version: "2024-01-01",
        scope: "https://myservice.azure.com/.default"
      })
  """

  alias ExAzureCore.Http.Plugins

  @common_plugins [
    Plugins.RequestId,
    {Plugins.AzureHeaders, []},
    {Plugins.Retry, max_retries: 3},
    Plugins.ErrorHandler
  ]

  @common_config %{
    timeout: 30_000,
    pool_timeout: 5_000,
    max_retries: 3
  }

  @service_defaults %{
    management: %{
      host: "management.azure.com",
      api_version: "2024-03-01",
      scope: "https://management.azure.com/.default"
    }
  }

  @doc """
  Returns default configuration for a service.

  ## Examples

      iex> ExAzureCore.Config.Defaults.get(:keyvault)
      %{host: "{vault_name}.vault.azure.net", api_version: "7.5", ...}

      iex> ExAzureCore.Config.Defaults.get(:unknown)
      %{timeout: 30_000, pool_timeout: 5_000, max_retries: 3}
  """
  @spec get(atom()) :: map()
  def get(service) do
    custom = Application.get_env(:ex_azure_core, {:defaults, service}, %{})

    builtin =
      Map.get(@service_defaults, service, %{})
      |> Map.merge(@common_config)

    Map.merge(builtin, custom)
  end

  @doc """
  Returns the base plugins for a service.

  These are the standard plugins that should be attached to most requests:
  - RequestId: Generates client request IDs
  - AzureHeaders: Adds x-ms-version and x-ms-date headers
  - Retry: Implements exponential backoff retry
  - ErrorHandler: Parses Azure error responses
  """
  @spec base_plugins() :: list()
  def base_plugins do
    @common_plugins
  end

  @doc """
  Registers custom defaults for a service.

  Use this to add defaults for services not built into ExAzureCore.

  ## Example

      ExAzureCore.Config.Defaults.register(:my_service, %{
        host: "myservice.azure.com",
        api_version: "2024-01-01"
      })
  """
  @spec register(atom(), map()) :: :ok
  def register(service, defaults) when is_atom(service) and is_map(defaults) do
    Application.put_env(:ex_azure_core, {:defaults, service}, defaults)
    :ok
  end
end
