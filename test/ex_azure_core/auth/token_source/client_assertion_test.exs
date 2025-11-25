defmodule ExAzureCore.Auth.TokenSource.ClientAssertionTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Auth.Errors.AzureAdStsError
  alias ExAzureCore.Auth.Errors.ConfigurationError
  alias ExAzureCore.Auth.TokenSource.ClientAssertion

  describe "fetch_token/1" do
    test "successfully fetches token with complete config" do
      config = %{
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        scope: "https://graph.microsoft.com/.default",
        provider: :aws_cognito,
        provider_opts: [identity_id: "test-identity-id", auth_type: :basic],
        cloud: :public
      }

      mock_token = %{
        access_token: "test-access-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ExAzureCore.Auth.FederatedTokenProvider
      |> expect(:get_token, fn :aws_cognito, opts ->
        assert opts[:identity_id] == "test-identity-id"
        assert opts[:auth_type] == :basic
        {:ok, "federated-jwt-token"}
      end)

      ExAzureCore.Auth.OAuth2
      |> expect(:get_token, fn tenant_id, client_id, assertion, scope, cloud ->
        assert tenant_id == "test-tenant-id"
        assert client_id == "test-client-id"
        assert assertion == "federated-jwt-token"
        assert scope == "https://graph.microsoft.com/.default"
        assert cloud == :public
        {:ok, mock_token}
      end)

      assert {:ok, token} = ClientAssertion.fetch_token(config)
      assert token.access_token == "test-access-token"
      assert token.token_type == "Bearer"
    end

    test "uses default cloud when not specified" do
      config = %{
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        scope: "https://graph.microsoft.com/.default",
        provider: :aws_cognito
      }

      mock_token = %{
        access_token: "test-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ExAzureCore.Auth.FederatedTokenProvider
      |> stub(:get_token, fn :aws_cognito, _opts -> {:ok, "federated-token"} end)

      ExAzureCore.Auth.OAuth2
      |> expect(:get_token, fn _tenant, _client, _assertion, _scope, cloud ->
        assert cloud == :public
        {:ok, mock_token}
      end)

      assert {:ok, _token} = ClientAssertion.fetch_token(config)
    end

    test "returns error when tenant_id is missing" do
      config = %{
        client_id: "test-client-id",
        scope: "https://graph.microsoft.com/.default",
        provider: :aws_cognito
      }

      assert {:error, %ConfigurationError{type: :missing_required, key: :tenant_id}} =
               ClientAssertion.fetch_token(config)
    end

    test "returns error when client_id is missing" do
      config = %{
        tenant_id: "test-tenant-id",
        scope: "https://graph.microsoft.com/.default",
        provider: :aws_cognito
      }

      assert {:error, %ConfigurationError{type: :missing_required, key: :client_id}} =
               ClientAssertion.fetch_token(config)
    end

    test "returns error when scope is missing" do
      config = %{
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        provider: :aws_cognito
      }

      assert {:error, %ConfigurationError{type: :missing_required, key: :scope}} =
               ClientAssertion.fetch_token(config)
    end

    test "returns error when provider is missing" do
      config = %{
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        scope: "https://graph.microsoft.com/.default"
      }

      assert {:error, %ConfigurationError{type: :missing_required, key: :provider}} =
               ClientAssertion.fetch_token(config)
    end

    test "propagates federated token provider errors" do
      config = %{
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        scope: "https://graph.microsoft.com/.default",
        provider: :aws_cognito
      }

      ExAzureCore.Auth.FederatedTokenProvider
      |> stub(:get_token, fn :aws_cognito, _opts ->
        {:error, "Cognito authentication failed"}
      end)

      assert {:error, "Cognito authentication failed"} = ClientAssertion.fetch_token(config)
    end

    test "propagates OAuth2 errors" do
      config = %{
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        scope: "https://graph.microsoft.com/.default",
        provider: :aws_cognito
      }

      ExAzureCore.Auth.FederatedTokenProvider
      |> stub(:get_token, fn :aws_cognito, _opts -> {:ok, "federated-token"} end)

      ExAzureCore.Auth.OAuth2
      |> stub(:get_token, fn _tenant, _client, _assertion, _scope, _cloud ->
        {:error,
         %AzureAdStsError{
           type: :invalid_client,
           error_code: :unknown,
           description: "Client not found"
         }}
      end)

      assert {:error, %AzureAdStsError{type: :invalid_client}} =
               ClientAssertion.fetch_token(config)
    end

    test "passes provider_opts to federated token provider" do
      config = %{
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        scope: "https://graph.microsoft.com/.default",
        provider: :aws_cognito,
        provider_opts: [
          identity_id: "specific-identity",
          auth_type: :enhanced,
          logins: %{"provider" => "token"}
        ]
      }

      mock_token = %{
        access_token: "test-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ExAzureCore.Auth.FederatedTokenProvider
      |> expect(:get_token, fn :aws_cognito, opts ->
        assert opts[:identity_id] == "specific-identity"
        assert opts[:auth_type] == :enhanced
        assert opts[:logins] == %{"provider" => "token"}
        {:ok, "federated-token"}
      end)

      ExAzureCore.Auth.OAuth2
      |> stub(:get_token, fn _tenant, _client, _assertion, _scope, _cloud ->
        {:ok, mock_token}
      end)

      assert {:ok, _token} = ClientAssertion.fetch_token(config)
    end
  end
end
