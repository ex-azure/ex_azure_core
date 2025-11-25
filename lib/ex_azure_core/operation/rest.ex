defmodule ExAzureCore.Operation.REST do
  @moduledoc """
  REST-based operation for Azure services.

  Used by service modules to define operations that will be executed
  by `ExAzureCore.request/2`.

  ## Fields

    * `:service` - Service atom (e.g., `:storage`, `:keyvault`, `:management`)
    * `:http_method` - HTTP method
    * `:path` - URL path (relative to base URL)
    * `:host` - Optional host override
    * `:body` - Request body (map for JSON, binary for raw)
    * `:params` - Query parameters
    * `:headers` - Additional headers
    * `:parser` - Optional function to parse response body
    * `:stream_builder` - Optional function to build pagination stream

  ## Example

      %ExAzureCore.Operation.REST{
        service: :keyvault,
        http_method: :get,
        path: "/secrets/my-secret",
        params: %{},
        parser: fn response -> response.body end
      }
  """

  @type http_method :: :get | :post | :put | :patch | :delete | :head

  @type t :: %__MODULE__{
          service: atom(),
          http_method: http_method(),
          path: String.t(),
          host: String.t() | nil,
          body: term(),
          params: map(),
          headers: [{String.t(), String.t()}],
          parser: (ExAzureCore.Http.Response.t() -> term()) | nil,
          stream_builder: (map() -> Enumerable.t()) | nil
        }

  defstruct [
    :service,
    :http_method,
    :path,
    :host,
    body: nil,
    params: %{},
    headers: [],
    parser: nil,
    stream_builder: nil
  ]
end

defimpl ExAzureCore.Operation, for: ExAzureCore.Operation.REST do
  alias ExAzureCore.Http.Client
  alias ExAzureCore.Http.Request

  @doc """
  Executes the REST operation using the HTTP client.
  """
  def perform(operation, config) do
    client = build_client(operation, config)
    request = build_request(operation, config)

    case Client.request(client, request) do
      {:ok, response} ->
        parse_response(response, operation)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns a stream for paginated results.
  """
  def stream!(%{stream_builder: nil}, _config) do
    raise ArgumentError, "This operation does not support streaming"
  end

  def stream!(%{stream_builder: builder}, config) when is_function(builder, 1) do
    builder.(config)
  end

  defp build_client(operation, config) do
    base_url = resolve_base_url(operation, config)
    plugins = Map.get(config, :plugins, [])
    timeout = Map.get(config, :timeout, 30_000)
    pool_timeout = Map.get(config, :pool_timeout, 5_000)

    Client.new(
      base_url: base_url,
      timeout: timeout,
      pool_timeout: pool_timeout,
      plugins: plugins
    )
  end

  defp resolve_base_url(%{host: host}, _config) when is_binary(host) and host != "" do
    ensure_scheme(host)
  end

  defp resolve_base_url(_operation, %{base_url: base_url}) when is_binary(base_url) do
    base_url
  end

  defp resolve_base_url(_operation, %{host: host}) when is_binary(host) do
    ensure_scheme(host)
  end

  defp resolve_base_url(_operation, _config) do
    raise ArgumentError, "No base_url or host configured for operation"
  end

  defp ensure_scheme(url) do
    if String.starts_with?(url, "http") do
      url
    else
      "https://#{url}"
    end
  end

  defp build_request(operation, config) do
    api_version = Map.get(config, :api_version)

    params =
      if api_version do
        Map.put(operation.params, "api-version", api_version)
      else
        operation.params
      end

    Request.new(
      method: operation.http_method,
      url: operation.path,
      headers: Map.new(operation.headers),
      body: operation.body,
      query: stringify_params(params)
    )
  end

  defp stringify_params(params) when is_map(params) do
    Map.new(params, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp parse_response(response, %{parser: nil}) do
    {:ok, response}
  end

  defp parse_response(response, %{parser: parser}) when is_function(parser, 1) do
    {:ok, parser.(response)}
  end
end
