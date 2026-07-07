defmodule ExAzureCore.LroTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Lro
  alias ExAzureCore.Operation.REST

  defp op do
    %REST{
      service: :storage,
      http_method: :put,
      path: "/pets/1",
      default_host: "petstore.example.com",
      body: %{"name" => "rex"}
    }
  end

  # No Retry-After header and delay_ms: 0 keep the tests instant.
  defp resp(status, headers, body) do
    {:ok, %Req.Response{status: status, headers: headers, body: body}}
  end

  test "polls the status monitor until Succeeded, then GETs the original URI" do
    # 1. initial PUT -> 201 + Operation-Location
    expect(Req, :request, fn _client, _opts ->
      resp(201, [{"operation-location", "https://petstore.example.com/lro/op1"}], %{})
    end)

    # 2. poll -> Running
    expect(Req, :request, fn client, _opts ->
      assert client.options[:base_url] == "https://petstore.example.com"
      resp(200, [], %{"status" => "Running"})
    end)

    # 3. poll -> Succeeded
    expect(Req, :request, fn _client, _opts ->
      resp(200, [], %{"status" => "Succeeded"})
    end)

    # 4. final GET on original URI -> the resource
    expect(Req, :request, fn client, opts ->
      assert client.options[:base_url] == "https://petstore.example.com"
      assert opts[:method] == :get
      resp(200, [], %{"id" => 1, "name" => "rex"})
    end)

    assert {:ok, %{"id" => 1, "name" => "rex"}} =
             Lro.run(%{}, op(),
               status_path: "status",
               final: :original_uri,
               delay_ms: 0,
               decode: & &1
             )
  end

  test "resolves the result from the terminal poll body when final: :poll_body" do
    expect(Req, :request, fn _client, _opts ->
      resp(202, [{"operation-location", "https://petstore.example.com/lro/op2"}], %{})
    end)

    expect(Req, :request, fn _client, _opts ->
      resp(200, [], %{"status" => "Succeeded", "id" => 7})
    end)

    assert {:ok, %{"status" => "Succeeded", "id" => 7}} =
             Lro.run(%{}, op(), final: :poll_body, delay_ms: 0)
  end

  test "returns an error tuple on a failed terminal state" do
    expect(Req, :request, fn _client, _opts ->
      resp(201, [{"operation-location", "https://petstore.example.com/lro/op3"}], %{})
    end)

    expect(Req, :request, fn _client, _opts ->
      resp(200, [], %{"status" => "Failed", "error" => %{"code" => "boom"}})
    end)

    assert {:error, {:lro_failed, "Failed", %{"error" => %{"code" => "boom"}}}} =
             Lro.run(%{}, op(), final: :original_uri, delay_ms: 0)
  end

  test "completes synchronously when the initial response has no status-monitor header" do
    expect(Req, :request, fn _client, _opts ->
      resp(200, [], %{"id" => 9, "name" => "sync"})
    end)

    assert {:ok, %{"id" => 9, "name" => "sync"}} = Lro.run(%{}, op(), final: :poll_body, delay_ms: 0)
  end
end
