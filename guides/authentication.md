# Authentication

ExAzureCore supports multiple authentication methods for Azure services. This guide covers all available options and when to use each.

## Overview

Authentication in ExAzureCore is handled by the `ExAzureCore.Auth` module, which manages token lifecycle through GenServer-based token servers. Tokens are cached and proactively refreshed before expiry.

### Token Management

The `ExAzureCore.Auth.TokenServer` handles:

- Initial token fetch (sync or async)
- Token caching in a Registry
- Proactive refresh (default: 300 seconds before expiry)
- Exponential backoff retry on failures (up to 10 attempts)

## Authentication Methods

### Managed Identity

Use managed identity when running in Azure environments (VMs, App Service, Container Apps, AKS). No credentials are required as Azure handles identity automatically.

```elixir
config :ex_azure_core,
  auth: :managed_identity
```

#### Supported Environments

| Environment | Detection |
|-------------|-----------|
| Azure VM (IMDS) | Probes `169.254.169.254` metadata endpoint |
| App Service | Checks `IDENTITY_ENDPOINT` and `IDENTITY_HEADER` |
| AKS Workload Identity | Checks `AZURE_FEDERATED_TOKEN_FILE` |

#### User-Assigned Identity

For user-assigned managed identities, specify the client ID:

```elixir
config :ex_azure_core,
  auth: :managed_identity,
  client_id: "your-managed-identity-client-id"
```

#### How It Works

1. `EnvironmentDetector` determines the Azure environment
2. The appropriate provider (`ImdsProvider` or `AppServiceProvider`) is selected
3. Token is fetched from the local metadata endpoint
4. No external network calls to Azure AD are needed

### Workload Identity

Use workload identity in AKS clusters with workload identity enabled. This exchanges Kubernetes service account tokens for Azure AD tokens.

```elixir
config :ex_azure_core,
  auth: :workload_identity
```

#### Required Environment Variables

These are automatically set by AKS when workload identity is configured:

| Variable | Description |
|----------|-------------|
| `AZURE_FEDERATED_TOKEN_FILE` | Path to projected service account token |
| `AZURE_CLIENT_ID` | Azure AD application client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_AUTHORITY_HOST` | Azure AD authority (optional, defaults to public cloud) |

#### How It Works

1. Kubernetes projects a service account token to a file
2. ExAzureCore reads the token from `AZURE_FEDERATED_TOKEN_FILE`
3. Token is exchanged with Azure AD using client credentials grant with JWT bearer assertion
4. Azure AD validates the token issuer against the federated identity credential

### Client Assertion (Workload Identity Federation)

Use client assertion for cross-cloud authentication or external identity providers. This exchanges tokens from external identity providers for Azure AD tokens.

```elixir
config :ex_azure_core,
  auth: :client_assertion,
  tenant_id: "your-tenant-id",
  client_id: "your-client-id",
  federation_provider: :aws_cognito,
  aws_identity_pool_id: "us-east-1:your-pool-id"
```

#### Supported Federation Providers

##### AWS Cognito

Exchange AWS Cognito identity tokens for Azure AD tokens:

```elixir
config :ex_azure_core,
  auth: :client_assertion,
  tenant_id: {:system, "AZURE_TENANT_ID"},
  client_id: {:system, "AZURE_CLIENT_ID"},
  federation_provider: :aws_cognito,
  aws_identity_pool_id: {:system, "AWS_IDENTITY_POOL_ID"},
  aws_region: "us-east-1"
```

Requires `ex_aws` and `ex_aws_cognito_identity` dependencies:

```elixir
{:ex_aws, "~> 2.3"},
{:ex_aws_cognito_identity, "~> 1.2"}
```

##### Multiple Cognito Pools with Supervisor

For applications that need to authenticate against multiple AWS Cognito identity pools (e.g., multi-tenant or multi-region), use a supervisor to manage multiple token servers dynamically:

```elixir
defmodule MyApp.Azure.TokenSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = []
    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_token_server(name, opts) do
    spec = {ExAzureCore.Auth.TokenServer, Keyword.put(opts, :name, name)}
    Supervisor.start_child(__MODULE__, spec)
  end

  def stop_token_server(name) do
    Supervisor.terminate_child(__MODULE__, name)
    Supervisor.delete_child(__MODULE__, name)
  end
end
```

Define your Cognito configurations:

```elixir
defmodule MyApp.Azure.CognitoConfigs do
  def configs do
    %{
      us_east: [
        tenant_id: System.fetch_env!("AZURE_TENANT_ID"),
        client_id: System.fetch_env!("AZURE_CLIENT_ID_US"),
        scope: "https://storage.azure.com/.default",
        token_source: ExAzureCore.Auth.TokenSource.ClientAssertion,
        token_source_opts: [
          federation_provider: ExAzureCore.Auth.FederationTokenProvider.AwsCognito,
          aws_identity_pool_id: System.fetch_env!("AWS_COGNITO_POOL_US_EAST"),
          aws_region: "us-east-1"
        ]
      ],
      eu_west: [
        tenant_id: System.fetch_env!("AZURE_TENANT_ID"),
        client_id: System.fetch_env!("AZURE_CLIENT_ID_EU"),
        scope: "https://storage.azure.com/.default",
        token_source: ExAzureCore.Auth.TokenSource.ClientAssertion,
        token_source_opts: [
          federation_provider: ExAzureCore.Auth.FederationTokenProvider.AwsCognito,
          aws_identity_pool_id: System.fetch_env!("AWS_COGNITO_POOL_EU_WEST"),
          aws_region: "eu-west-1"
        ]
      ],
      ap_south: [
        tenant_id: System.fetch_env!("AZURE_TENANT_ID"),
        client_id: System.fetch_env!("AZURE_CLIENT_ID_AP"),
        scope: "https://storage.azure.com/.default",
        token_source: ExAzureCore.Auth.TokenSource.ClientAssertion,
        token_source_opts: [
          federation_provider: ExAzureCore.Auth.FederationTokenProvider.AwsCognito,
          aws_identity_pool_id: System.fetch_env!("AWS_COGNITO_POOL_AP_SOUTH"),
          aws_region: "ap-south-1"
        ]
      ]
    }
  end
end
```

Add the supervisor to your application:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Azure.TokenSupervisor
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    start_token_servers()

    {:ok, pid}
  end

  defp start_token_servers do
    for {name, opts} <- MyApp.Azure.CognitoConfigs.configs() do
      MyApp.Azure.TokenSupervisor.start_token_server(name, opts)
    end
  end
end
```

Use a specific token server for requests:

```elixir
defmodule MyApp.Azure.Storage do
  def list_containers(region) do
    operation = %ExAzureCore.Operation.REST{
      method: :get,
      service: :storage,
      path: "/",
      params: %{comp: "list"}
    }

    ExAzureCore.request(operation, auth_name: region)
  end
end

MyApp.Azure.Storage.list_containers(:us_east)
MyApp.Azure.Storage.list_containers(:eu_west)
```

Add or remove token servers at runtime:

```elixir
new_config = [
  tenant_id: "...",
  client_id: "...",
  scope: "https://storage.azure.com/.default",
  token_source: ExAzureCore.Auth.TokenSource.ClientAssertion,
  token_source_opts: [
    federation_provider: ExAzureCore.Auth.FederationTokenProvider.AwsCognito,
    aws_identity_pool_id: "us-west-2:new-pool-id",
    aws_region: "us-west-2"
  ]
]

MyApp.Azure.TokenSupervisor.start_token_server(:us_west, new_config)

MyApp.Azure.TokenSupervisor.stop_token_server(:us_west)
```

##### Custom Providers

Implement the `ExAzureCore.Auth.FederatedTokenProvider` behaviour for custom providers:

```elixir
defmodule MyApp.CustomTokenProvider do
  @behaviour ExAzureCore.Auth.FederatedTokenProvider

  @impl true
  def get_token(opts) do
    # Fetch token from your identity provider
    {:ok, "external-jwt-token"}
  end
end
```

Configure the custom provider:

```elixir
config :ex_azure_core,
  auth: :client_assertion,
  tenant_id: "your-tenant-id",
  client_id: "your-client-id",
  federation_provider: MyApp.CustomTokenProvider
```

#### Azure AD Setup for Federation

1. Register an application in Azure AD
2. Add a federated identity credential:
   - Issuer: Your external IdP issuer URL
   - Subject: The subject claim from the external token
   - Audience: Typically `api://AzureADTokenExchange`
3. Grant the application required permissions

### Static Credentials

For scenarios where token-based auth is not appropriate, use static credentials.

#### API Key

For Azure Cognitive Services, Azure Search, and similar services:

```elixir
credential = ExAzureCore.Credentials.AzureKeyCredential.new("your-api-key")

ExAzureCore.request(operation, credential: credential)
```

The key is added as an HTTP header (typically `api-key` or `Ocp-Apim-Subscription-Key`).

#### SAS Token

For Azure Storage with shared access signatures:

```elixir
credential = ExAzureCore.Credentials.AzureSasCredential.new("sv=2021-06-08&ss=b&srt=sco...")

ExAzureCore.request(operation, credential: credential)
```

The SAS token is appended to the request URL.

#### Named Key (Shared Key)

For Azure Storage and Cosmos DB with account key authentication:

```elixir
credential = ExAzureCore.Credentials.AzureNamedKeyCredential.new(
  "mystorageaccount",
  "base64-encoded-account-key"
)

ExAzureCore.request(operation, credential: credential)
```

Requests are signed using HMAC-SHA256 with the account key.

## Cloud Environments

ExAzureCore supports all Azure cloud environments:

```elixir
# Azure Public Cloud (default)
config :ex_azure_core,
  cloud: :public

# Azure Government
config :ex_azure_core,
  cloud: :government

# Azure China
config :ex_azure_core,
  cloud: :china

# Azure Germany
config :ex_azure_core,
  cloud: :germany
```

Each cloud uses the appropriate Azure AD authority endpoint.

## Scopes

Azure AD tokens are scoped to specific resources. The default scope is derived from the service, but you can override it:

```elixir
config :ex_azure_core,
  scope: "https://storage.azure.com/.default"
```

Common scopes:

| Service | Scope |
|---------|-------|
| Storage | `https://storage.azure.com/.default` |
| Key Vault | `https://vault.azure.net/.default` |
| Management | `https://management.azure.com/.default` |
| Graph | `https://graph.microsoft.com/.default` |

## Token Server Options

Fine-tune token server behavior:

```elixir
config :ex_azure_core,
  # Refresh token this many seconds before expiry (default: 300)
  token_refresh_offset: 300,

  # Initial token fetch mode: :sync or :async (default: :sync)
  prefetch_mode: :sync,

  # Maximum retry attempts on token fetch failure (default: 10)
  max_retries: 10
```

## Error Handling

Authentication errors are returned as structured Splode errors:

```elixir
case ExAzureCore.request(operation) do
  {:ok, response} ->
    # Success

  {:error, %ExAzureCore.Auth.Errors.ConfigurationError{} = error} ->
    # Missing or invalid configuration

  {:error, %ExAzureCore.Auth.Errors.ManagedIdentityError{} = error} ->
    # Managed identity endpoint unavailable

  {:error, %ExAzureCore.Auth.Errors.AzureAdStsError{} = error} ->
    # Azure AD returned an error (invalid credentials, expired token, etc.)

  {:error, %ExAzureCore.Auth.Errors.FederationError{} = error} ->
    # External identity provider error

  {:error, %ExAzureCore.Auth.Errors.TokenServerError{} = error} ->
    # Token server crashed or unavailable
end
```

## Choosing an Authentication Method

| Scenario | Recommended Method |
|----------|-------------------|
| Running in Azure VM/App Service | Managed Identity |
| Running in AKS with workload identity | Workload Identity |
| Cross-cloud (AWS to Azure) | Client Assertion with AWS Cognito |
| GitHub Actions to Azure | Client Assertion with GitHub OIDC |
| Local development | Client Assertion or Static Credentials |
| Service-to-service with shared keys | Named Key Credential |
| Pre-signed URLs | SAS Token |
| Cognitive Services | API Key |

## Security Recommendations

1. Prefer managed identity when running in Azure - no credentials to manage
2. Use workload identity in AKS instead of storing secrets in pods
3. For federation, validate the issuer and subject claims in Azure AD
4. Rotate static credentials regularly if you must use them
5. Use the narrowest possible scope for tokens
6. Monitor authentication failures through telemetry events
