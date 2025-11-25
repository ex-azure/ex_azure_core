defmodule ExAzureCore.Auth.Errors.ManagedIdentityError do
  @moduledoc """
  Error for managed identity and workload identity operations.

  Used when fetching tokens from Azure IMDS, App Service identity endpoint,
  or AKS Workload Identity fails.
  """
  use Splode.Error, fields: [:type, :provider, :reason, :status], class: :external

  @type t() :: %__MODULE__{
          type:
            :imds_unavailable
            | :identity_not_found
            | :token_file_not_found
            | :token_file_read_error
            | :environment_not_detected
            | :provider_error
            | :invalid_response,
          provider: atom(),
          reason: term(),
          status: integer() | nil
        }

  @impl true
  def message(%{type: :imds_unavailable, reason: reason}) do
    "Azure IMDS endpoint is unavailable: #{format_reason(reason)}"
  end

  def message(%{type: :identity_not_found, provider: provider}) do
    "No managed identity found for provider #{provider}"
  end

  def message(%{type: :token_file_not_found, reason: path}) do
    "Workload identity token file not found: #{path}"
  end

  def message(%{type: :token_file_read_error, reason: reason}) do
    "Failed to read workload identity token file: #{format_reason(reason)}"
  end

  def message(%{type: :environment_not_detected}) do
    "Could not detect Azure environment (IMDS, App Service, or AKS Workload Identity)"
  end

  def message(%{type: :provider_error, provider: provider, reason: reason, status: status})
      when not is_nil(status) do
    "#{provider} returned error (HTTP #{status}): #{format_reason(reason)}"
  end

  def message(%{type: :provider_error, provider: provider, reason: reason}) do
    "#{provider} returned error: #{format_reason(reason)}"
  end

  def message(%{type: :invalid_response, provider: provider, reason: reason}) do
    "Invalid response from #{provider}: #{format_reason(reason)}"
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
