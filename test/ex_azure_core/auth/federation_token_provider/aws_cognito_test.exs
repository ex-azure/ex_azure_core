defmodule ExAzureCore.Auth.FederationTokenProvider.AwsCognitoTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAws.CognitoIdentity
  alias ExAzureCore.Auth.Errors.ConfigurationError
  alias ExAzureCore.Auth.Errors.FederationError
  alias ExAzureCore.Auth.FederationTokenProvider.AwsCognito

  describe "get_token/2 with basic auth" do
    test "fetches token using basic authentication" do
      identity_id = "us-east-1:12345678-1234-1234-1234-123456789012"

      expect(CognitoIdentity, :get_open_id_token, fn ^identity_id ->
        %ExAws.Operation.JSON{
          data: %{},
          headers: [],
          http_method: :post,
          params: %{},
          path: "/",
          service: :cognito_identity,
          stream_builder: nil
        }
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{"Token" => "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."}}
      end)

      assert {:ok, token} = AwsCognito.get_token(identity_id, auth_type: :basic)
      assert token == "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
    end

    test "handles error from basic auth" do
      identity_id = "invalid-identity"

      expect(CognitoIdentity, :get_open_id_token, fn ^identity_id ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:error, {:http_error, 400, %{"message" => "Invalid identity"}}}
      end)

      assert {:error, %FederationError{type: :token_fetch_failed, provider: :aws_cognito}} =
               AwsCognito.get_token(identity_id, auth_type: :basic)
    end
  end

  describe "get_token/2 with enhanced auth" do
    test "fetches token using enhanced authentication with map logins" do
      pool_id = "us-east-1:12345678-1234-1234-1234-123456789012"
      logins = %{"provider.com" => "token123"}

      expect(CognitoIdentity, :get_open_id_token_for_developer_identity, fn ^pool_id,
                                                                            ^logins,
                                                                            _opts ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{"Token" => "enhanced-token"}}
      end)

      assert {:ok, token} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced, logins: logins)

      assert token == "enhanced-token"
    end

    test "fetches token using enhanced authentication with string logins" do
      pool_id = "us-east-1:12345678-1234-1234-1234-123456789012"
      logins_string = "provider1.com=token1, provider2.com=token2"

      expected_logins = %{
        "provider1.com" => "token1",
        "provider2.com" => "token2"
      }

      expect(CognitoIdentity, :get_open_id_token_for_developer_identity, fn ^pool_id,
                                                                            ^expected_logins,
                                                                            _opts ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{"Token" => "enhanced-token"}}
      end)

      assert {:ok, _token} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced, logins: logins_string)
    end

    test "omits IdentityId when no cognito_identity_id is given" do
      pool_id = "us-east-1:pool-guid"
      logins = %{"provider.com" => "token123"}

      expect(CognitoIdentity, :get_open_id_token_for_developer_identity, fn ^pool_id,
                                                                            ^logins,
                                                                            [] ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{"Token" => "enhanced-token"}}
      end)

      assert {:ok, "enhanced-token"} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced, logins: logins)
    end

    test "pins the Cognito IdentityId when cognito_identity_id is given" do
      pool_id = "us-east-1:pool-guid"
      cognito_identity_id = "us-east-1:12345678-1234-1234-1234-123456789012"
      logins = %{"provider.com" => "token123"}

      expect(CognitoIdentity, :get_open_id_token_for_developer_identity, fn ^pool_id,
                                                                            ^logins,
                                                                            [
                                                                              identity_id:
                                                                                ^cognito_identity_id
                                                                            ] ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{"Token" => "pinned-token"}}
      end)

      assert {:ok, "pinned-token"} =
               AwsCognito.get_token(pool_id,
                 auth_type: :enhanced,
                 logins: logins,
                 cognito_identity_id: cognito_identity_id
               )
    end

    test "handles missing logins for enhanced auth" do
      pool_id = "us-east-1:12345678-1234-1234-1234-123456789012"

      assert {:error, %ConfigurationError{type: :missing_required, key: :logins}} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced)
    end

    test "handles invalid logins format" do
      pool_id = "us-east-1:12345678-1234-1234-1234-123456789012"

      assert {:error, %ConfigurationError{type: :invalid_value, key: :logins}} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced, logins: 123)
    end

    test "handles error from enhanced auth" do
      pool_id = "us-east-1:12345678-1234-1234-1234-123456789012"
      logins = %{"provider.com" => "token"}

      expect(CognitoIdentity, :get_open_id_token_for_developer_identity, fn ^pool_id,
                                                                            ^logins,
                                                                            _opts ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:error, {:http_error, 403, %{"message" => "Unauthorized"}}}
      end)

      assert {:error, %FederationError{type: :token_fetch_failed, provider: :aws_cognito}} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced, logins: logins)
    end
  end

  describe "login string parsing" do
    test "parses comma-separated login pairs" do
      pool_id = "test-id"
      logins_string = "provider1=token1,provider2=token2,provider3=token3"

      expected_logins = %{
        "provider1" => "token1",
        "provider2" => "token2",
        "provider3" => "token3"
      }

      expect(CognitoIdentity, :get_open_id_token_for_developer_identity, fn ^pool_id,
                                                                            ^expected_logins,
                                                                            _opts ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{"Token" => "test-token"}}
      end)

      assert {:ok, _token} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced, logins: logins_string)
    end

    test "handles login strings with spaces" do
      pool_id = "test-id"
      logins_string = " provider1 = token1 , provider2 = token2 "

      expected_logins = %{
        "provider1" => "token1",
        "provider2" => "token2"
      }

      expect(CognitoIdentity, :get_open_id_token_for_developer_identity, fn ^pool_id,
                                                                            ^expected_logins,
                                                                            _opts ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{"Token" => "test-token"}}
      end)

      assert {:ok, _token} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced, logins: logins_string)
    end

    test "ignores malformed login entries" do
      pool_id = "test-id"
      logins_string = "valid=token,invalid_no_equals,another_valid=token2"

      expected_logins = %{
        "valid" => "token",
        "another_valid" => "token2"
      }

      expect(CognitoIdentity, :get_open_id_token_for_developer_identity, fn ^pool_id,
                                                                            ^expected_logins,
                                                                            _opts ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{"Token" => "test-token"}}
      end)

      assert {:ok, _token} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced, logins: logins_string)
    end

    test "handles empty login string" do
      pool_id = "test-id"
      logins_string = ""
      expected_logins = %{}

      expect(CognitoIdentity, :get_open_id_token_for_developer_identity, fn ^pool_id,
                                                                            ^expected_logins,
                                                                            _opts ->
        %ExAws.Operation.JSON{}
      end)

      expect(ExAws, :request, fn _operation ->
        {:ok, %{"Token" => "test-token"}}
      end)

      assert {:ok, _token} =
               AwsCognito.get_token(pool_id, auth_type: :enhanced, logins: logins_string)
    end
  end
end
