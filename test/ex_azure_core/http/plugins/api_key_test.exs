defmodule ExAzureCore.Http.Plugins.ApiKeyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Credentials.AzureKeyCredential
  alias ExAzureCore.Http.Plugins.ApiKey

  describe "attach/2" do
    test "adds api-key header with string key" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "api-key") == "my-secret-key"
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> ApiKey.attach(api_key: "my-secret-key")
      |> Req.request!()
    end

    test "adds api-key header with AzureKeyCredential" do
      {:ok, credential} = AzureKeyCredential.new("credential-key")

      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "api-key") == "credential-key"
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> ApiKey.attach(api_key: credential)
      |> Req.request!()
    end

    test "uses custom header name" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "ocp-apim-subscription-key") == "my-key"
        assert get_header(request, "api-key") == nil
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> ApiKey.attach(api_key: "my-key", header_name: "Ocp-Apim-Subscription-Key")
      |> Req.request!()
    end

    test "adds prefix to header value" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "api-key") == "ApiKey my-secret-key"
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> ApiKey.attach(api_key: "my-secret-key", prefix: "ApiKey")
      |> Req.request!()
    end

    test "stores error in private when no api_key provided" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "api-key") == nil
        assert request.private[:api_key_error] == :no_api_key_configured
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> ApiKey.attach()
      |> Req.request!()
    end

    test "stores error in private when api_key is empty string" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "api-key") == nil
        assert request.private[:api_key_error] == :invalid_api_key
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> ApiKey.attach(api_key: "")
      |> Req.request!()
    end

    test "stores error in private when api_key is invalid type" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "api-key") == nil
        assert request.private[:api_key_error] == :invalid_api_key
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> ApiKey.attach(api_key: 123)
      |> Req.request!()
    end
  end

  defp get_header(request, name) do
    request.headers
    |> Enum.find(fn {k, _v} -> String.downcase(to_string(k)) == String.downcase(name) end)
    |> case do
      {_, [value | _]} -> value
      {_, value} -> value
      nil -> nil
    end
  end
end
