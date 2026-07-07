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
    next_key = Keyword.fetch!(opts, :next_link)

    paginate(config, initial_op, opts, fn body ->
      case Map.get(body, next_key) do
        url when is_binary(url) and url != "" -> {:cont, next_op(initial_op, url)}
        _ -> :halt
      end
    end)
  end

  @doc """
  Builds a lazy `Stream` that walks continuation-token pagination.

  Fetches `initial_op`, extracts the page's items and a continuation token from
  each response body, decodes each item, and re-issues the *same* operation with
  the token set on a request parameter until the token is absent.

  ## Options

    * `:items` - response body key holding the page's item list (required)
    * `:token_response` - response body key holding the continuation token (required)
    * `:token_query` - query parameter name to carry the token on the next request
    * `:token_header` - header name to carry the token (use instead of `:token_query`)
    * `:decode` - 1-arity function applied to each raw item (default: identity)
  """
  @spec continuation_stream(map(), Operation.t(), keyword()) :: Enumerable.t()
  def continuation_stream(config, initial_op, opts) do
    token_key = Keyword.fetch!(opts, :token_response)
    put_token = token_putter(opts)

    paginate(config, initial_op, opts, fn body ->
      case Map.get(body, token_key) do
        token when is_nil(token) or token == "" -> :halt
        token -> {:cont, put_token.(initial_op, token)}
      end
    end)
  end

  # Shared page-walk: fetch a page, emit decoded items, then let `advance` decide
  # the next operation (or `:halt`) from the raw response body.
  defp paginate(config, initial_op, opts, advance) do
    items_key = Keyword.fetch!(opts, :items)
    decode = Keyword.get(opts, :decode, & &1)

    Stream.resource(
      fn -> {:cont, initial_op} end,
      fn
        :halt ->
          {:halt, nil}

        {:cont, op} ->
          body = fetch_body(op, config)
          items = body |> Map.get(items_key) |> List.wrap() |> Enum.map(decode)
          {items, advance.(body)}
      end,
      fn _ -> :ok end
    )
  end

  defp token_putter(opts) do
    cond do
      name = Keyword.get(opts, :token_query) ->
        fn op, token -> %{op | params: Map.put(op.params || %{}, name, token)} end

      name = Keyword.get(opts, :token_header) ->
        fn op, token ->
          headers = List.keystore(op.headers || [], name, 0, {name, to_string(token)})
          %{op | headers: headers}
        end

      true ->
        raise ArgumentError, "continuation_stream requires :token_query or :token_header"
    end
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
