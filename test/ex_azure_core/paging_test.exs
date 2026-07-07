defmodule ExAzureCore.PagingTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Operation.REST
  alias ExAzureCore.Paging

  defp op do
    %REST{
      service: :storage,
      http_method: :get,
      path: "/pets",
      default_host: "petstore.example.com"
    }
  end

  test "walks pages until nextLink is absent, decoding each item in order" do
    expect(Req, :request, fn client, _opts ->
      assert client.options[:base_url] == "https://petstore.example.com"

      {:ok,
       %Req.Response{
         status: 200,
         headers: [],
         body: %{
           "items" => [%{"id" => 1}, %{"id" => 2}],
           "next" => "https://next.example.com/pets?skiptoken=p2"
         }
       }}
    end)

    expect(Req, :request, fn client, _opts ->
      assert client.options[:base_url] == "https://next.example.com"

      {:ok,
       %Req.Response{
         status: 200,
         headers: [],
         body: %{"items" => [%{"id" => 3}], "next" => nil}
       }}
    end)

    result =
      Paging.nextlink_stream(%{}, op(), items: "items", next_link: "next", decode: &Map.fetch!(&1, "id"))
      |> Enum.to_list()

    assert result == [1, 2, 3]
  end

  test "a single page with no nextLink yields just that page" do
    expect(Req, :request, fn _client, _opts ->
      {:ok, %Req.Response{status: 200, headers: [], body: %{"items" => [%{"id" => 1}], "next" => ""}}}
    end)

    result =
      Paging.nextlink_stream(%{}, op(), items: "items", next_link: "next")
      |> Enum.to_list()

    assert result == [%{"id" => 1}]
  end

  test "streams lazily — only fetches pages that are consumed" do
    expect(Req, :request, fn _client, _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         headers: [],
         body: %{"items" => [%{"id" => 1}], "next" => "https://next.example.com/pets?skiptoken=p2"}
       }}
    end)

    # Take only the first item; the second page must never be requested (single expect above).
    result =
      Paging.nextlink_stream(%{}, op(), items: "items", next_link: "next")
      |> Enum.take(1)

    assert result == [%{"id" => 1}]
  end

  describe "continuation_stream/3" do
    test "re-issues the same operation with the token on a query param until absent" do
      expect(Req, :request, fn client, opts ->
        assert client.options[:base_url] == "https://petstore.example.com"
        refute Map.has_key?(opts[:params] || %{}, "token")

        {:ok, %Req.Response{status: 200, headers: [], body: %{"items" => [%{"id" => 1}], "nextToken" => "abc"}}}
      end)

      expect(Req, :request, fn _client, opts ->
        assert opts[:params]["token"] == "abc"

        {:ok, %Req.Response{status: 200, headers: [], body: %{"items" => [%{"id" => 2}], "nextToken" => nil}}}
      end)

      result =
        Paging.continuation_stream(%{}, op(),
          items: "items",
          token_response: "nextToken",
          token_query: "token",
          decode: &Map.fetch!(&1, "id")
        )
        |> Enum.to_list()

      assert result == [1, 2]
    end

    test "halts on an empty-string token" do
      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, headers: [], body: %{"items" => [%{"id" => 1}], "nextToken" => ""}}}
      end)

      result =
        Paging.continuation_stream(%{}, op(), items: "items", token_response: "nextToken", token_query: "token")
        |> Enum.to_list()

      assert result == [%{"id" => 1}]
    end
  end
end
