defmodule ExAzureCore.Http.Client do
  @moduledoc """
  HTTP client for Azure services using Req.

  Provides a pre-configured Req client with Azure-specific plugins
  for authentication, error handling, and retry logic.

  ## Creating a Client

      client = ExAzureCore.Http.Client.new(base_url: "https://management.azure.com")

  ## Making Requests

      {:ok, response} = ExAzureCore.Http.Client.get(client, "/subscriptions")
      {:ok, response} = ExAzureCore.Http.Client.post(client, "/resources", %{name: "example"})

  ## With Plugins

      client = ExAzureCore.Http.Client.new(
        base_url: "https://vault.azure.net",
        plugins: [
          {ExAzureCore.Http.Plugins.BearerToken, credential: :my_credential},
          {ExAzureCore.Http.Plugins.AzureHeaders, api_version: "7.4"}
        ]
      )
  """

  alias ExAzureCore.Errors.NetworkError
  alias ExAzureCore.Http.Request
  alias ExAzureCore.Http.Response

  @type client :: Req.Request.t()

  @default_timeout 30_000
  @default_pool_timeout 5_000

  @doc """
  Creates a new HTTP client with the given options.

  ## Options

    * `:base_url` - Base URL for all requests
    * `:timeout` - Request timeout in milliseconds (default: #{@default_timeout})
    * `:pool_timeout` - Connection pool timeout (default: #{@default_pool_timeout})
    * `:plugins` - List of plugins to attach, as `{Module, opts}` or `Module`
    * `:headers` - Default headers for all requests
  """
  @spec new(keyword()) :: client()
  def new(opts \\ []) do
    base_url = Keyword.get(opts, :base_url)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_pool_timeout)
    headers = Keyword.get(opts, :headers, [])
    plugins = Keyword.get(opts, :plugins, [])

    req =
      Req.new(
        base_url: base_url,
        receive_timeout: timeout,
        pool_timeout: pool_timeout,
        headers: headers,
        retry: false
      )

    attach_plugins(req, plugins)
  end

  @doc """
  Executes an HTTP request using the given client.

  ## Parameters

    * `client` - The Req client
    * `request` - An `ExAzureCore.Http.Request` struct

  ## Returns

    * `{:ok, response}` - Successful response
    * `{:error, error}` - Network or HTTP error
  """
  @spec request(client(), Request.t()) :: {:ok, Response.t()} | {:error, term()}
  def request(client, %Request{} = request) do
    opts = Request.to_req_options(request)
    do_request(client, opts)
  end

  @doc """
  Executes a GET request.
  """
  @spec get(client(), String.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def get(client, url, opts \\ []) do
    do_request(client, [{:method, :get}, {:url, url} | opts])
  end

  @doc """
  Executes a POST request.
  """
  @spec post(client(), String.t(), term(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def post(client, url, body \\ nil, opts \\ []) do
    opts = add_body(opts, body)
    do_request(client, [{:method, :post}, {:url, url} | opts])
  end

  @doc """
  Executes a PUT request.
  """
  @spec put(client(), String.t(), term(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def put(client, url, body \\ nil, opts \\ []) do
    opts = add_body(opts, body)
    do_request(client, [{:method, :put}, {:url, url} | opts])
  end

  @doc """
  Executes a PATCH request.
  """
  @spec patch(client(), String.t(), term(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def patch(client, url, body \\ nil, opts \\ []) do
    opts = add_body(opts, body)
    do_request(client, [{:method, :patch}, {:url, url} | opts])
  end

  @doc """
  Executes a DELETE request.
  """
  @spec delete(client(), String.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def delete(client, url, opts \\ []) do
    do_request(client, [{:method, :delete}, {:url, url} | opts])
  end

  @doc """
  Executes a HEAD request.
  """
  @spec head(client(), String.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def head(client, url, opts \\ []) do
    do_request(client, [{:method, :head}, {:url, url} | opts])
  end

  @doc """
  Executes a streaming request.

  The `into` option determines how the response body is streamed:

    * `into: File.stream!(path)` - Stream to a file
    * `into: fun` - Stream to a function
    * `into: :self` - Stream to the calling process
  """
  @spec stream(client(), Request.t() | keyword(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def stream(client, request_or_opts, opts \\ [])

  def stream(client, %Request{} = request, opts) do
    req_opts = Request.to_req_options(request)
    stream(client, req_opts, opts)
  end

  def stream(client, request_opts, stream_opts) when is_list(request_opts) do
    into = Keyword.fetch!(stream_opts, :into)
    opts = Keyword.put(request_opts, :into, into)
    do_request(client, opts)
  end

  defp do_request(client, opts) do
    case Req.request(client, opts) do
      {:ok, %Req.Response{} = req_response} ->
        response = Response.from_req(req_response)
        {:ok, response}

      {:error, %Req.TransportError{reason: reason}} ->
        url = Keyword.get(opts, :url, "")
        {:error, NetworkError.exception(service: :azure, endpoint: url, reason: reason)}

      {:error, %Mint.TransportError{reason: reason}} ->
        url = Keyword.get(opts, :url, "")
        {:error, NetworkError.exception(service: :azure, endpoint: url, reason: reason)}

      {:error, reason} ->
        url = Keyword.get(opts, :url, "")
        {:error, NetworkError.exception(service: :azure, endpoint: url, reason: reason)}
    end
  end

  defp attach_plugins(req, plugins) do
    Enum.reduce(plugins, req, fn
      {plugin, plugin_opts}, acc -> plugin.attach(acc, plugin_opts)
      plugin, acc -> plugin.attach(acc)
    end)
  end

  defp add_body(opts, nil), do: opts
  defp add_body(opts, body) when is_map(body), do: Keyword.put(opts, :json, body)
  defp add_body(opts, {:form, data}), do: Keyword.put(opts, :form, data)
  defp add_body(opts, body), do: Keyword.put(opts, :body, body)
end
