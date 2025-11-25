defmodule ExAzureCore.Auth.TokenServerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExAzureCore.Auth.Errors.ConfigurationError
  alias ExAzureCore.Auth.TokenServer
  alias ExAzureCore.Auth.TokenSource.ClientAssertion

  setup :set_mimic_from_context

  describe "start_link/1" do
    test "starts a token server with sync prefetch" do
      config = %{test: "config"}

      mock_token = %{
        access_token: "test-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ClientAssertion
      |> expect(:fetch_token, fn ^config -> {:ok, mock_token} end)

      assert {:ok, _pid} =
               TokenServer.start_link(
                 name: :test_credential_sync,
                 source: {:client_assertion, config},
                 prefetch: :sync
               )

      assert {:ok, token} = TokenServer.fetch(:test_credential_sync)
      assert token.access_token == "test-token"
    end

    test "starts a token server with async prefetch" do
      config = %{test: "async-config"}

      mock_token = %{
        access_token: "test-token-async",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ClientAssertion
      |> stub(:fetch_token, fn ^config -> {:ok, mock_token} end)

      assert {:ok, _pid} =
               TokenServer.start_link(
                 name: :test_credential_async,
                 source: {:client_assertion, config},
                 prefetch: :async
               )

      Process.sleep(100)

      assert {:ok, token} = TokenServer.fetch(:test_credential_async)
      assert token.access_token == "test-token-async"
    end

    test "returns error for invalid prefetch option" do
      config = %{test: "invalid-config"}

      Process.flag(:trap_exit, true)

      assert {:error, %ConfigurationError{type: :invalid_option, key: :prefetch}} =
               TokenServer.start_link(
                 name: :test_credential_invalid,
                 source: {:client_assertion, config},
                 prefetch: :invalid
               )
    end
  end

  describe "fetch/1" do
    test "fetches token on demand if not cached" do
      config = %{test: "on-demand-config"}

      mock_token = %{
        access_token: "on-demand-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ClientAssertion
      |> stub(:fetch_token, fn ^config -> {:ok, mock_token} end)

      {:ok, _pid} =
        TokenServer.start_link(
          name: :test_on_demand,
          source: {:client_assertion, config},
          prefetch: :async
        )

      assert {:ok, token} = TokenServer.fetch(:test_on_demand)
      assert token.access_token == "on-demand-token"
    end

    test "returns cached token if available" do
      config = %{test: "cached-config"}

      call_count = :counters.new(1, [])

      mock_token = %{
        access_token: "cached-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ClientAssertion
      |> stub(:fetch_token, fn ^config ->
        :counters.add(call_count, 1, 1)
        {:ok, mock_token}
      end)

      {:ok, _pid} =
        TokenServer.start_link(
          name: :test_cached,
          source: {:client_assertion, config},
          prefetch: :sync
        )

      assert {:ok, token1} = TokenServer.fetch(:test_cached)
      assert {:ok, token2} = TokenServer.fetch(:test_cached)

      assert token1.access_token == "cached-token"
      assert token2.access_token == "cached-token"
      assert :counters.get(call_count, 1) == 1
    end
  end

  describe "automatic refresh" do
    test "schedules refresh before token expiry" do
      config = %{test: "refresh-config"}

      short_lived_token = %{
        access_token: "short-lived-token",
        expires_at: System.system_time(:second) + 2,
        expires_in: 2,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      refreshed_token = %{
        access_token: "refreshed-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      call_count = :counters.new(1, [])

      ClientAssertion
      |> stub(:fetch_token, fn ^config ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:ok, short_lived_token}
        else
          {:ok, refreshed_token}
        end
      end)

      {:ok, _pid} =
        TokenServer.start_link(
          name: :test_refresh,
          source: {:client_assertion, config},
          prefetch: :sync,
          refresh_before: 1
        )

      assert {:ok, token1} = TokenServer.fetch(:test_refresh)
      assert token1.access_token == "short-lived-token"

      Process.sleep(2000)

      assert {:ok, token2} = TokenServer.fetch(:test_refresh)
      assert token2.access_token == "refreshed-token"
    end
  end

  describe "retry logic" do
    test "retries with exponential backoff on failure" do
      config = %{test: "retry-config"}

      call_count = :counters.new(1, [])

      success_token = %{
        access_token: "retry-success-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ClientAssertion
      |> stub(:fetch_token, fn ^config ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count < 2 do
          {:error, "temporary failure"}
        else
          {:ok, success_token}
        end
      end)

      {:ok, _pid} =
        TokenServer.start_link(
          name: :test_retry,
          source: {:client_assertion, config},
          prefetch: :async,
          max_retries: 5
        )

      Process.sleep(5000)

      assert {:ok, token} = TokenServer.fetch(:test_retry)
      assert token.access_token == "retry-success-token"
      assert :counters.get(call_count, 1) >= 3
    end
  end
end
