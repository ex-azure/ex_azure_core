defmodule ExAzureCore.Http.Plugins.ErrorHandler do
  @moduledoc """
  Req plugin that transforms HTTP error responses to Splode errors.

  Parses Azure error response format and maps to appropriate error types:

    * 401/403 - Returns the response for auth-specific handling
    * 400 - Maps to HttpError with parsed error details
    * 4xx - Maps to HttpError
    * 5xx - Maps to HttpError

  ## Azure Error Format

  Azure services return errors in the format:

      {
        "error": {
          "code": "ErrorCode",
          "message": "Error message",
          "details": [...]
        }
      }

  ## Options

    * `:raise_on_error` - Raise exception instead of returning `{:error, _}` (default: false)

  ## Example

      req = Req.new()
      |> ExAzureCore.Http.Plugins.ErrorHandler.attach()
  """

  alias ExAzureCore.Errors.HttpError

  @doc """
  Attaches the error handler plugin to a Req request.
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts \\ []) do
    request
    |> Req.Request.register_options([:raise_on_error])
    |> Req.Request.merge_options(opts)
    |> Req.Request.prepend_response_steps(error_handler: &handle_error_response/1)
  end

  defp handle_error_response({request, response}) do
    if error_status?(response.status) do
      handle_error(request, response)
    else
      {request, response}
    end
  end

  defp error_status?(status), do: status >= 400

  defp handle_error(request, response) do
    raise_on_error = request.options[:raise_on_error] || false
    request_id = get_header(response, "x-ms-request-id")
    url = get_url(request)

    error = HttpError.from_response(response.status, response.body, request_id, url)

    if raise_on_error do
      raise error
    else
      {request, %{response | body: {:error, error}}}
    end
  end

  defp get_header(%{headers: headers}, name) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(to_string(k)) == name end)
    |> case do
      {_, value} when is_list(value) -> List.first(value)
      {_, value} -> value
      nil -> nil
    end
  end

  defp get_url(request) do
    case request.url do
      %URI{} = uri -> URI.to_string(uri)
      url when is_binary(url) -> url
      _ -> nil
    end
  end
end
