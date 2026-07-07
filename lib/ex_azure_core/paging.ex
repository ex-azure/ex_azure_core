defmodule ExAzureCore.Paging do
  @moduledoc """
  Helpers for building lazy streams over paginated Azure responses.

  Generated SDK operations that page via a `nextLink` set their
  `:stream_builder` to a closure that delegates here, so the page-walking
  logic lives (and is tested) in one place.
  """

  alias ExAzureCore.Operation

  @doc """
  Builds a lazy `Stream` that walks `nextLink`-style pagination.

  Fetches `initial_op`, extracts the page's items and the next-page URL from
  each response body, decodes each item, and follows the link until it is
  absent. The next-page request targets the absolute `nextLink` URL, preserving
  its query (e.g. the continuation token) while `api-version` is still injected
  from config.

  ## Options

    * `:items` - response body key holding the page's item list (required)
    * `:next_link` - response body key holding the next-page URL (required)
    * `:decode` - 1-arity function applied to each raw item (default: identity)
  """
  @spec nextlink_stream(map(), Operation.t(), keyword()) :: Enumerable.t()
  def nextlink_stream(config, initial_op, opts) do
    items_key = Keyword.fetch!(opts, :items)
    next_key = Keyword.fetch!(opts, :next_link)
    decode = Keyword.get(opts, :decode, & &1)

    Stream.resource(
      fn -> {:cont, initial_op} end,
      fn
        :halt ->
          {:halt, nil}

        {:cont, op} ->
          body = fetch_body(op, config)
          items = body |> Map.get(items_key) |> List.wrap() |> Enum.map(decode)

          case Map.get(body, next_key) do
            url when is_binary(url) and url != "" -> {items, {:cont, next_op(initial_op, url)}}
            _ -> {items, :halt}
          end
      end,
      fn _ -> :ok end
    )
  end

  defp fetch_body(op, config) do
    case Operation.perform(%{op | parser: nil, stream_builder: nil}, config) do
      {:ok, %{body: body}} -> body
      {:error, error} -> raise error
    end
  end

  defp next_op(op, url) do
    uri = URI.parse(url)
    params = if uri.query, do: URI.decode_query(uri.query), else: %{}

    %{
      op
      | host: "#{uri.scheme}://#{host_with_port(uri)}",
        path: uri.path || "/",
        params: params,
        body: nil,
        parser: nil,
        stream_builder: nil
    }
  end

  defp host_with_port(%URI{host: host, port: port, scheme: scheme}) do
    default = if scheme == "https", do: 443, else: 80
    if port && port != default, do: "#{host}:#{port}", else: host
  end
end
