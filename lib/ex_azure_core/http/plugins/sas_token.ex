defmodule ExAzureCore.Http.Plugins.SasToken do
  @moduledoc """
  Req plugin that adds Shared Access Signature (SAS) token authentication.

  Appends the SAS token to the request URL as query parameters.
  SAS tokens provide delegated access to Azure Storage resources.

  Supports both raw string tokens and `AzureSasCredential` structs.

  ## Options

    * `:sas_token` - The SAS token (string or `%AzureSasCredential{}`)

  ## Example

      # Using a string
      req = Req.new()
      |> ExAzureCore.Http.Plugins.SasToken.attach(
        sas_token: "sv=2021-06-08&ss=b&srt=sco&sp=rwdlacupitfx&se=..."
      )

      # Using an AzureSasCredential
      {:ok, credential} = AzureSasCredential.new("sv=2021-06-08&ss=b...")
      req = Req.new()
      |> ExAzureCore.Http.Plugins.SasToken.attach(sas_token: credential)
  """

  alias ExAzureCore.Credentials.AzureSasCredential

  @doc """
  Attaches the SAS token plugin to a Req request.
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts \\ []) do
    request
    |> Req.Request.register_options([:sas_token])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(sas_token: &add_sas_token/1)
  end

  defp add_sas_token(request) do
    case get_sas_token(request.options) do
      {:ok, sas_token} ->
        token = normalize_sas_token(sas_token)
        append_sas_to_url(request, token)

      :none ->
        request
    end
  end

  defp get_sas_token(%{sas_token: %AzureSasCredential{signature: sig}}), do: {:ok, sig}
  defp get_sas_token(%{sas_token: token}) when is_binary(token), do: {:ok, token}
  defp get_sas_token(_), do: :none

  defp normalize_sas_token(token) do
    token
    |> String.trim_leading("?")
    |> String.trim()
  end

  defp append_sas_to_url(request, sas_token) do
    url = request.url

    new_url =
      case url do
        %URI{} = uri ->
          append_to_uri(uri, sas_token)

        url when is_binary(url) ->
          uri = URI.parse(url)
          append_to_uri(uri, sas_token) |> URI.to_string()
      end

    %{request | url: new_url}
  end

  defp append_to_uri(%URI{query: nil} = uri, sas_token) do
    %{uri | query: sas_token}
  end

  defp append_to_uri(%URI{query: ""} = uri, sas_token) do
    %{uri | query: sas_token}
  end

  defp append_to_uri(%URI{query: existing} = uri, sas_token) do
    %{uri | query: "#{existing}&#{sas_token}"}
  end
end
