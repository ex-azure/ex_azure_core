defmodule ExAzureCore.Errors.NetworkError do
  @moduledoc """
  Network-related error when connecting to external services fails.
  """
  use Splode.Error, fields: [:service, :endpoint, :reason], class: :external

  @type t() :: %__MODULE__{
          service: String.t(),
          endpoint: String.t() | nil,
          reason: any()
        }

  @impl true
  def message(%{service: service, endpoint: endpoint, reason: reason}) do
    "Failed to connect to service #{service}" <>
      if endpoint, do: " at endpoint #{endpoint} ", else: " " <> "Cause: #{inspect(reason)}"
  end
end
