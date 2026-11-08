defmodule A2aEngine.Transport.Http do
  @moduledoc """
  HTTP transport for A2A. Client-side implementation of
  `A2aEngine.Transport`; pairs with `A2aEngine.Transport.Http.Plug` on the
  server side.

  Uses `Req` for unary requests and for SSE streaming.

  ## target

  A URL string (e.g. `"https://agent.example/a2a"`). The A2A
  JSON-RPC envelope is POSTed to this URL.

  ## opts

    * `:headers` — extra headers to include (e.g. `Authorization`).
    * `:timeout` — request timeout in ms (default 30 000 for unary,
      60 000 for streams).
    * `:req_opts` — any additional options to pass through to `Req`.

  ## Streaming

  `stream_request/3` returns `{:ok, stream}` where `stream` is a lazy
  `Enumerable` producing decoded SSE event payloads (maps). The
  underlying Req task runs in a linked process; closing the stream early
  stops the task.
  """

  @behaviour A2aEngine.Transport

  alias A2aEngine.Codec.SSE

  @default_unary_timeout 30_000
  @default_stream_timeout 60_000

  # ---- unary ----

  @impl true
  def send_request(url, request, opts \\ []) when is_binary(url) do
    headers =
      [{"content-type", "application/json"}]
      |> merge_headers(Keyword.get(opts, :headers, []))

    req_opts =
      [
        url: url,
        method: :post,
        headers: headers,
        json: request,
        receive_timeout: Keyword.get(opts, :timeout, @default_unary_timeout)
      ]
      |> Keyword.merge(Keyword.get(opts, :req_opts, []))

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---- streaming ----

  @impl true
  def stream_request(url, request, opts \\ []) when is_binary(url) do
    headers =
      [
        {"content-type", "application/json"},
        {"accept", "text/event-stream"}
      ]
      |> merge_headers(Keyword.get(opts, :headers, []))

    timeout = Keyword.get(opts, :timeout, @default_stream_timeout)
    caller = self()
    ref = make_ref()

    task =
      Task.async(fn ->
        req_opts =
          [
            url: url,
            method: :post,
            headers: headers,
            json: request,
            receive_timeout: timeout,
            into: fn {:data, chunk}, {req, resp} ->
              send(caller, {ref, :chunk, chunk})
              {:cont, {req, resp}}
            end
          ]
          |> Keyword.merge(Keyword.get(opts, :req_opts, []))

        result = Req.request(req_opts)
        send(caller, {ref, :done, result})
      end)

    stream =
      Stream.resource(
        fn -> %{ref: ref, task: task, buffer: "", halted?: false} end,
        &next_event/1,
        fn state ->
          # Drain any remaining messages addressed to this ref to avoid leaking.
          flush(state.ref)
          :ok
        end
      )

    {:ok, stream}
  end

  # ---- stream helpers ----

  defp next_event(%{halted?: true} = state), do: {:halt, state}

  defp next_event(state) do
    # Parse any complete frames from the current buffer first.
    case take_frame(state.buffer) do
      {:ok, frame, rest} ->
        case SSE.decode_event(frame) do
          {:ok, parsed} ->
            case decode_payload(parsed.data) do
              {:ok, event} -> {[event], %{state | buffer: rest}}
              :end -> {:halt, %{state | buffer: rest, halted?: true}}
              {:error, _} -> {[], %{state | buffer: rest}}
            end

          {:error, _} ->
            {[], %{state | buffer: rest}}
        end

      :more ->
        read_more(state)
    end
  end

  defp read_more(%{ref: ref} = state) do
    receive do
      {^ref, :chunk, chunk} ->
        next_event(%{state | buffer: state.buffer <> chunk})

      {^ref, :done, {:ok, %Req.Response{status: status}}} when status in 200..299 ->
        {:halt, %{state | halted?: true}}

      {^ref, :done, {:ok, %Req.Response{}}} ->
        {:halt, %{state | halted?: true}}

      {^ref, :done, {:error, _}} ->
        {:halt, %{state | halted?: true}}
    after
      30_000 -> {:halt, %{state | halted?: true}}
    end
  end

  defp take_frame(buffer) do
    case :binary.match(buffer, "\n\n") do
      {start, 2} ->
        frame = binary_part(buffer, 0, start + 2)
        rest = binary_part(buffer, start + 2, byte_size(buffer) - (start + 2))
        {:ok, frame, rest}

      :nomatch ->
        :more
    end
  end

  defp decode_payload(data) do
    case Jason.decode(data) do
      {:ok, %{"kind" => _} = event} -> {:ok, event}
      {:ok, %{}} -> :end
      {:ok, _} -> {:error, :not_a_map}
      {:error, reason} -> {:error, reason}
    end
  end

  defp flush(ref) do
    receive do
      {^ref, _, _} -> flush(ref)
    after
      0 -> :ok
    end
  end

  defp merge_headers(base, extra) when is_list(base) and is_list(extra), do: base ++ extra
end
