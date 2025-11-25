defmodule ExAzureCore.Http.ResponseTest do
  use ExUnit.Case, async: true

  alias ExAzureCore.Http.Response

  describe "from_req/1" do
    test "creates response from Req.Response" do
      req_response = %Req.Response{
        status: 200,
        headers: [
          {"content-type", "application/json"},
          {"x-ms-request-id", "server-123"},
          {"x-ms-client-request-id", "client-456"}
        ],
        body: %{"data" => "value"}
      }

      response = Response.from_req(req_response)

      assert response.status == 200
      assert response.body == %{"data" => "value"}
      assert response.headers["content-type"] == "application/json"
      assert response.request_id == "server-123"
      assert response.client_request_id == "client-456"
    end

    test "normalizes header names to lowercase" do
      req_response = %Req.Response{
        status: 200,
        headers: [{"Content-Type", "text/plain"}],
        body: ""
      }

      response = Response.from_req(req_response)

      assert response.headers["content-type"] == "text/plain"
    end
  end

  describe "success?/1" do
    test "returns true for 2xx status codes" do
      for status <- [200, 201, 204, 299] do
        response = %Response{status: status}
        assert Response.success?(response), "Expected #{status} to be success"
      end
    end

    test "returns false for non-2xx status codes" do
      for status <- [100, 301, 400, 500] do
        response = %Response{status: status}
        refute Response.success?(response), "Expected #{status} to not be success"
      end
    end
  end

  describe "client_error?/1" do
    test "returns true for 4xx status codes" do
      for status <- [400, 401, 403, 404, 429] do
        response = %Response{status: status}
        assert Response.client_error?(response), "Expected #{status} to be client error"
      end
    end

    test "returns false for non-4xx status codes" do
      for status <- [200, 301, 500] do
        response = %Response{status: status}
        refute Response.client_error?(response), "Expected #{status} to not be client error"
      end
    end
  end

  describe "server_error?/1" do
    test "returns true for 5xx status codes" do
      for status <- [500, 502, 503, 504] do
        response = %Response{status: status}
        assert Response.server_error?(response), "Expected #{status} to be server error"
      end
    end

    test "returns false for non-5xx status codes" do
      for status <- [200, 400, 429] do
        response = %Response{status: status}
        refute Response.server_error?(response), "Expected #{status} to not be server error"
      end
    end
  end

  describe "rate_limited?/1" do
    test "returns true for 429 status" do
      response = %Response{status: 429}
      assert Response.rate_limited?(response)
    end

    test "returns false for other status codes" do
      response = %Response{status: 400}
      refute Response.rate_limited?(response)
    end
  end

  describe "get_header/2" do
    test "returns header value" do
      response = %Response{headers: %{"content-type" => "application/json"}}

      assert Response.get_header(response, "content-type") == "application/json"
    end

    test "is case-insensitive" do
      response = %Response{headers: %{"content-type" => "application/json"}}

      assert Response.get_header(response, "Content-Type") == "application/json"
    end

    test "returns nil for missing header" do
      response = %Response{headers: %{}}

      assert Response.get_header(response, "x-missing") == nil
    end
  end

  describe "get_retry_after/1" do
    test "returns retry-after as integer" do
      response = %Response{headers: %{"retry-after" => "120"}}

      assert Response.get_retry_after(response) == 120
    end

    test "returns nil when header is missing" do
      response = %Response{headers: %{}}

      assert Response.get_retry_after(response) == nil
    end

    test "returns nil for invalid value" do
      response = %Response{headers: %{"retry-after" => "invalid"}}

      assert Response.get_retry_after(response) == nil
    end
  end

  describe "content_type/1" do
    test "returns content type without parameters" do
      response = %Response{headers: %{"content-type" => "application/json; charset=utf-8"}}

      assert Response.content_type(response) == "application/json"
    end

    test "returns nil when header is missing" do
      response = %Response{headers: %{}}

      assert Response.content_type(response) == nil
    end
  end
end
