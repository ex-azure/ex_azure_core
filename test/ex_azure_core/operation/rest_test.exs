defmodule ExAzureCore.Operation.RESTTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Operation
  alias ExAzureCore.Operation.REST

  describe "perform/2 base URL resolution" do
    test "operation.host wins over config.base_url" do
      expect(Req, :request, fn client, _opts ->
        assert client.options[:base_url] == "https://op-host.example.com"
        {:ok, %Req.Response{status: 200, headers: [], body: %{}}}
      end)

      operation = %REST{
        service: :storage,
        http_method: :get,
        path: "/test",
        host: "op-host.example.com"
      }

      config = %{base_url: "https://config-base.example.com"}

      assert {:ok, _} = Operation.perform(operation, config)
    end

    test "config.base_url wins over default_host" do
      expect(Req, :request, fn client, _opts ->
        assert client.options[:base_url] == "https://config-base.example.com"
        {:ok, %Req.Response{status: 200, headers: [], body: %{}}}
      end)

      operation = %REST{
        service: :storage,
        http_method: :get,
        path: "/test",
        default_host: "default-host.example.com"
      }

      config = %{base_url: "https://config-base.example.com"}

      assert {:ok, _} = Operation.perform(operation, config)
    end

    test "default_host is used when no operation.host or config base_url/host is set" do
      expect(Req, :request, fn client, _opts ->
        assert client.options[:base_url] == "https://default-host.example.com"
        {:ok, %Req.Response{status: 200, headers: [], body: %{}}}
      end)

      operation = %REST{
        service: :storage,
        http_method: :get,
        path: "/test",
        default_host: "default-host.example.com"
      }

      assert {:ok, _} = Operation.perform(operation, %{})
    end
  end
end
