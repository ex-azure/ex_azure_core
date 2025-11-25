defmodule ExAzureCore.Http.Request do
  @moduledoc """
  Represents an HTTP request for Azure services.

  Provides a normalized request structure that can be converted to Req options.

  ## Creating a Request

      request = ExAzureCore.Http.Request.new(
        method: :get,
        url: "/subscriptions",
        headers: %{"accept" => "application/json"}
      )

  ## Building Requests

      request =
        Request.new(method: :post, url: "/resources")
        |> Request.put_header("content-type", "application/json")
        |> Request.put_query("api-version", "2024-01-01")
        |> Request.put_body(%{name: "example"})
  """

  @type method :: :get | :post | :put | :patch | :delete | :head | :options

  @type t :: %__MODULE__{
          method: method(),
          url: String.t(),
          headers: %{String.t() => String.t()},
          body: term(),
          query: %{String.t() => String.t()},
          options: keyword()
        }

  @enforce_keys [:method, :url]
  defstruct [
    :method,
    :url,
    headers: %{},
    body: nil,
    query: %{},
    options: []
  ]

  @doc """
  Creates a new request with the given options.

  ## Options

    * `:method` - Required. HTTP method atom
    * `:url` - Required. URL path or full URL
    * `:headers` - Optional. Map of headers
    * `:body` - Optional. Request body
    * `:query` - Optional. Query parameters map
    * `:options` - Optional. Additional Req options
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    method = Keyword.fetch!(opts, :method)
    url = Keyword.fetch!(opts, :url)

    %__MODULE__{
      method: method,
      url: url,
      headers: Keyword.get(opts, :headers, %{}) |> normalize_headers(),
      body: Keyword.get(opts, :body),
      query: Keyword.get(opts, :query, %{}),
      options: Keyword.get(opts, :options, [])
    }
  end

  @doc """
  Adds or updates a header in the request.

  Header names are normalized to lowercase.
  """
  @spec put_header(t(), String.t(), String.t()) :: t()
  def put_header(%__MODULE__{} = request, name, value)
      when is_binary(name) and is_binary(value) do
    normalized_name = String.downcase(name)
    %{request | headers: Map.put(request.headers, normalized_name, value)}
  end

  @doc """
  Merges multiple headers into the request.

  Header names are normalized to lowercase.
  """
  @spec put_headers(t(), %{String.t() => String.t()} | keyword()) :: t()
  def put_headers(%__MODULE__{} = request, headers) when is_map(headers) or is_list(headers) do
    normalized = normalize_headers(headers)
    %{request | headers: Map.merge(request.headers, normalized)}
  end

  @doc """
  Adds or updates a query parameter.
  """
  @spec put_query(t(), String.t(), String.t()) :: t()
  def put_query(%__MODULE__{} = request, name, value) when is_binary(name) and is_binary(value) do
    %{request | query: Map.put(request.query, name, value)}
  end

  @doc """
  Merges multiple query parameters into the request.
  """
  @spec put_query_params(t(), %{String.t() => String.t()} | keyword()) :: t()
  def put_query_params(%__MODULE__{} = request, params) do
    params_map =
      case params do
        map when is_map(map) -> map
        list when is_list(list) -> Map.new(list, fn {k, v} -> {to_string(k), to_string(v)} end)
      end

    %{request | query: Map.merge(request.query, params_map)}
  end

  @doc """
  Sets the request body.
  """
  @spec put_body(t(), term()) :: t()
  def put_body(%__MODULE__{} = request, body) do
    %{request | body: body}
  end

  @doc """
  Sets the body as JSON and adds the content-type header.
  """
  @spec put_json(t(), term()) :: t()
  def put_json(%__MODULE__{} = request, data) do
    request
    |> put_header("content-type", "application/json")
    |> put_body(data)
  end

  @doc """
  Sets the body as form data and adds the content-type header.
  """
  @spec put_form(t(), keyword() | map()) :: t()
  def put_form(%__MODULE__{} = request, data) do
    request
    |> put_header("content-type", "application/x-www-form-urlencoded")
    |> put_body({:form, data})
  end

  @doc """
  Converts the request to Req options.
  """
  @spec to_req_options(t()) :: keyword()
  def to_req_options(%__MODULE__{} = request) do
    opts =
      [
        method: request.method,
        url: request.url,
        headers: Map.to_list(request.headers)
      ]
      |> maybe_add_body(request.body)
      |> maybe_add_query(request.query)

    Keyword.merge(opts, request.options)
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end

  defp maybe_add_body(opts, nil), do: opts
  defp maybe_add_body(opts, {:form, data}), do: Keyword.put(opts, :form, data)
  defp maybe_add_body(opts, body) when is_map(body), do: Keyword.put(opts, :json, body)
  defp maybe_add_body(opts, body), do: Keyword.put(opts, :body, body)

  defp maybe_add_query(opts, query) when map_size(query) == 0, do: opts
  defp maybe_add_query(opts, query), do: Keyword.put(opts, :params, query)
end
