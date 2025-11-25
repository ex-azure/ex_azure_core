defmodule ExAzureCore.Config do
  @moduledoc """
  Configuration management for ExAzureCore.

  Builds configuration by merging from multiple sources (lowest to highest priority):
  1. Service defaults from `ExAzureCore.Config.Defaults`
  2. Global config from `config :ex_azure_core`
  3. Service-specific config from `config :ex_azure_core, :service_name`
  4. Per-request overrides from `ExAzureCore.request(op, overrides)`

  ## Application Configuration

      # config/config.exs

      # Global defaults (apply to all services)
      config :ex_azure_core,
        timeout: 30_000,
        max_retries: 3

      # Service-specific configuration
      config :ex_azure_core, :storage,
        account: {:system, "AZURE_STORAGE_ACCOUNT"},
        credential: my_named_key_credential

      config :ex_azure_core, :keyvault,
        vault_name: "my-vault",
        credential: :azure_default_credential  # TokenServer name

  ## Runtime Value Resolution

  Values can be resolved at runtime using `{:system, "ENV_VAR"}` tuples:

      config :ex_azure_core, :storage,
        account: {:system, "AZURE_STORAGE_ACCOUNT"},
        credential: {:system, "AZURE_STORAGE_KEY"}

  ## Credential Types

  The `:credential` config accepts:
  - `AzureKeyCredential` struct - Uses ApiKey plugin
  - `AzureSasCredential` struct - Uses SasToken plugin
  - `AzureNamedKeyCredential` struct - Uses SharedKey plugin
  - Atom (e.g., `:my_credential`) - Uses BearerToken plugin with TokenServer
  """

  alias ExAzureCore.Config.Defaults
  alias ExAzureCore.Credentials.AzureKeyCredential
  alias ExAzureCore.Credentials.AzureNamedKeyCredential
  alias ExAzureCore.Credentials.AzureSasCredential
  alias ExAzureCore.Http.Plugins

  @common_config_keys [
    :credential,
    :timeout,
    :pool_timeout,
    :max_retries
  ]

  @doc """
  Builds complete configuration for a service operation.

  ## Examples

      # With defaults only
      config = ExAzureCore.Config.new(:keyvault)

      # With per-request overrides
      config = ExAzureCore.Config.new(:storage, account: "other-account")
  """
  @spec new(atom(), keyword()) :: map()
  def new(service, overrides \\ []) do
    overrides_map = Map.new(overrides)

    service
    |> build_base_config(overrides_map)
    |> resolve_runtime_values()
    |> resolve_host_template()
    |> build_plugins()
  end

  defp build_base_config(service, overrides) do
    defaults = Defaults.get(service)

    global_config =
      Application.get_all_env(:ex_azure_core)
      |> Enum.reject(fn {k, _} -> (is_atom(k) and k == service) or is_tuple(k) end)
      |> Map.new()
      |> Map.take(@common_config_keys ++ [:api_key_header])

    service_config =
      Application.get_env(:ex_azure_core, service, [])
      |> Map.new()

    defaults
    |> Map.merge(global_config)
    |> Map.merge(service_config)
    |> Map.merge(overrides)
    |> Map.put(:service, service)
  end

  defp resolve_runtime_values(config) do
    Enum.reduce(config, config, fn
      {key, {:system, env_var}}, acc ->
        Map.put(acc, key, System.get_env(env_var))

      {key, {:system, env_var, default}}, acc ->
        Map.put(acc, key, System.get_env(env_var) || default)

      _, acc ->
        acc
    end)
  end

  defp resolve_host_template(config) do
    case Map.get(config, :host) do
      nil ->
        config

      host when is_binary(host) ->
        resolved_host =
          host
          |> String.replace("{account}", Map.get(config, :account, "") || "")
          |> String.replace("{vault_name}", Map.get(config, :vault_name, "") || "")
          |> String.replace("{namespace}", Map.get(config, :namespace, "") || "")
          |> String.replace("{endpoint}", Map.get(config, :endpoint, "") || "")

        base_url =
          if String.starts_with?(resolved_host, "http") do
            resolved_host
          else
            "https://#{resolved_host}"
          end

        Map.put(config, :base_url, base_url)
    end
  end

  defp build_plugins(config) do
    auth_plugins = auth_plugins_for(config)
    base_plugins = Defaults.base_plugins()

    api_version = Map.get(config, :api_version)

    base_plugins_with_version =
      Enum.map(base_plugins, fn
        {Plugins.AzureHeaders, opts} ->
          {Plugins.AzureHeaders, Keyword.put(opts, :api_version, api_version)}

        {Plugins.Retry, opts} ->
          max_retries = Map.get(config, :max_retries, 3)
          {Plugins.Retry, Keyword.put(opts, :max_retries, max_retries)}

        other ->
          other
      end)

    Map.put(config, :plugins, auth_plugins ++ base_plugins_with_version)
  end

  defp auth_plugins_for(%{credential: %AzureKeyCredential{} = cred} = config) do
    header_name = Map.get(config, :api_key_header, "api-key")
    [{Plugins.ApiKey, api_key: cred, header_name: header_name}]
  end

  defp auth_plugins_for(%{credential: %AzureSasCredential{} = cred}) do
    [{Plugins.SasToken, sas_token: cred}]
  end

  defp auth_plugins_for(%{credential: %AzureNamedKeyCredential{} = cred}) do
    [{Plugins.SharedKey, credential: cred}]
  end

  defp auth_plugins_for(%{credential: name}) when is_atom(name) and not is_nil(name) do
    [{Plugins.BearerToken, credential: name}]
  end

  defp auth_plugins_for(_config) do
    []
  end
end
