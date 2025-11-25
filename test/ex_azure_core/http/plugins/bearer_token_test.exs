defmodule ExAzureCore.Http.Plugins.BearerTokenTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Auth
  alias ExAzureCore.Http.Plugins.BearerToken

  describe "attach/2" do
    test "adds authorization header with static token" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "authorization") == "Bearer my-access-token"
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> BearerToken.attach(token: "my-access-token")
      |> Req.request!()
    end

    test "fetches token from credential server" do
      stub(Auth, :fetch, fn :my_credential ->
        {:ok, %{access_token: "fetched-token"}}
      end)

      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "authorization") == "Bearer fetched-token"
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> BearerToken.attach(credential: :my_credential)
      |> Req.request!()
    end

    test "handles token fetch errors gracefully" do
      stub(Auth, :fetch, fn :failing_credential ->
        {:error, :token_expired}
      end)

      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "authorization") == nil
        assert request.private[:bearer_token_error] == :token_expired
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> BearerToken.attach(credential: :failing_credential)
      |> Req.request!()
    end

    test "does nothing when no credential or token provided" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "authorization") == nil
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> BearerToken.attach()
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
