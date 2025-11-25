defmodule ExAzureCore.Auth.TokenSource.WorkloadIdentityTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Auth.Errors.ManagedIdentityError
  alias ExAzureCore.Auth.OAuth2
  alias ExAzureCore.Auth.TokenSource.WorkloadIdentity

  @test_token_content "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.test-token-content"

  describe "fetch_token/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      token_file = Path.join(tmp_dir, "test-token-#{:rand.uniform(10000)}")
      File.write!(token_file, @test_token_content)

      on_exit(fn -> File.rm(token_file) end)

      %{token_file: token_file}
    end

    test "successfully exchanges token with explicit config", %{token_file: token_file} do
      config = %{
        scope: "https://management.azure.com/.default",
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        token_file_path: token_file
      }

      mock_token = mock_token_response()

      OAuth2
      |> expect(:get_token, fn tenant_id, client_id, assertion, scope, cloud ->
        assert tenant_id == "test-tenant-id"
        assert client_id == "test-client-id"
        assert assertion == @test_token_content
        assert scope == "https://management.azure.com/.default"
        assert cloud == :public
        {:ok, mock_token}
      end)

      assert {:ok, token} = WorkloadIdentity.fetch_token(config)
      assert token.access_token == mock_token.access_token
    end

    test "uses custom cloud when specified", %{token_file: token_file} do
      config = %{
        scope: "https://management.azure.com/.default",
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        token_file_path: token_file,
        cloud: :government
      }

      OAuth2
      |> expect(:get_token, fn _tenant, _client, _assertion, _scope, cloud ->
        assert cloud == :government
        {:ok, mock_token_response()}
      end)

      assert {:ok, _token} = WorkloadIdentity.fetch_token(config)
    end

    test "returns error when scope is missing" do
      config = %{
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        token_file_path: "/some/path"
      }

      assert {:error, %ManagedIdentityError{type: :provider_error}} =
               WorkloadIdentity.fetch_token(config)
    end

    test "returns error when token file does not exist" do
      config = %{
        scope: "https://management.azure.com/.default",
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        token_file_path: "/nonexistent/path/token"
      }

      assert {:error, %ManagedIdentityError{type: :token_file_not_found}} =
               WorkloadIdentity.fetch_token(config)
    end

    test "returns error when token file is empty", %{token_file: token_file} do
      File.write!(token_file, "")

      config = %{
        scope: "https://management.azure.com/.default",
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        token_file_path: token_file
      }

      assert {:error, %ManagedIdentityError{type: :token_file_read_error}} =
               WorkloadIdentity.fetch_token(config)
    end

    test "trims whitespace from token file content", %{token_file: token_file} do
      File.write!(token_file, "  #{@test_token_content}  \n")

      config = %{
        scope: "https://management.azure.com/.default",
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        token_file_path: token_file
      }

      OAuth2
      |> expect(:get_token, fn _tenant, _client, assertion, _scope, _cloud ->
        assert assertion == @test_token_content
        {:ok, mock_token_response()}
      end)

      assert {:ok, _token} = WorkloadIdentity.fetch_token(config)
    end

    test "propagates OAuth2 errors", %{token_file: token_file} do
      config = %{
        scope: "https://management.azure.com/.default",
        tenant_id: "test-tenant-id",
        client_id: "test-client-id",
        token_file_path: token_file
      }

      OAuth2
      |> expect(:get_token, fn _tenant, _client, _assertion, _scope, _cloud ->
        {:error, %{error: "invalid_client"}}
      end)

      assert {:error, %{error: "invalid_client"}} = WorkloadIdentity.fetch_token(config)
    end
  end

  describe "fetch_token/1 with environment variables" do
    setup do
      tmp_dir = System.tmp_dir!()
      token_file = Path.join(tmp_dir, "test-token-#{:rand.uniform(10000)}")
      File.write!(token_file, @test_token_content)

      old_tenant = System.get_env("AZURE_TENANT_ID")
      old_client = System.get_env("AZURE_CLIENT_ID")
      old_token_file = System.get_env("AZURE_FEDERATED_TOKEN_FILE")

      System.put_env("AZURE_TENANT_ID", "env-tenant-id")
      System.put_env("AZURE_CLIENT_ID", "env-client-id")
      System.put_env("AZURE_FEDERATED_TOKEN_FILE", token_file)

      on_exit(fn ->
        File.rm(token_file)

        if old_tenant,
          do: System.put_env("AZURE_TENANT_ID", old_tenant),
          else: System.delete_env("AZURE_TENANT_ID")

        if old_client,
          do: System.put_env("AZURE_CLIENT_ID", old_client),
          else: System.delete_env("AZURE_CLIENT_ID")

        if old_token_file,
          do: System.put_env("AZURE_FEDERATED_TOKEN_FILE", old_token_file),
          else: System.delete_env("AZURE_FEDERATED_TOKEN_FILE")
      end)

      %{token_file: token_file}
    end

    test "reads configuration from environment variables" do
      config = %{scope: "https://management.azure.com/.default"}

      OAuth2
      |> expect(:get_token, fn tenant_id, client_id, _assertion, _scope, _cloud ->
        assert tenant_id == "env-tenant-id"
        assert client_id == "env-client-id"
        {:ok, mock_token_response()}
      end)

      assert {:ok, _token} = WorkloadIdentity.fetch_token(config)
    end

    test "explicit config overrides environment variables", %{token_file: token_file} do
      config = %{
        scope: "https://management.azure.com/.default",
        tenant_id: "explicit-tenant",
        client_id: "explicit-client",
        token_file_path: token_file
      }

      OAuth2
      |> expect(:get_token, fn tenant_id, client_id, _assertion, _scope, _cloud ->
        assert tenant_id == "explicit-tenant"
        assert client_id == "explicit-client"
        {:ok, mock_token_response()}
      end)

      assert {:ok, _token} = WorkloadIdentity.fetch_token(config)
    end
  end

  defp mock_token_response do
    %{
      access_token: "azure-ad-token-#{:rand.uniform(1000)}",
      expires_at: System.system_time(:second) + 3600,
      expires_in: 3600,
      token_type: "Bearer",
      scope: "https://management.azure.com/.default"
    }
  end
end
