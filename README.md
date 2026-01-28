# ExAzureCore

Base library for Azure SDKs in Elixir. Provides authentication, HTTP client infrastructure, and common utilities for service-specific Azure SDKs.

## Installation

Add `ex_azure_core` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_azure_core, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
# Define an operation (typically done by service SDKs)
operation = %ExAzureCore.Operation.REST{
  method: :get,
  service: :storage,
  path: "/",
  params: %{comp: "list"}
}

# Execute the operation
{:ok, response} = ExAzureCore.request(operation)

# Or raise on error
response = ExAzureCore.request!(operation)

# Stream paginated results
ExAzureCore.stream!(operation)
|> Enum.each(&process_item/1)
```

## Configuration

Configuration uses a 4-level hierarchy (lowest to highest priority):

1. Service defaults
2. Global config: `config :ex_azure_core`
3. Service-specific: `config :ex_azure_core, :storage`
4. Per-request overrides

```elixir
# config/config.exs
config :ex_azure_core,
  tenant_id: {:system, "AZURE_TENANT_ID"},
  client_id: {:system, "AZURE_CLIENT_ID"}

config :ex_azure_core, :storage,
  account_name: "myaccount"
```

## License

MIT
