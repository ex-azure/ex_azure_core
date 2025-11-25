defmodule ExAzureCore.Http.Plugins.SharedKey do
  @moduledoc """
  Req plugin that adds Azure Storage Shared Key authentication.

  Implements the Shared Key authorization scheme for Azure Storage services.
  Builds a signature string from the request and signs it with HMAC-SHA256.

  Supports both raw name/key options and `AzureNamedKeyCredential` structs.

  ## Options

    * `:account_name` - Azure Storage account name
    * `:account_key` - Azure Storage account key, Base64-encoded
    * `:named_key_credential` - `%AzureNamedKeyCredential{}` (alternative to name/key)

  ## Example

      # Using raw options
      req = Req.new()
      |> ExAzureCore.Http.Plugins.SharedKey.attach(
        account_name: "myaccount",
        account_key: "base64key=="
      )

      # Using AzureNamedKeyCredential
      {:ok, credential} = AzureNamedKeyCredential.new("myaccount", "base64key==")
      req = Req.new()
      |> ExAzureCore.Http.Plugins.SharedKey.attach(named_key_credential: credential)

  ## Authorization Header Format

      Authorization: SharedKey account:signature
  """

  alias ExAzureCore.Credentials.AzureNamedKeyCredential

  @doc """
  Attaches the shared key plugin to a Req request.
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts \\ []) do
    request
    |> Req.Request.register_options([:account_name, :account_key, :named_key_credential])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(shared_key: &add_shared_key/1)
  end

  defp add_shared_key(request) do
    case get_account_info(request.options) do
      {:ok, account_name, account_key} ->
        signature = compute_signature(request, account_name, account_key)
        auth_header = "SharedKey #{account_name}:#{signature}"
        Req.Request.put_header(request, "authorization", auth_header)

      :none ->
        request
    end
  end

  defp get_account_info(%{named_key_credential: %AzureNamedKeyCredential{name: name, key: key}}) do
    {:ok, name, key}
  end

  defp get_account_info(%{account_name: name, account_key: key})
       when is_binary(name) and is_binary(key) do
    {:ok, name, key}
  end

  defp get_account_info(_), do: :none

  defp compute_signature(request, _account_name, account_key) do
    string_to_sign = build_string_to_sign(request)
    decoded_key = Base.decode64!(account_key)

    :crypto.mac(:hmac, :sha256, decoded_key, string_to_sign)
    |> Base.encode64()
  end

  defp build_string_to_sign(request) do
    method = request.method |> to_string() |> String.upcase()

    headers = normalize_headers(request.headers)

    content_encoding = Map.get(headers, "content-encoding", "")
    content_language = Map.get(headers, "content-language", "")
    content_length = get_content_length(headers, request.body)
    content_md5 = Map.get(headers, "content-md5", "")
    content_type = Map.get(headers, "content-type", "")
    date = Map.get(headers, "date", "")
    if_modified_since = Map.get(headers, "if-modified-since", "")
    if_match = Map.get(headers, "if-match", "")
    if_none_match = Map.get(headers, "if-none-match", "")
    if_unmodified_since = Map.get(headers, "if-unmodified-since", "")
    range = Map.get(headers, "range", "")

    canonicalized_headers = build_canonicalized_headers(headers)
    canonicalized_resource = build_canonicalized_resource(request)

    [
      method,
      content_encoding,
      content_language,
      content_length,
      content_md5,
      content_type,
      date,
      if_modified_since,
      if_match,
      if_none_match,
      if_unmodified_since,
      range,
      canonicalized_headers,
      canonicalized_resource
    ]
    |> Enum.join("\n")
  end

  defp normalize_headers(headers) do
    headers
    |> Enum.map(fn {k, v} ->
      key = k |> to_string() |> String.downcase()
      value = if is_list(v), do: List.first(v), else: to_string(v)
      {key, value}
    end)
    |> Map.new()
  end

  defp get_content_length(headers, body) do
    case Map.get(headers, "content-length") do
      nil when is_nil(body) -> ""
      nil when is_binary(body) -> to_string(byte_size(body))
      nil -> ""
      len -> len
    end
  end

  defp build_canonicalized_headers(headers) do
    headers
    |> Enum.filter(fn {k, _v} -> String.starts_with?(k, "x-ms-") end)
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map_join("\n", fn {k, v} -> "#{k}:#{String.trim(v)}" end)
  end

  defp build_canonicalized_resource(request) do
    account_name = request.options[:account_name]

    {path, query} =
      case request.url do
        %URI{path: path, query: query} ->
          {path || "/", query}

        url when is_binary(url) ->
          uri = URI.parse(url)
          {uri.path || "/", uri.query}

        _ ->
          {"/", nil}
      end

    resource = "/#{account_name}#{path}"

    if query do
      query_params =
        query
        |> URI.decode_query()
        |> Enum.sort_by(fn {k, _v} -> String.downcase(k) end)
        |> Enum.map_join(fn {k, v} -> "\n#{String.downcase(k)}:#{v}" end)

      resource <> query_params
    else
      resource
    end
  end
end
