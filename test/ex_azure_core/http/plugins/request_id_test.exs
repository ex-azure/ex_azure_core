defmodule ExAzureCore.Http.Plugins.RequestIdTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAzureCore.Http.Plugins.RequestId

  describe "attach/2" do
    test "generates a UUID for x-ms-client-request-id" do
      stub(Req, :request, fn request, _opts ->
        request_id = get_header(request, "x-ms-client-request-id")
        assert request_id != nil

        assert String.match?(
                 request_id,
                 ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
               )

        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> RequestId.attach()
      |> Req.request!()
    end

    test "uses provided request_id" do
      custom_id = "my-custom-request-id"

      stub(Req, :request, fn request, _opts ->
        assert get_header(request, "x-ms-client-request-id") == custom_id
        {:ok, %Req.Response{status: 200, headers: [], body: nil}}
      end)

      Req.new(url: "https://example.com")
      |> RequestId.attach(request_id: custom_id)
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
