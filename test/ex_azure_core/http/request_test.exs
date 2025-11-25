defmodule ExAzureCore.Http.RequestTest do
  use ExUnit.Case, async: true

  alias ExAzureCore.Http.Request

  describe "new/1" do
    test "creates request with required fields" do
      request = Request.new(method: :get, url: "/test")

      assert request.method == :get
      assert request.url == "/test"
      assert request.headers == %{}
      assert request.body == nil
      assert request.query == %{}
    end

    test "creates request with all fields" do
      request =
        Request.new(
          method: :post,
          url: "/test",
          headers: %{"Content-Type" => "application/json"},
          body: %{data: "value"},
          query: %{"api-version" => "2024-01-01"}
        )

      assert request.method == :post
      assert request.url == "/test"
      assert request.headers == %{"content-type" => "application/json"}
      assert request.body == %{data: "value"}
      assert request.query == %{"api-version" => "2024-01-01"}
    end

    test "normalizes header names to lowercase" do
      request =
        Request.new(method: :get, url: "/test", headers: %{"Content-Type" => "text/plain"})

      assert request.headers == %{"content-type" => "text/plain"}
    end
  end

  describe "put_header/3" do
    test "adds a header" do
      request =
        Request.new(method: :get, url: "/test")
        |> Request.put_header("x-custom", "value")

      assert request.headers == %{"x-custom" => "value"}
    end

    test "normalizes header name to lowercase" do
      request =
        Request.new(method: :get, url: "/test")
        |> Request.put_header("X-Custom-Header", "value")

      assert request.headers == %{"x-custom-header" => "value"}
    end

    test "overwrites existing header" do
      request =
        Request.new(method: :get, url: "/test", headers: %{"x-custom" => "old"})
        |> Request.put_header("x-custom", "new")

      assert request.headers == %{"x-custom" => "new"}
    end
  end

  describe "put_headers/2" do
    test "merges multiple headers" do
      request =
        Request.new(method: :get, url: "/test", headers: %{"existing" => "value"})
        |> Request.put_headers(%{"header1" => "value1", "header2" => "value2"})

      assert request.headers == %{
               "existing" => "value",
               "header1" => "value1",
               "header2" => "value2"
             }
    end
  end

  describe "put_query/3" do
    test "adds a query parameter" do
      request =
        Request.new(method: :get, url: "/test")
        |> Request.put_query("key", "value")

      assert request.query == %{"key" => "value"}
    end
  end

  describe "put_body/2" do
    test "sets the body" do
      request =
        Request.new(method: :post, url: "/test")
        |> Request.put_body("raw data")

      assert request.body == "raw data"
    end
  end

  describe "put_json/2" do
    test "sets body and content-type header" do
      request =
        Request.new(method: :post, url: "/test")
        |> Request.put_json(%{key: "value"})

      assert request.body == %{key: "value"}
      assert request.headers == %{"content-type" => "application/json"}
    end
  end

  describe "put_form/2" do
    test "sets body as form and content-type header" do
      request =
        Request.new(method: :post, url: "/test")
        |> Request.put_form(%{"field" => "value"})

      assert request.body == {:form, %{"field" => "value"}}
      assert request.headers == %{"content-type" => "application/x-www-form-urlencoded"}
    end
  end

  describe "to_req_options/1" do
    test "converts request to Req options" do
      request =
        Request.new(
          method: :post,
          url: "/test",
          headers: %{"x-custom" => "value"},
          body: %{data: "value"},
          query: %{"version" => "1"}
        )

      opts = Request.to_req_options(request)

      assert opts[:method] == :post
      assert opts[:url] == "/test"
      assert opts[:headers] == [{"x-custom", "value"}]
      assert opts[:json] == %{data: "value"}
      assert opts[:params] == %{"version" => "1"}
    end

    test "converts form body correctly" do
      request =
        Request.new(method: :post, url: "/test")
        |> Request.put_form(%{"field" => "value"})

      opts = Request.to_req_options(request)

      assert opts[:form] == %{"field" => "value"}
    end

    test "excludes empty query params" do
      request = Request.new(method: :get, url: "/test")
      opts = Request.to_req_options(request)

      refute Keyword.has_key?(opts, :params)
    end
  end
end
