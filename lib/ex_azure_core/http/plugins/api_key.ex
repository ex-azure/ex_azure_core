defmodule ExAzureCore.Http.Plugins.ApiKey do
  @moduledoc """
  Req plugin that adds API key authentication to requests.

  Adds the API key as a header with a configurable name.
  Supports both raw string keys and `AzureKeyCredential` structs.

  ## Options

    * `:api_key` - The API key (string or `%AzureKeyCredential{}`)
    * `:header_name` - Header name (default: "api-key")
    * `:prefix` - Optional prefix for the header value (e.g., "Bearer")

  ## Common Header Names by Service

    * Cognitive Services: "Ocp-Apim-Subscription-Key"
    * Azure Search: "api-key"
    * Form Recognizer: "Ocp-Apim-Subscription-Key"
    * Translator: "Ocp-Apim-Subscription-Key"

  ## Example

      # Using a string key
      req = Req.new()
      |> ExAzureCore.Http.Plugins.ApiKey.attach(api_key: "my-key")

      # Using an AzureKeyCredential
      {:ok, credential} = AzureKeyCredential.new("my-key")
      req = Req.new()
      |> ExAzureCore.Http.Plugins.ApiKey.attach(api_key: credential)

      # With custom header name (Cognitive Services)
      req = Req.new()
      |> ExAzureCore.Http.Plugins.ApiKey.attach(
        api_key: "my-key",
        header_name: "Ocp-Apim-Subscription-Key"
      )

      # With prefix
      req = Req.new()
      |> ExAzureCore.Http.Plugins.ApiKey.attach(
        api_key: "my-key",
        prefix: "ApiKey"
      )
  """

  alias ExAzureCore.Credentials.AzureKeyCredential

  @default_header "api-key"

  @doc """
  Attaches the API key plugin to a Req request.
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts \\ []) do
    request
    |> Req.Request.register_options([:api_key, :header_name, :prefix])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(api_key: &add_api_key/1)
  end

  defp add_api_key(request) do
    case get_key(request.options) do
      {:ok, key} ->
        header_name = Map.get(request.options, :header_name, @default_header)
        prefix = Map.get(request.options, :prefix)
        value = if prefix, do: "#{prefix} #{key}", else: key
        Req.Request.put_header(request, header_name, value)

      {:error, reason} ->
        %{request | private: Map.put(request.private, :api_key_error, reason)}
    end
  end

  defp get_key(%{api_key: %AzureKeyCredential{key: key}}), do: {:ok, key}
  defp get_key(%{api_key: key}) when is_binary(key) and byte_size(key) > 0, do: {:ok, key}
  defp get_key(%{api_key: _}), do: {:error, :invalid_api_key}
  defp get_key(_), do: {:error, :no_api_key_configured}
end
