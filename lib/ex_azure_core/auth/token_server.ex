defmodule ExAzureCore.Auth.TokenServer do
  @moduledoc """
  GenServer for managing individual credential tokens with proactive refresh.

  Each TokenServer instance manages a single credential's token lifecycle:
  - Fetches tokens from configured source
  - Stores tokens in Registry for efficient lookup
  - Proactively schedules refresh before expiry
  - Implements exponential backoff retry logic on failures

  ## Options

    * `:name` (required) - Unique name for this credential instance
    * `:source` (required) - Token source configuration tuple
    * `:refresh_before` - Seconds before expiry to refresh (default: 300)
    * `:prefetch` - Initial token fetch strategy (`:async` or `:sync`, default: `:async`)
    * `:max_retries` - Maximum retry attempts (default: 10)
    * `:retry_delay` - Custom backoff function (default: exponential backoff)

  ## Examples

      {:ok, _pid} = ExAzureCore.Auth.TokenServer.start_link(
        name: :my_credential,
        source: {:client_assertion, %{
          tenant_id: "...",
          client_id: "...",
          scope: "https://graph.microsoft.com/.default",
          provider: :aws_cognito,
          provider_opts: [identity_id: "..."]
        }},
        prefetch: :sync
      )

      {:ok, token} = ExAzureCore.Auth.TokenServer.fetch(:my_credential)
  """

  use GenServer

  require Logger

  alias ExAzureCore.Auth.Errors.ConfigurationError
  alias ExAzureCore.Auth.Errors.TokenServerError
  alias ExAzureCore.Auth.TokenSource

  @default_refresh_before 300
  @default_max_retries 10
  @default_prefetch :async

  @type state :: %{
          name: term(),
          source: term(),
          refresh_before: non_neg_integer(),
          max_retries: non_neg_integer(),
          retry_delay: (non_neg_integer() -> non_neg_integer()),
          retry_count: non_neg_integer()
        }

  @doc """
  Starts a token server for a credential.

  ## Options

  See module documentation for available options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  @doc """
  Fetches the current token from the token server.

  Returns the cached token if available, otherwise fetches a new one.
  """
  @spec fetch(term()) :: {:ok, map()} | {:error, term()}
  def fetch(name) do
    GenServer.call(via_tuple(name), :fetch)
  catch
    :exit, reason ->
      {:error, TokenServerError.exception(type: :fetch_failed, name: name, reason: reason)}
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    source = Keyword.fetch!(opts, :source)
    refresh_before = Keyword.get(opts, :refresh_before, @default_refresh_before)
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    retry_delay = Keyword.get(opts, :retry_delay, &exp_backoff/1)
    prefetch = Keyword.get(opts, :prefetch, @default_prefetch)

    state = %{
      name: name,
      source: source,
      refresh_before: refresh_before,
      max_retries: max_retries,
      retry_delay: retry_delay,
      retry_count: 0
    }

    case prefetch do
      :sync ->
        case fetch_token(state) do
          {:ok, token} ->
            state = store_and_schedule_refresh(state, token)
            {:ok, state}

          {:error, reason} ->
            Logger.warning("Initial token fetch failed: #{inspect(reason)}")
            send(self(), :refresh)
            {:ok, state}
        end

      :async ->
        send(self(), :refresh)
        {:ok, state}

      _ ->
        {:stop,
         ConfigurationError.exception(type: :invalid_option, key: :prefetch, value: prefetch)}
    end
  end

  @impl true
  def handle_call(:fetch, _from, state) do
    case lookup_token(state.name) do
      {:ok, token} ->
        {:reply, {:ok, token}, state}

      :error ->
        case fetch_token(state) do
          {:ok, token} ->
            state = store_and_schedule_refresh(state, token)
            {:reply, {:ok, token}, state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    case fetch_token(state) do
      {:ok, token} ->
        state = store_and_schedule_refresh(state, token)
        {:noreply, state}

      {:error, reason} when state.retry_count < state.max_retries ->
        Logger.warning(
          "Token fetch failed for #{state.name} (attempt #{state.retry_count + 1}): #{inspect(reason)}"
        )

        delay = state.retry_delay.(state.retry_count)
        Process.send_after(self(), :refresh, delay)
        {:noreply, %{state | retry_count: state.retry_count + 1}}

      {:error, reason} ->
        Logger.error(
          "Token fetch failed for #{state.name} after #{state.max_retries} retries: #{inspect(reason)}"
        )

        Process.send_after(self(), :refresh, 30_000)
        {:noreply, %{state | retry_count: 0}}
    end
  end

  defp fetch_token(%{source: {source_type, config}}) do
    case source_type do
      :client_assertion ->
        TokenSource.ClientAssertion.fetch_token(config)

      :managed_identity ->
        TokenSource.ManagedIdentity.fetch_token(config)

      :workload_identity ->
        TokenSource.WorkloadIdentity.fetch_token(config)

      other ->
        {:error, TokenServerError.exception(type: :unknown_source_type, name: nil, reason: other)}
    end
  end

  defp store_and_schedule_refresh(state, token) do
    Registry.update_value(ExAzureCore.Auth.Registry, state.name, fn _ -> token end)

    time_in_seconds =
      max(
        token.expires_at - System.system_time(:second) - state.refresh_before,
        0
      )

    Process.send_after(self(), :refresh, time_in_seconds * 1000)

    %{state | retry_count: 0}
  end

  defp lookup_token(name) do
    case Registry.lookup(ExAzureCore.Auth.Registry, name) do
      [{_pid, token}] -> {:ok, token}
      [] -> :error
    end
  end

  defp exp_backoff(retry_count) do
    min(30, round(:math.pow(2, retry_count))) * 1000
  end

  defp via_tuple(name) do
    {:via, Registry, {ExAzureCore.Auth.Registry, name}}
  end
end
