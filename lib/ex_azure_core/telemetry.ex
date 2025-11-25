defmodule ExAzureCore.Telemetry do
  @moduledoc """
  Telemetry events for ExAzureCore operations.

  ## Events

  ExAzureCore emits the following telemetry events:

  ### `[:ex_azure_core, :request, :start]`

  Emitted when a request starts.

  Measurements:
  - `:system_time` - System time at start (from `System.system_time()`)

  Metadata:
  - `:service` - Service atom (e.g., `:storage`, `:keyvault`)
  - `:method` - HTTP method
  - `:path` - Request path

  ### `[:ex_azure_core, :request, :stop]`

  Emitted when a request completes (success or error).

  Measurements:
  - `:duration` - Request duration in native time units

  Metadata:
  - `:service` - Service atom
  - `:method` - HTTP method
  - `:path` - Request path
  - `:result` - `:ok` or `:error`

  ### `[:ex_azure_core, :request, :exception]`

  Emitted when a request raises an exception.

  Measurements:
  - `:duration` - Time until exception in native time units

  Metadata:
  - `:service` - Service atom
  - `:kind` - Exception kind (`:error`, `:exit`, `:throw`)
  - `:reason` - Exception reason
  - `:stacktrace` - Exception stacktrace

  ## Usage

  Attach handlers in your application startup:

      :telemetry.attach_many(
        "my-app-azure-handler",
        [
          [:ex_azure_core, :request, :start],
          [:ex_azure_core, :request, :stop],
          [:ex_azure_core, :request, :exception]
        ],
        &MyApp.AzureTelemetry.handle_event/4,
        nil
      )
  """

  @prefix [:ex_azure_core, :request]

  @doc """
  Executes a function with telemetry span events.

  Emits `:start` before execution, `:stop` after successful completion,
  and `:exception` if the function raises.

  ## Parameters

  - `operation` - The operation being executed (for metadata)
  - `config` - The resolved configuration
  - `fun` - The function to execute (should return `{:ok, _}` or `{:error, _}`)
  """
  @spec span(struct(), map(), (-> result)) :: result when result: {:ok, term()} | {:error, term()}
  def span(operation, config, fun) when is_function(fun, 0) do
    metadata = build_metadata(operation, config)
    start_time = System.monotonic_time()

    emit_start(metadata)

    try do
      result = fun.()
      emit_stop(metadata, result, start_time)
      result
    rescue
      e ->
        emit_exception(metadata, :error, e, __STACKTRACE__, start_time)
        reraise e, __STACKTRACE__
    catch
      kind, reason ->
        emit_exception(metadata, kind, reason, __STACKTRACE__, start_time)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Emits a start event.
  """
  @spec emit_start(map()) :: :ok
  def emit_start(metadata) do
    :telemetry.execute(
      @prefix ++ [:start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a stop event.
  """
  @spec emit_stop(map(), {:ok, term()} | {:error, term()}, integer()) :: :ok
  def emit_stop(metadata, result, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @prefix ++ [:stop],
      %{duration: duration},
      Map.put(metadata, :result, result_status(result))
    )
  end

  @doc """
  Emits an exception event.
  """
  @spec emit_exception(map(), atom(), term(), list(), integer()) :: :ok
  def emit_exception(metadata, kind, reason, stacktrace, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @prefix ++ [:exception],
      %{duration: duration},
      Map.merge(metadata, %{
        kind: kind,
        reason: reason,
        stacktrace: stacktrace
      })
    )
  end

  defp build_metadata(operation, config) do
    %{
      service: Map.get(config, :service),
      method: get_method(operation),
      path: get_path(operation)
    }
  end

  defp get_method(%{http_method: method}), do: method
  defp get_method(_), do: nil

  defp get_path(%{path: path}), do: path
  defp get_path(_), do: nil

  defp result_status({:ok, _}), do: :ok
  defp result_status({:error, _}), do: :error
  defp result_status(_), do: :unknown
end
