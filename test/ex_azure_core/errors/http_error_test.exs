defmodule ExAzureCore.Errors.HttpErrorTest do
  use ExUnit.Case, async: true

  alias ExAzureCore.Errors.HttpError

  describe "from_response/4" do
    test "parses Azure error format" do
      body = %{
        "error" => %{
          "code" => "InvalidRequest",
          "message" => "The request was invalid"
        }
      }

      error = HttpError.from_response(400, body, "req-123", "https://example.com/api")

      assert error.status == 400
      assert error.error_code == "InvalidRequest"
      assert error.message == "The request was invalid"
      assert error.request_id == "req-123"
      assert error.url == "https://example.com/api"
    end

    test "parses flat error format" do
      body = %{
        "code" => "NotFound",
        "message" => "Resource not found"
      }

      error = HttpError.from_response(404, body)

      assert error.status == 404
      assert error.error_code == "NotFound"
      assert error.message == "Resource not found"
    end

    test "handles string body" do
      error = HttpError.from_response(500, "Internal Server Error")

      assert error.status == 500
      assert error.message == "Internal Server Error"
    end

    test "handles unknown body format" do
      error = HttpError.from_response(503, %{"unknown" => "format"})

      assert error.status == 503
      assert error.message == "Service Unavailable"
    end
  end

  describe "message/1" do
    test "formats message with all fields" do
      error =
        HttpError.exception(
          status: 400,
          error_code: "BadRequest",
          message: "Invalid parameter",
          url: "https://api.example.com/test"
        )

      assert Exception.message(error) ==
               "HTTP 400 [BadRequest]: Invalid parameter (https://api.example.com/test)"
    end

    test "formats message without error code" do
      error =
        HttpError.exception(
          status: 500,
          message: "Server error"
        )

      assert Exception.message(error) == "HTTP 500: Server error"
    end

    test "formats message with status only" do
      error = HttpError.exception(status: 404)

      assert Exception.message(error) == "HTTP 404"
    end
  end
end
