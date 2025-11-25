defmodule ExAzureCore.Http.Plugins.RequestId do
  @moduledoc """
  Req plugin that manages request ID tracking for Azure services.

  Generates a UUID for the `x-ms-client-request-id` header if not already present,
  enabling request correlation across Azure services.

  ## Headers

    * `x-ms-client-request-id` - Client-generated request ID (UUID)
    * `x-ms-request-id` - Server-generated request ID (extracted from response)

  ## Options

    * `:request_id` - Override the generated request ID with a specific value

  ## Example

      req = Req.new()
      |> ExAzureCore.Http.Plugins.RequestId.attach()

      # With custom request ID
      req = Req.new()
      |> ExAzureCore.Http.Plugins.RequestId.attach(request_id: "my-custom-id")
  """

  import Bitwise

  @client_request_id_header "x-ms-client-request-id"

  @doc """
  Attaches the request ID plugin to a Req request.
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts \\ []) do
    request
    |> Req.Request.register_options([:request_id])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(request_id: &add_request_id/1)
  end

  defp add_request_id(request) do
    request_id = request.options[:request_id] || generate_uuid()

    Req.Request.put_header(request, @client_request_id_header, request_id)
  end

  defp generate_uuid do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    c = (c &&& 0x0FFF) ||| 0x4000
    d = (d &&& 0x3FFF) ||| 0x8000

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c, d, e]
    )
    |> IO.iodata_to_binary()
    |> String.downcase()
  end
end
