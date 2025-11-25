defmodule ExAzureCore.Errors.HttpError do
  @moduledoc """
  Error representing HTTP-level failures from Azure services.

  This error is raised when an HTTP request completes but returns
  a non-successful status code (4xx or 5xx).

  ## Fields

    * `:status` - HTTP status code
    * `:error_code` - Azure error code from response body (if available)
    * `:message` - Error message from Azure or generated
    * `:request_id` - Azure request ID for correlation
    * `:url` - The URL that was requested
  """
  @moduledoc section: :errors

  use Splode.Error,
    fields: [:status, :error_code, :message, :request_id, :url],
    class: :external

  @type t() :: %__MODULE__{
          status: integer() | nil,
          error_code: String.t() | nil,
          message: String.t() | nil,
          request_id: String.t() | nil,
          url: String.t() | nil
        }

  @impl true
  def message(%{status: status, error_code: code, message: msg, url: url}) do
    base = "HTTP #{status || "error"}"

    base =
      if code do
        "#{base} [#{code}]"
      else
        base
      end

    base =
      if msg do
        "#{base}: #{msg}"
      else
        base
      end

    if url do
      "#{base} (#{url})"
    else
      base
    end
  end

  @doc """
  Creates an HttpError from an Azure error response body.

  Azure services typically return errors in the format:

      {
        "error": {
          "code": "ErrorCode",
          "message": "Error message"
        }
      }
  """
  @spec from_response(integer(), map() | binary(), String.t() | nil, String.t() | nil) :: t()
  def from_response(status, body, request_id \\ nil, url \\ nil)

  def from_response(status, %{"error" => error}, request_id, url) when is_map(error) do
    exception(
      status: status,
      error_code: Map.get(error, "code"),
      message: Map.get(error, "message"),
      request_id: request_id,
      url: url
    )
  end

  def from_response(status, %{"code" => code, "message" => message}, request_id, url) do
    exception(
      status: status,
      error_code: code,
      message: message,
      request_id: request_id,
      url: url
    )
  end

  def from_response(status, body, request_id, url) when is_binary(body) do
    exception(
      status: status,
      error_code: nil,
      message: body,
      request_id: request_id,
      url: url
    )
  end

  def from_response(status, _body, request_id, url) do
    exception(
      status: status,
      error_code: nil,
      message: status_message(status),
      request_id: request_id,
      url: url
    )
  end

  defp status_message(400), do: "Bad Request"
  defp status_message(401), do: "Unauthorized"
  defp status_message(403), do: "Forbidden"
  defp status_message(404), do: "Not Found"
  defp status_message(405), do: "Method Not Allowed"
  defp status_message(408), do: "Request Timeout"
  defp status_message(409), do: "Conflict"
  defp status_message(429), do: "Too Many Requests"
  defp status_message(500), do: "Internal Server Error"
  defp status_message(502), do: "Bad Gateway"
  defp status_message(503), do: "Service Unavailable"
  defp status_message(504), do: "Gateway Timeout"
  defp status_message(_), do: "HTTP Error"
end
