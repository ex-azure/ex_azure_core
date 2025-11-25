defmodule ExAzureCore.Auth.FederatedTokenProviderTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Auth.Errors.FederationError
  alias ExAzureCore.Auth.FederatedTokenProvider
  alias ExAzureCore.Auth.FederationTokenProvider.AwsCognito

  describe "get_token/2" do
    test "dispatches to AWS Cognito provider" do
      identity_id = "test-identity"
      opts = [identity_id: identity_id, auth_type: :basic]

      expect(AwsCognito, :get_token, fn ^identity_id, received_opts ->
        assert received_opts[:auth_type] == :basic
        {:ok, "test-token"}
      end)

      assert {:ok, "test-token"} = FederatedTokenProvider.get_token(:aws_cognito, opts)
    end

    test "extracts identity_id from opts" do
      identity_id = "extracted-identity"
      opts = [identity_id: identity_id, other_option: "value"]

      expect(AwsCognito, :get_token, fn ^identity_id, received_opts ->
        assert received_opts[:other_option] == "value"
        refute Keyword.has_key?(received_opts, :identity_id)
        {:ok, "test-token"}
      end)

      assert {:ok, "test-token"} = FederatedTokenProvider.get_token(:aws_cognito, opts)
    end

    test "handles missing identity_id with empty string" do
      opts = [auth_type: :basic]

      expect(AwsCognito, :get_token, fn identity_id, _opts ->
        assert identity_id == ""
        {:ok, "test-token"}
      end)

      assert {:ok, "test-token"} = FederatedTokenProvider.get_token(:aws_cognito, opts)
    end

    test "returns error for unknown provider" do
      opts = [identity_id: "test"]

      assert {:error, %FederationError{type: :unknown_provider, provider: :unknown}} =
               FederatedTokenProvider.get_token(:unknown, opts)
    end

    test "propagates errors from provider" do
      opts = [identity_id: "test"]

      expect(AwsCognito, :get_token, fn _id, _opts ->
        {:error, "Provider error"}
      end)

      assert {:error, "Provider error"} =
               FederatedTokenProvider.get_token(:aws_cognito, opts)
    end
  end
end
