defmodule ExAzureCore.Http.Plugins.Retry do
  @moduledoc """
  Req plugin that implements Azure-specific retry logic.

  Retries requests on transient failures with exponential backoff and jitter,
  respecting the `Retry-After` header when present.

  ## Retryable Status Codes

    * 408 - Request Timeout
    * 429 - Too Many Requests
    * 500 - Internal Server Error
    * 502 - Bad Gateway
    * 503 - Service Unavailable
    * 504 - Gateway Timeout

  ## Options

    * `:max_retries` - Maximum number of retry attempts (default: 3)
    * `:base_delay` - Base delay in milliseconds (default: 1000)
    * `:max_delay` - Maximum delay in milliseconds (default: 32000)
    * `:retry_statuses` - List of status codes to retry (default: [408, 429, 500, 502, 503, 504])

  ## Example

      req = Req.new()
      |> ExAzureCore.Http.Plugins.Retry.attach(max_retries: 5)
  """

  require Logger

  @default_max_retries 3
  @default_base_delay 1_000
  @default_max_delay 32_000
  @default_retry_statuses [408, 429, 500, 502, 503, 504]

  @doc """
  Attaches the retry plugin to a Req request.
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts \\ []) do
    request
    |> Req.Request.register_options([
      :max_retries,
      :base_delay,
      :max_delay,
      :retry_statuses,
      :retry_count
    ])
    |> Req.Request.merge_options(opts)
    |> Req.Request.prepend_response_steps(azure_retry: &maybe_retry/1)
    |> Req.Request.prepend_error_steps(azure_retry_error: &maybe_retry_error/1)
  end

  defp maybe_retry({request, response}) do
    retry_statuses = request.options[:retry_statuses] || @default_retry_statuses

    if response.status in retry_statuses do
      do_retry(request, response)
    else
      {request, response}
    end
  end

  defp maybe_retry_error({request, exception}) do
    if retryable_error?(exception) do
      do_retry_error(request, exception)
    else
      {request, exception}
    end
  end

  defp retryable_error?(%Req.TransportError{}), do: true
  defp retryable_error?(%Mint.TransportError{}), do: true
  defp retryable_error?(_), do: false

  defp do_retry(request, response) do
    max_retries = request.options[:max_retries] || @default_max_retries
    retry_count = request.options[:retry_count] || 0

    if retry_count < max_retries do
      delay = calculate_delay(request, response, retry_count)

      Logger.debug(
        "Azure retry: attempt #{retry_count + 1}/#{max_retries}, " <>
          "status=#{response.status}, delay=#{delay}ms"
      )

      Process.sleep(delay)

      request = Req.Request.merge_options(request, retry_count: retry_count + 1)
      {request, Req.Request.run_request(request)}
    else
      {request, response}
    end
  end

  defp do_retry_error(request, exception) do
    max_retries = request.options[:max_retries] || @default_max_retries
    retry_count = request.options[:retry_count] || 0

    if retry_count < max_retries do
      delay = calculate_delay(request, nil, retry_count)

      Logger.debug(
        "Azure retry: attempt #{retry_count + 1}/#{max_retries}, " <>
          "error=#{inspect(exception)}, delay=#{delay}ms"
      )

      Process.sleep(delay)

      request = Req.Request.merge_options(request, retry_count: retry_count + 1)
      {request, Req.Request.run_request(request)}
    else
      {request, exception}
    end
  end

  defp calculate_delay(request, response, retry_count) do
    retry_after = get_retry_after(response)

    if retry_after do
      retry_after * 1000
    else
      base_delay = request.options[:base_delay] || @default_base_delay
      max_delay = request.options[:max_delay] || @default_max_delay

      exponential_delay(base_delay, max_delay, retry_count)
    end
  end

  defp get_retry_after(nil), do: nil

  defp get_retry_after(%{headers: headers}) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(to_string(k)) == "retry-after" end)
    |> case do
      {_, value} -> parse_retry_after(value)
      nil -> nil
    end
  end

  defp parse_retry_after(value) when is_list(value) do
    parse_retry_after(List.first(value))
  end

  defp parse_retry_after(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds
      :error -> nil
    end
  end

  defp parse_retry_after(_), do: nil

  defp exponential_delay(base_delay, max_delay, retry_count) do
    delay = base_delay * :math.pow(2, retry_count)
    jitter = :rand.uniform(round(delay * 0.2))
    delay = round(delay) + jitter
    min(delay, max_delay)
  end
end
