defmodule ExAzureCore.Http.Plugins.AzureHeaders do
  @moduledoc """
  Req plugin that adds standard Azure headers to requests.

  ## Headers Added

    * `x-ms-version` - Azure API version (from `:api_version` option)
    * `x-ms-date` - RFC 1123 formatted timestamp
    * `x-ms-return-client-request-id` - Set to "true" to echo request ID

  ## Options

    * `:api_version` - Azure API version string (e.g., "2024-01-01")
    * `:include_date` - Whether to add x-ms-date header (default: true)

  ## Example

      req = Req.new()
      |> ExAzureCore.Http.Plugins.AzureHeaders.attach(api_version: "2024-01-01")
  """

  @doc """
  Attaches the Azure headers plugin to a Req request.
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts \\ []) do
    request
    |> Req.Request.register_options([:api_version, :include_date])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(azure_headers: &add_azure_headers/1)
  end

  defp add_azure_headers(request) do
    api_version = request.options[:api_version]
    include_date = Map.get(request.options, :include_date, true)

    request
    |> maybe_add_version(api_version)
    |> maybe_add_date(include_date)
    |> add_return_request_id()
  end

  defp maybe_add_version(request, nil), do: request

  defp maybe_add_version(request, version) do
    Req.Request.put_header(request, "x-ms-version", version)
  end

  defp maybe_add_date(request, false), do: request

  defp maybe_add_date(request, true) do
    date = format_rfc1123_date()
    Req.Request.put_header(request, "x-ms-date", date)
  end

  defp add_return_request_id(request) do
    Req.Request.put_header(request, "x-ms-return-client-request-id", "true")
  end

  defp format_rfc1123_date do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()

    day_name = day_of_week(year, month, day)
    month_name = month_name(month)

    :io_lib.format("~s, ~2..0B ~s ~4..0B ~2..0B:~2..0B:~2..0B GMT", [
      day_name,
      day,
      month_name,
      year,
      hour,
      minute,
      second
    ])
    |> IO.iodata_to_binary()
  end

  defp day_of_week(year, month, day) do
    case :calendar.day_of_the_week(year, month, day) do
      1 -> "Mon"
      2 -> "Tue"
      3 -> "Wed"
      4 -> "Thu"
      5 -> "Fri"
      6 -> "Sat"
      7 -> "Sun"
    end
  end

  defp month_name(1), do: "Jan"
  defp month_name(2), do: "Feb"
  defp month_name(3), do: "Mar"
  defp month_name(4), do: "Apr"
  defp month_name(5), do: "May"
  defp month_name(6), do: "Jun"
  defp month_name(7), do: "Jul"
  defp month_name(8), do: "Aug"
  defp month_name(9), do: "Sep"
  defp month_name(10), do: "Oct"
  defp month_name(11), do: "Nov"
  defp month_name(12), do: "Dec"
end
