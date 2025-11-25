defmodule ExAzureCore.Http.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Errors.NetworkError
  alias ExAzureCore.Http.Client
  alias ExAzureCore.Http.Request

  describe "new/1" do
    test "creates a Req client with default options" do
      client = Client.new()

      assert %Req.Request{} = client
    end

    test "creates a Req client with base_url" do
      client = Client.new(base_url: "https://example.com")

      assert client.options[:base_url] == "https://example.com"
    end

    test "creates a Req client with custom timeout" do
      client = Client.new(timeout: 60_000)

      assert client.options[:receive_timeout] == 60_000
    end
  end

  describe "get/3" do
    test "makes a GET request and returns response" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :get
        assert opts[:url] == "/test"

        {:ok,
         %Req.Response{
           status: 200,
           headers: [],
           body: %{"result" => "ok"}
         }}
      end)

      client = Client.new(base_url: "https://example.com")
      {:ok, response} = Client.get(client, "/test")

      assert response.status == 200
      assert response.body == %{"result" => "ok"}
    end

    test "returns NetworkError on connection failure" do
      expect(Req, :request, fn _client, _opts ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end)

      client = Client.new(base_url: "https://example.com")
      {:error, error} = Client.get(client, "/test")

      assert %NetworkError{} = error
      assert error.reason == :econnrefused
    end
  end

  describe "post/4" do
    test "makes a POST request with JSON body" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/test"
        assert opts[:json] == %{key: "value"}

        {:ok,
         %Req.Response{
           status: 201,
           headers: [],
           body: %{"id" => "123"}
         }}
      end)

      client = Client.new(base_url: "https://example.com")
      {:ok, response} = Client.post(client, "/test", %{key: "value"})

      assert response.status == 201
    end

    test "makes a POST request with form body" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:form] == %{"field" => "value"}

        {:ok,
         %Req.Response{
           status: 200,
           headers: [],
           body: %{}
         }}
      end)

      client = Client.new(base_url: "https://example.com")
      {:ok, _response} = Client.post(client, "/test", {:form, %{"field" => "value"}})
    end
  end

  describe "put/4" do
    test "makes a PUT request" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :put

        {:ok, %Req.Response{status: 200, headers: [], body: %{}}}
      end)

      client = Client.new(base_url: "https://example.com")
      {:ok, response} = Client.put(client, "/test", %{data: "value"})

      assert response.status == 200
    end
  end

  describe "delete/3" do
    test "makes a DELETE request" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete

        {:ok, %Req.Response{status: 204, headers: [], body: nil}}
      end)

      client = Client.new(base_url: "https://example.com")
      {:ok, response} = Client.delete(client, "/test")

      assert response.status == 204
    end
  end

  describe "request/2" do
    test "executes a Request struct" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/custom"
        assert opts[:headers] == [{"x-custom", "value"}]

        {:ok, %Req.Response{status: 200, headers: [], body: %{}}}
      end)

      client = Client.new(base_url: "https://example.com")

      request =
        Request.new(method: :post, url: "/custom")
        |> Request.put_header("x-custom", "value")

      {:ok, response} = Client.request(client, request)

      assert response.status == 200
    end
  end
end
