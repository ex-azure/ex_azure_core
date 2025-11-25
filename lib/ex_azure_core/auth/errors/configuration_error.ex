defmodule ExAzureCore.Auth.Errors.ConfigurationError do
  @moduledoc """
  Error for configuration validation failures.

  Used when required configuration is missing, values are invalid,
  or options are not recognized.
  """
  use Splode.Error, fields: [:type, :key, :value], class: :invalid

  @type t() :: %__MODULE__{
          type: :missing_required | :invalid_value | :invalid_option,
          key: atom(),
          value: term()
        }

  @impl true
  def message(%{type: :missing_required, key: key, value: _value}) do
    "Missing required configuration: #{inspect(key)}"
  end

  def message(%{type: :invalid_value, key: key, value: value}) do
    "Invalid value for #{inspect(key)}: #{inspect(value)}"
  end

  def message(%{type: :invalid_option, key: key, value: value}) do
    "Invalid option #{inspect(key)}: #{inspect(value)}. Valid options: :async, :sync"
  end
end
