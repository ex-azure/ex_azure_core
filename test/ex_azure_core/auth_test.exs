defmodule ExAzureCore.AuthTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExAzureCore.Auth
  alias ExAzureCore.Auth.Errors.TokenServerError
  alias ExAzureCore.Auth.TokenSource.ClientAssertion

  setup :set_mimic_from_context

  describe "start_link/1" do
    test "starts a credential server successfully" do
      config = %{test: "integration-config"}

      mock_token = %{
        access_token: "integration-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ClientAssertion
      |> expect(:fetch_token, 1, fn ^config -> {:ok, mock_token} end)

      assert {:ok, _pid} =
               Auth.start_link(
                 name: :integration_test_credential,
                 source: {:client_assertion, config},
                 prefetch: :sync
               )
    end

    test "returns error when name is missing" do
      config = %{test: "no-name-config"}

      assert_raise KeyError, ~r/key :name not found/, fn ->
        Auth.start_link(source: {:client_assertion, config})
      end
    end

    test "returns error when source is missing" do
      Process.flag(:trap_exit, true)

      assert {:error, _} =
               Auth.start_link(name: :test_no_source)
    end
  end

  describe "fetch/1" do
    test "fetches token from credential server" do
      config = %{test: "fetch-test-config"}

      mock_token = %{
        access_token: "fetch-test-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ClientAssertion
      |> stub(:fetch_token, fn ^config -> {:ok, mock_token} end)

      {:ok, _pid} =
        Auth.start_link(
          name: :fetch_test_credential,
          source: {:client_assertion, config},
          prefetch: :sync
        )

      assert {:ok, token} = Auth.fetch(:fetch_test_credential)
      assert token.access_token == "fetch-test-token"
      assert token.token_type == "Bearer"
      assert token.expires_at > System.system_time(:second)
    end
  end

  describe "fetch!/1" do
    test "fetches token and returns it directly" do
      config = %{test: "fetch-bang-config"}

      mock_token = %{
        access_token: "fetch-bang-token",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      ClientAssertion
      |> stub(:fetch_token, fn ^config -> {:ok, mock_token} end)

      {:ok, _pid} =
        Auth.start_link(
          name: :fetch_bang_credential,
          source: {:client_assertion, config},
          prefetch: :sync
        )

      token = Auth.fetch!(:fetch_bang_credential)
      assert token.access_token == "fetch-bang-token"
    end

    test "raises on error when no token is available" do
      assert_raise TokenServerError, fn ->
        Auth.fetch!(:nonexistent_credential)
      end
    end
  end

  describe "child_spec/1" do
    test "returns a valid child spec" do
      config = %{test: "child-spec-config"}

      spec =
        Auth.child_spec(
          name: :child_spec_test,
          source: {:client_assertion, config}
        )

      assert spec.id == :child_spec_test
      assert spec.type == :worker
      assert spec.restart == :permanent
      assert {Auth, :start_link, _} = spec.start
    end

    test "uses module name as default id" do
      config = %{test: "default-id-config"}

      spec = Auth.child_spec(source: {:client_assertion, config})

      assert spec.id == Auth
    end
  end

  describe "multiple concurrent credentials" do
    test "supports multiple independent credential instances" do
      config1 = %{test: "multi-1"}
      config2 = %{test: "multi-2"}

      token1 = %{
        access_token: "token-1",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://graph.microsoft.com/.default"
      }

      token2 = %{
        access_token: "token-2",
        expires_at: System.system_time(:second) + 3600,
        expires_in: 3600,
        token_type: "Bearer",
        scope: "https://storage.azure.com/.default"
      }

      ClientAssertion
      |> stub(:fetch_token, fn
        ^config1 -> {:ok, token1}
        ^config2 -> {:ok, token2}
      end)

      {:ok, _pid1} =
        Auth.start_link(
          name: :multi_cred_1,
          source: {:client_assertion, config1},
          prefetch: :sync
        )

      {:ok, _pid2} =
        Auth.start_link(
          name: :multi_cred_2,
          source: {:client_assertion, config2},
          prefetch: :sync
        )

      assert {:ok, t1} = Auth.fetch(:multi_cred_1)
      assert {:ok, t2} = Auth.fetch(:multi_cred_2)

      assert t1.access_token == "token-1"
      assert t2.access_token == "token-2"
    end
  end
end
