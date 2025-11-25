defmodule ExAzureCore.Auth.TokenSource.ManagedIdentityTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Auth.Errors.ManagedIdentityError
  alias ExAzureCore.Auth.ManagedIdentity.AppServiceProvider
  alias ExAzureCore.Auth.ManagedIdentity.EnvironmentDetector
  alias ExAzureCore.Auth.ManagedIdentity.ImdsProvider
  alias ExAzureCore.Auth.TokenSource.ManagedIdentity

  describe "fetch_token/1 with explicit provider" do
    test "uses IMDS provider when provider: :imds" do
      config = %{resource: "https://management.azure.com/", provider: :imds}
      mock_token = mock_token_response()

      ImdsProvider
      |> expect(:fetch_token, fn ^config -> {:ok, mock_token} end)

      assert {:ok, token} = ManagedIdentity.fetch_token(config)
      assert token.access_token == mock_token.access_token
    end

    test "uses App Service provider when provider: :app_service" do
      config = %{resource: "https://management.azure.com/", provider: :app_service}
      mock_token = mock_token_response()

      AppServiceProvider
      |> expect(:fetch_token, fn ^config -> {:ok, mock_token} end)

      assert {:ok, token} = ManagedIdentity.fetch_token(config)
      assert token.access_token == mock_token.access_token
    end

    test "returns error for unknown provider" do
      config = %{resource: "https://management.azure.com/", provider: :unknown}

      assert {:error, %ManagedIdentityError{type: :provider_error}} =
               ManagedIdentity.fetch_token(config)
    end
  end

  describe "fetch_token/1 with auto-detection" do
    test "uses App Service when IDENTITY_ENDPOINT is available" do
      config = %{resource: "https://management.azure.com/"}
      mock_token = mock_token_response()

      EnvironmentDetector
      |> expect(:app_service_available?, fn -> true end)

      AppServiceProvider
      |> expect(:fetch_token, fn ^config -> {:ok, mock_token} end)

      assert {:ok, _token} = ManagedIdentity.fetch_token(config)
    end

    test "falls back to IMDS when App Service not available" do
      config = %{resource: "https://management.azure.com/"}
      mock_token = mock_token_response()

      EnvironmentDetector
      |> expect(:app_service_available?, fn -> false end)
      |> expect(:workload_identity_available?, fn -> false end)

      ImdsProvider
      |> expect(:fetch_token, fn ^config -> {:ok, mock_token} end)

      assert {:ok, _token} = ManagedIdentity.fetch_token(config)
    end

    test "returns helpful error when Workload Identity detected but using ManagedIdentity" do
      config = %{resource: "https://management.azure.com/"}

      EnvironmentDetector
      |> expect(:app_service_available?, fn -> false end)
      |> expect(:workload_identity_available?, fn -> true end)

      assert {:error, %ManagedIdentityError{type: :provider_error}} =
               ManagedIdentity.fetch_token(config)
    end
  end

  describe "fetch_token/1 error propagation" do
    test "propagates IMDS provider errors" do
      config = %{resource: "https://management.azure.com/", provider: :imds}

      error =
        ManagedIdentityError.exception(
          type: :imds_unavailable,
          provider: :imds,
          reason: "connection refused"
        )

      ImdsProvider
      |> expect(:fetch_token, fn _config -> {:error, error} end)

      assert {:error, %ManagedIdentityError{type: :imds_unavailable}} =
               ManagedIdentity.fetch_token(config)
    end
  end

  defp mock_token_response do
    %{
      access_token: "test-token-#{:rand.uniform(1000)}",
      expires_at: System.system_time(:second) + 3600,
      expires_in: 3600,
      token_type: "Bearer",
      scope: "https://management.azure.com/"
    }
  end
end
