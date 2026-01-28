# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ExAzureCore is the base library for Azure SDKs in Elixir. It provides authentication, HTTP client infrastructure, and common utilities that service-specific Azure SDKs build upon.

## Commands

```bash
# Run all tests
mix test

# Run a single test file
mix test test/ex_azure_core/auth/token_server_test.exs

# Run tests matching a pattern
mix test --only integration

# Code quality
mix format              # Format code
mix credo               # Lint
mix dialyzer            # Type checking
mix sobelow             # Security scanning
mix recode              # Additional style checks

# All checks at once
mix check
```

## Architecture

### Request Flow

```
ExAzureCore.request(operation) → Config Resolution → HTTP Client + Plugins → Azure REST API
```

The library uses a protocol-based design where service SDKs define operations implementing `ExAzureCore.Operation`.

### Key Modules

- **`ExAzureCore`** - Public API (`request/2`, `request!/2`, `stream!/2`)
- **`ExAzureCore.Config`** - 4-level config hierarchy (defaults → global → service → per-request)
- **`ExAzureCore.Operation`** - Protocol for service operations; `Operation.REST` is the main implementation
- **`ExAzureCore.Http.Client`** - Req-based HTTP client with plugin architecture

### Authentication System

Token management uses GenServers registered in `ExAzureCore.Auth.Registry`:

- **`Auth.TokenServer`** - Manages token lifecycle with proactive refresh before expiry
- **`Auth.TokenSource`** - Behavior for token fetching strategies:
  - `TokenSource.ClientAssertion` - Federation (AWS Cognito, GitHub Actions, K8s)
  - `TokenSource.ManagedIdentity` - Azure managed identity (IMDS, App Service, AKS)
  - `TokenSource.WorkloadIdentity` - AKS workload identity

### HTTP Plugins (`Http.Plugins.*`)

Plugins compose into the request pipeline:
- `BearerToken` / `ApiKey` / `SasToken` / `SharedKey` - Auth methods
- `AzureHeaders` - Adds `x-ms-version`, `x-ms-date`
- `Retry` - Exponential backoff for transient failures (408, 429, 5xx)
- `ErrorHandler` - Transforms HTTP errors to Splode errors

### Credentials

Three credential types (mirrors Azure Python SDK):
- `AzureKeyCredential` - API keys
- `AzureSasCredential` - SAS tokens
- `AzureNamedKeyCredential` - Account name + key pairs

### Error Handling

Uses Splode for structured errors. Error modules are in `ExAzureCore.Errors.*` and `ExAzureCore.Auth.Errors.*`.

## Testing

Tests use Mimic for mocking. All mockable modules are registered in `test/test_helper.exs`. Most auth tests use `async: false` due to shared Registry state.

Pattern for mocking:
```elixir
use ExUnit.Case, async: false
use Mimic

setup :set_mimic_from_context
```
