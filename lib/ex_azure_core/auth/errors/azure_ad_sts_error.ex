defmodule ExAzureCore.Auth.Errors.AzureAdStsError do
  @moduledoc """
  Azure AD Security Token Service error with specific AADSTS error code handling.
  """
  use Splode.Error, fields: [:error_code, :description, :type], class: :authentication

  @impl true
  def message(%{error_code: error_code, description: description, type: type}) do
    "Azure AD STS Error (#{type}): #{error_code} - #{description}"
  end

  @doc """
  Handles Azure AD specific error responses.
  """
  def handle_error(error_response) when is_map(error_response) do
    error = Map.get(error_response, "error", "unknown")
    error_description = Map.get(error_response, "error_description", "No description provided")
    error_codes = Map.get(error_response, "error_codes", [])

    case handle_aadsts_error_codes(error_codes) do
      :no_specific_error ->
        case error do
          "invalid_client" ->
            {:error,
             __MODULE__.exception(
               error_code: :unknown,
               description: error_description,
               type: :invalid_client
             )}

          "invalid_scope" ->
            {:error,
             __MODULE__.exception(
               error_code: :unknown,
               description: error_description,
               type: :invalid_scope
             )}

          "invalid_request" ->
            {:error,
             __MODULE__.exception(
               error_code: :unknown,
               description: error_description,
               type: :invalid_request
             )}

          cause ->
            {:error,
             __MODULE__.exception(
               error_code: :unknown,
               description: "Authentication failed: #{cause}. #{error_description}",
               type: :authentication_failed
             )}
        end

      error_struct ->
        {:error, error_struct}
    end
  end

  def handle_error(error_response) do
    {:error,
     __MODULE__.exception(
       error_code: "unknown",
       description: inspect(error_response),
       type: :unknown
     )}
  end

  defp handle_aadsts_error_codes(error_codes) when is_list(error_codes) do
    cond do
      70_021 in error_codes ->
        __MODULE__.exception(
          error_code: 70_021,
          description: "The provided client secret is expired or invalid.",
          type: :federation_trust_mismatch
        )

      700_016 in error_codes ->
        __MODULE__.exception(
          error_code: 700_016,
          description: "The provided tenant ID is invalid or does not exist.",
          type: :invalid_tenant_id
        )

      50_027 in error_codes ->
        __MODULE__.exception(
          error_code: 50_027,
          description: "Invalid JWT token. Check certificate and signing.",
          type: :invalid_jwt
        )

      700_027 in error_codes ->
        __MODULE__.exception(
          error_code: 700_027,
          description: "Certificate not found in tenant configuration.",
          type: :certificate_not_found
        )

      true ->
        :no_specific_error
    end
  end

  defp handle_aadsts_error_codes(_error_codes) do
    :no_specific_error
  end
end
