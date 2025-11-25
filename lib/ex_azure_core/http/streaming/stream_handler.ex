defmodule ExAzureCore.Http.Streaming.StreamHandler do
  @moduledoc """
  Utilities for handling streaming HTTP responses.

  Provides helper functions for streaming large responses like blob downloads,
  event streams, and other streaming Azure APIs.

  ## Streaming to File

      StreamHandler.download_to_file(client, url, "/path/to/file.bin")

  ## Streaming with Callback

      StreamHandler.stream_with_callback(client, url, fn chunk, acc ->
        # Process each chunk
        {:cont, acc + byte_size(chunk)}
      end, 0)

  ## Streaming to Process

      StreamHandler.stream_to_self(client, url)
      receive do
        {:data, chunk} -> process(chunk)
      end
  """

  alias ExAzureCore.Http.Client
  alias ExAzureCore.Http.Request

  @doc """
  Downloads a response body directly to a file.

  ## Options

    * `:headers` - Additional headers for the request
    * `:params` - Query parameters

  ## Returns

    * `{:ok, response}` - Response metadata (status, headers)
    * `{:error, reason}` - Download failed
  """
  @spec download_to_file(Client.client(), String.t(), Path.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def download_to_file(client, url, file_path, opts \\ []) do
    file_stream = File.stream!(file_path, [:write, :binary])

    request_opts = [
      method: :get,
      url: url,
      into: file_stream
    ]

    request_opts = add_optional_opts(request_opts, opts)

    case Req.request(client, request_opts) do
      {:ok, response} ->
        {:ok,
         %{
           status: response.status,
           headers: response.headers,
           path: file_path
         }}

      {:error, reason} ->
        File.rm(file_path)
        {:error, reason}
    end
  end

  @doc """
  Streams response with a callback function.

  The callback receives each chunk and an accumulator, and should return
  `{:cont, new_acc}` to continue or `{:halt, final_acc}` to stop.

  ## Returns

    * `{:ok, {response, final_acc}}` - Streaming completed
    * `{:error, reason}` - Streaming failed
  """
  @spec stream_with_callback(
          Client.client(),
          String.t(),
          (binary(), acc -> {:cont, acc} | {:halt, acc}),
          acc,
          keyword()
        ) :: {:ok, {map(), acc}} | {:error, term()}
        when acc: term()
  def stream_with_callback(client, url, callback, initial_acc, opts \\ []) do
    into_fun = fn {:data, data}, {req, resp} ->
      case callback.(data, resp.private[:stream_acc] || initial_acc) do
        {:cont, new_acc} ->
          new_resp = %{resp | private: Map.put(resp.private, :stream_acc, new_acc)}
          {:cont, {req, new_resp}}

        {:halt, final_acc} ->
          new_resp = %{resp | private: Map.put(resp.private, :stream_acc, final_acc)}
          {:halt, {req, new_resp}}
      end
    end

    request_opts = [
      method: :get,
      url: url,
      into: into_fun
    ]

    request_opts = add_optional_opts(request_opts, opts)

    case Req.request(client, request_opts) do
      {:ok, response} ->
        final_acc = response.private[:stream_acc] || initial_acc

        {:ok,
         {
           %{status: response.status, headers: response.headers},
           final_acc
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Streams response chunks to the calling process.

  The calling process will receive messages in the format:
    * `{:chunk, data}` - A chunk of data
    * `{:done, response}` - Streaming completed

  ## Returns

    * `{:ok, ref}` - Reference to the streaming request
    * `{:error, reason}` - Request failed to start
  """
  @spec stream_to_self(Client.client(), String.t(), keyword()) ::
          {:ok, reference()} | {:error, term()}
  def stream_to_self(client, url, opts \\ []) do
    caller = self()
    ref = make_ref()

    spawn_link(fn ->
      into_fun = fn {:data, data}, {req, resp} ->
        send(caller, {:chunk, ref, data})
        {:cont, {req, resp}}
      end

      request_opts = [
        method: :get,
        url: url,
        into: into_fun
      ]

      request_opts = add_optional_opts(request_opts, opts)

      case Req.request(client, request_opts) do
        {:ok, response} ->
          send(caller, {:done, ref, %{status: response.status, headers: response.headers}})

        {:error, reason} ->
          send(caller, {:error, ref, reason})
      end
    end)

    {:ok, ref}
  end

  @doc """
  Creates a request struct configured for streaming.
  """
  @spec streaming_request(String.t(), keyword()) :: Request.t()
  def streaming_request(url, opts \\ []) do
    Request.new(
      method: Keyword.get(opts, :method, :get),
      url: url,
      headers: Keyword.get(opts, :headers, %{}),
      query: Keyword.get(opts, :params, %{}),
      options: Keyword.get(opts, :options, [])
    )
  end

  defp add_optional_opts(request_opts, opts) do
    request_opts
    |> maybe_add_headers(opts[:headers])
    |> maybe_add_params(opts[:params])
  end

  defp maybe_add_headers(opts, nil), do: opts
  defp maybe_add_headers(opts, headers), do: Keyword.put(opts, :headers, headers)

  defp maybe_add_params(opts, nil), do: opts
  defp maybe_add_params(opts, params), do: Keyword.put(opts, :params, params)
end
