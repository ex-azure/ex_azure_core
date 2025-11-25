defmodule ExAzureCore.Http.Plugins.AzureHeadersTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Http.Plugins.AzureHeaders

  describe "attach/2" do
    test "adds x-ms-version header when api_version is provided" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "x-ms-version") == "2024-01-01"
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> AzureHeaders.attach(api_version: "2024-01-01")
      |> Req.request!()
    end

    test "adds x-ms-date header by default" do
      stub(Req, :request, fn request, _opts ->
        date = get_header(request, "x-ms-date")
        assert date != nil
        assert String.contains?(date, "GMT")
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> AzureHeaders.attach()
      |> Req.request!()
    end

    test "skips x-ms-date when include_date is false" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "x-ms-date") == nil
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> AzureHeaders.attach(include_date: false)
      |> Req.request!()
    end

    test "adds x-ms-return-client-request-id header" do
      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "x-ms-return-client-request-id") == "true"
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> AzureHeaders.attach()
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
