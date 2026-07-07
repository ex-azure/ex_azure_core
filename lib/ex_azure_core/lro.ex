defmodule ExAzureCore.Lro do
  @moduledoc """
  Drives Azure long-running operations (status-monitor pattern) to completion.

  Generated SDK operations that are long-running set their `:poller` to a
  closure that delegates here, so the polling logic lives (and is tested) in
  one place.

  The flow: perform the initial request, read the status-monitor URL from a
  response header, poll it (honoring `Retry-After`) until the body's status
  property reaches a terminal state, then resolve the final result — either by
  GETting the original resource URI or from the terminal poll body.
  """

  alias ExAzureCore.Http.Response
  alias ExAzureCore.Operation

  @poll_headers ["operation-location", "azure-asyncoperation", "location"]
  @default_delay_ms 1_000

  @doc """
  Runs a long-running operation to completion.

  ## Options

    * `:status_path` - response body key holding the status (default `"status"`)
    * `:succeeded` / `:failed` / `:canceled` - terminal state values
      (defaults `["Succeeded"]` / `["Failed"]` / `["Canceled"]`)
    * `:final` - how to get the result after success: `:original_uri` (GET the
      original resource) or `:poll_body` (use the terminal status monitor body)
    * `:decode` - 1-arity function applied to the final result body
    * `:delay_ms` - fallback poll interval when no `Retry-After` header is present
  """
  @spec run(map(), Operation.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(config, initial_op, opts) do
    decode = Keyword.get(opts, :decode, & &1)

    with {:ok, response} <- perform(initial_op, config) do
      case poll_url(response) do
        nil -> {:ok, decode.(response.body)}
        url -> poll(config, initial_op, url, opts, decode)
      end
    end
  end

  defp poll(config, initial_op, url, opts, decode) do
    status_path = Keyword.get(opts, :status_path, "status")
    succeeded = Keyword.get(opts, :succeeded, ["Succeeded"])

    terminal_error =
      Keyword.get(opts, :failed, ["Failed"]) ++ Keyword.get(opts, :canceled, ["Canceled"])

    with {:ok, response} <- perform(get_op(initial_op, url), config) do
      status = response.body |> Map.get(status_path) |> to_string()

      cond do
        status in succeeded ->
          resolve_final(config, initial_op, response, opts, decode)

        status in terminal_error ->
          {:error, {:lro_failed, status, response.body}}

        true ->
          delay(response, config, opts)
          poll(config, initial_op, url, opts, decode)
      end
    end
  end

  defp resolve_final(config, initial_op, poll_response, opts, decode) do
    case Keyword.get(opts, :final, :poll_body) do
      :original_uri ->
        with {:ok, response} <- perform(%{initial_op | http_method: :get, body: nil}, config) do
          {:ok, decode.(response.body)}
        end

      :poll_body ->
        {:ok, decode.(poll_response.body)}
    end
  end

  defp perform(op, config) do
    Operation.perform(%{op | parser: nil, stream_builder: nil, poller: nil}, config)
  end

  defp poll_url(response) do
    Enum.find_value(@poll_headers, fn header -> Response.get_header(response, header) end)
  end

  defp get_op(op, url) do
    uri = URI.parse(url)
    params = if uri.query, do: URI.decode_query(uri.query), else: %{}

    %{
      op
      | http_method: :get,
        host: "#{uri.scheme}://#{host_with_port(uri)}",
        path: uri.path || "/",
        params: params,
        body: nil
    }
  end

  defp host_with_port(%URI{host: host, port: port, scheme: scheme}) do
    default = if scheme == "https", do: 443, else: 80
    if port && port != default, do: "#{host}:#{port}", else: host
  end

  defp delay(response, config, opts) do
    ms =
      case Response.get_retry_after(response) do
        seconds when is_integer(seconds) -> seconds * 1000
        nil -> Keyword.get(opts, :delay_ms) || Map.get(config, :lro_poll_delay, @default_delay_ms)
      end

    if ms > 0, do: Process.sleep(ms)
    :ok
  end
end
