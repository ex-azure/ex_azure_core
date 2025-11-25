defmodule ExAzureCore.Http.Response do
  @moduledoc """
  Represents an HTTP response from Azure services.

  Provides normalized access to response data with helper functions for
  common status code checks and header access.

  ## Creating from Req Response

      {:ok, req_response} = Req.request(opts)
      response = ExAzureCore.Http.Response.from_req(req_response)

  ## Checking Status

      if Response.success?(response) do
        process(response.body)
      end
  """

  @type t :: %__MODULE__{
          status: integer(),
          headers: %{String.t() => String.t()},
          body: term(),
          request_id: String.t() | nil,
          client_request_id: String.t() | nil
        }

  defstruct [
    :status,
    :body,
    headers: %{},
    request_id: nil,
    client_request_id: nil
  ]

  @doc """
  Creates a Response from a Req.Response struct.
  """
  @spec from_req(Req.Response.t()) :: t()
  def from_req(%Req.Response{} = req_response) do
    headers = normalize_headers(req_response.headers)

    %__MODULE__{
      status: req_response.status,
      headers: headers,
      body: req_response.body,
      request_id: Map.get(headers, "x-ms-request-id"),
      client_request_id: Map.get(headers, "x-ms-client-request-id")
    }
  end

  @doc """
  Returns true if the response has a 2xx status code.
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: status}), do: status >= 200 and status < 300

  @doc """
  Returns true if the response has a 4xx status code.
  """
  @spec client_error?(t()) :: boolean()
  def client_error?(%__MODULE__{status: status}), do: status >= 400 and status < 500

  @doc """
  Returns true if the response has a 5xx status code.
  """
  @spec server_error?(t()) :: boolean()
  def server_error?(%__MODULE__{status: status}), do: status >= 500 and status < 600

  @doc """
  Returns true if the response is a redirect (3xx).
  """
  @spec redirect?(t()) :: boolean()
  def redirect?(%__MODULE__{status: status}), do: status >= 300 and status < 400

  @doc """
  Returns true if the response is rate limited (429).
  """
  @spec rate_limited?(t()) :: boolean()
  def rate_limited?(%__MODULE__{status: status}), do: status == 429

  @doc """
  Gets a header value by name (case-insensitive).

  Returns nil if the header is not present.
  """
  @spec get_header(t(), String.t()) :: String.t() | nil
  def get_header(%__MODULE__{headers: headers}, name) when is_binary(name) do
    Map.get(headers, String.downcase(name))
  end

  @doc """
  Gets the Retry-After header value as an integer (seconds).

  Returns nil if the header is not present or cannot be parsed.
  Azure services return Retry-After as seconds.
  """
  @spec get_retry_after(t()) :: non_neg_integer() | nil
  def get_retry_after(%__MODULE__{} = response) do
    case get_header(response, "retry-after") do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {seconds, _} -> seconds
          :error -> nil
        end
    end
  end

  @doc """
  Gets the Content-Type header value.
  """
  @spec content_type(t()) :: String.t() | nil
  def content_type(%__MODULE__{} = response) do
    case get_header(response, "content-type") do
      nil -> nil
      value -> value |> String.split(";") |> List.first() |> String.trim()
    end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {k, v} ->
      key = k |> to_string() |> String.downcase()
      value = if is_list(v), do: Enum.join(v, ", "), else: to_string(v)
      {key, value}
    end)
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end
end
