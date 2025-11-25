defmodule ExAzureCore.Auth.OAuth2Test do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Auth.Errors.AzureAdStsError
  alias ExAzureCore.Auth.Errors.InvalidTokenFormat
  alias ExAzureCore.Auth.OAuth2
  alias ExAzureCore.Errors.NetworkError

  describe "get_token/4" do
    test "successfully exchanges assertion for access token" do
      tenant_id = "test-tenant"
      client_id = "test-client"
      assertion = "test-jwt-token"
      scope = "https://graph.microsoft.com/.default"

      expect(Req, :post, fn url, opts ->
        assert url == "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token"

        assert opts[:form] == %{
                 "grant_type" => "client_credentials",
                 "client_id" => client_id,
                 "client_assertion_type" =>
                   "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
                 "client_assertion" => assertion,
                 "scope" => scope
               }

        assert opts[:headers] == [{"Content-Type", "application/x-www-form-urlencoded"}]

        {:ok,
         %{
           status: 200,
           body: %{
             "access_token" => "eyJ0eXAiOiJKV1QiLCJhbGc...",
             "expires_in" => 3600,
             "token_type" => "Bearer",
             "scope" => scope
           }
         }}
      end)

      assert {:ok, token} = OAuth2.get_token(tenant_id, client_id, assertion, scope)
      assert token.access_token == "eyJ0eXAiOiJKV1QiLCJhbGc..."
      assert token.expires_in == 3600
      assert token.token_type == "Bearer"
      assert token.scope == scope
      assert is_integer(token.expires_at)
    end

    test "handles invalid client error" do
      expect(Req, :post, fn _url, _opts ->
        {:ok,
         %{
           status: 400,
           body: %{
             "error" => "invalid_client",
             "error_description" => "Client authentication failed",
             "error_codes" => []
           }
         }}
      end)

      assert {:error, %AzureAdStsError{type: :invalid_client}} =
               OAuth2.get_token("tenant", "client", "assertion", "scope")
    end

    test "handles invalid client error with AADSTS code" do
      expect(Req, :post, fn _url, _opts ->
        {:ok,
         %{
           status: 400,
           body: %{
             "error" => "invalid_client",
             "error_description" => "Client authentication failed",
             "error_codes" => [700_016]
           }
         }}
      end)

      assert {:error, %AzureAdStsError{type: :invalid_tenant_id}} =
               OAuth2.get_token("tenant", "client", "assertion", "scope")
    end

    test "handles invalid scope error" do
      expect(Req, :post, fn _url, _opts ->
        {:ok,
         %{
           status: 400,
           body: %{
             "error" => "invalid_scope",
             "error_description" => "The scope is not valid"
           }
         }}
      end)

      assert {:error, %AzureAdStsError{type: :invalid_scope}} =
               OAuth2.get_token("tenant", "client", "assertion", "scope")
    end

    test "handles network errors" do
      expect(Req, :post, fn _url, _opts ->
        {:error, %Mint.TransportError{reason: :nxdomain}}
      end)

      assert {:error, %NetworkError{}} =
               OAuth2.get_token("tenant", "client", "assertion", "scope")
    end

    test "handles AADSTS error codes" do
      test_cases = [
        {70021, :federation_trust_mismatch},
        {700_016, :invalid_tenant_id},
        {50027, :invalid_jwt},
        {700_027, :certificate_not_found}
      ]

      for {error_code, expected_type} <- test_cases do
        expect(Req, :post, fn _url, _opts ->
          {:ok,
           %{
             status: 400,
             body: %{
               "error" => "invalid_request",
               "error_description" => "Azure AD error",
               "error_codes" => [error_code]
             }
           }}
        end)

        assert {:error, %AzureAdStsError{type: ^expected_type}} =
                 OAuth2.get_token("tenant", "client", "assertion", "scope")
      end
    end
  end

  describe "token_endpoint/2" do
    test "returns correct endpoint for public cloud" do
      assert OAuth2.token_endpoint("tenant-id") ==
               "https://login.microsoftonline.com/tenant-id/oauth2/v2.0/token"

      assert OAuth2.token_endpoint("tenant-id", :public) ==
               "https://login.microsoftonline.com/tenant-id/oauth2/v2.0/token"
    end

    test "returns correct endpoint for government cloud" do
      assert OAuth2.token_endpoint("tenant-id", :government) ==
               "https://login.microsoftonline.us/tenant-id/oauth2/v2.0/token"
    end

    test "returns correct endpoint for china cloud" do
      assert OAuth2.token_endpoint("tenant-id", :china) ==
               "https://login.chinacloudapi.cn/tenant-id/oauth2/v2.0/token"
    end

    test "returns correct endpoint for germany cloud" do
      assert OAuth2.token_endpoint("tenant-id", :germany) ==
               "https://login.microsoftonline.de/tenant-id/oauth2/v2.0/token"
    end

    test "supports custom endpoint URL" do
      custom_url = "https://custom.azure.com"

      assert OAuth2.token_endpoint("tenant-id", custom_url) ==
               "#{custom_url}/tenant-id/oauth2/v2.0/token"
    end
  end

  describe "parse_token_response/1" do
    test "parses valid token response with all fields" do
      response = %{
        "access_token" => "token123",
        "expires_in" => 7200,
        "token_type" => "Bearer",
        "scope" => "User.Read"
      }

      assert {:ok, token} = OAuth2.parse_token_response(response)
      assert token.access_token == "token123"
      assert token.expires_in == 7200
      assert token.token_type == "Bearer"
      assert token.scope == "User.Read"
      assert is_integer(token.expires_at)
    end

    test "parses response with missing optional fields" do
      response = %{
        "access_token" => "token123",
        "expires_in" => 3600
      }

      assert {:ok, token} = OAuth2.parse_token_response(response)
      assert token.access_token == "token123"
      assert token.expires_in == 3600
      assert token.token_type == "Bearer"
      assert token.scope == nil
    end

    test "handles missing required fields" do
      response = %{"token_type" => "Bearer"}

      assert {:error, %InvalidTokenFormat{}} = OAuth2.parse_token_response(response)
    end

    test "handles invalid response format" do
      assert {:error, %InvalidTokenFormat{}} = OAuth2.parse_token_response("invalid")
    end

    test "handles string expires_in value" do
      response = %{
        "access_token" => "token123",
        "expires_in" => "3600"
      }

      assert {:ok, token} = OAuth2.parse_token_response(response)
      assert token.expires_in == "3600"
      assert is_integer(token.expires_at)
    end
  end
end
