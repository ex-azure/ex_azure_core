defmodule ExAzureCore.Auth.Errors.TokenServerError do
  @moduledoc """
  Error for token server operations.

  Used when token fetching fails or when an unknown token source type
  is specified.
  """
  use Splode.Error, fields: [:type, :name, :reason], class: :internal

  @type t() :: %__MODULE__{
          type: :fetch_failed | :unknown_source_type,
          name: atom(),
          reason: term()
        }

  @impl true
  def message(%{type: :fetch_failed, name: name, reason: reason}) do
    "Failed to fetch token from #{name}: #{inspect(reason)}"
  end

  def message(%{type: :unknown_source_type, name: _name, reason: source_type}) do
    "Unknown token source type: #{inspect(source_type)}"
  end
end
