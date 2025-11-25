defmodule ExAzureCore.Auth.ManagedIdentity.ImdsProviderTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Auth.Errors.ManagedIdentityError
  alias ExAzureCore.Auth.ManagedIdentity.ImdsProvider
  alias ExAzureCore.Errors.NetworkError

  describe "fetch_token/1" do
    test "successfully fetches token for system-assigned identity" do
      config = %{resource: "https://management.azure.com/"}
      expires_on = System.system_time(:second) + 3600

      Req
      |> expect(:get, fn url, opts ->
        assert url =~ "169.254.169.254"
        assert url =~ "resource=https%3A%2F%2Fmanagement.azure.com%2F"
        refute url =~ "client_id="
        assert {"Metadata", "true"} in opts[:headers]

        {:ok,
         %{
           status: 200,
           body: %{
             "access_token" => "test-token-123",
             "expires_on" => to_string(expires_on),
             "token_type" => "Bearer",
             "resource" => "https://management.azure.com/"
           }
         }}
      end)

      assert {:ok, token} = ImdsProvider.fetch_token(config)
      assert token.access_token == "test-token-123"
      assert token.token_type == "Bearer"
      assert token.expires_at == expires_on
    end

    test "includes client_id for user-assigned identity" do
      config = %{
        resource: "https://vault.azure.net/",
        client_id: "user-assigned-client-id"
      }

      Req
      |> expect(:get, fn url, _opts ->
        assert url =~ "client_id=user-assigned-client-id"

        {:ok,
         %{
           status: 200,
           body: %{
             "access_token" => "user-token",
             "expires_on" => to_string(System.system_time(:second) + 3600),
             "token_type" => "Bearer"
           }
         }}
      end)

      assert {:ok, token} = ImdsProvider.fetch_token(config)
      assert token.access_token == "user-token"
    end

    test "includes object_id when provided" do
      config = %{
        resource: "https://management.azure.com/",
        object_id: "object-id-123"
      }

      Req
      |> expect(:get, fn url, _opts ->
        assert url =~ "object_id=object-id-123"

        {:ok,
         %{
           status: 200,
           body: %{
             "access_token" => "token",
             "expires_on" => to_string(System.system_time(:second) + 3600),
             "token_type" => "Bearer"
           }
         }}
      end)

      assert {:ok, _token} = ImdsProvider.fetch_token(config)
    end

    test "returns error when resource is missing" do
      config = %{}

      assert {:error, %ManagedIdentityError{type: :provider_error}} =
               ImdsProvider.fetch_token(config)
    end

    test "handles IMDS 400 error responses" do
      config = %{resource: "https://management.azure.com/"}

      Req
      |> expect(:get, fn _url, _opts ->
        {:ok,
         %{
           status: 400,
           body: %{
             "error" => "invalid_request",
             "error_description" => "Identity not found"
           }
         }}
      end)

      assert {:error, %ManagedIdentityError{type: :provider_error, status: 400}} =
               ImdsProvider.fetch_token(config)
    end

    test "retries on 429 responses" do
      config = %{resource: "https://management.azure.com/"}
      call_count = :counters.new(1, [])

      Req
      |> stub(:get, fn _url, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count < 2 do
          {:ok, %{status: 429, headers: [{"Retry-After", "0"}], body: %{}}}
        else
          {:ok,
           %{
             status: 200,
             body: %{
               "access_token" => "token-after-retry",
               "expires_on" => to_string(System.system_time(:second) + 3600),
               "token_type" => "Bearer"
             }
           }}
        end
      end)

      assert {:ok, token} = ImdsProvider.fetch_token(config)
      assert token.access_token == "token-after-retry"
      assert :counters.get(call_count, 1) == 3
    end

    test "returns network error on connection failure" do
      config = %{resource: "https://management.azure.com/"}

      Req
      |> stub(:get, fn _url, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      assert {:error, %NetworkError{service: :azure_imds}} =
               ImdsProvider.fetch_token(config)
    end

    test "handles integer expires_in response" do
      config = %{resource: "https://management.azure.com/"}

      Req
      |> expect(:get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "access_token" => "token",
             "expires_in" => 3600,
             "token_type" => "Bearer"
           }
         }}
      end)

      assert {:ok, token} = ImdsProvider.fetch_token(config)
      assert token.expires_in == 3600
    end
  end
end
