defmodule A2aEngine.Transport.Http.Plug do
  @moduledoc """
  Plug that receives A2A JSON-RPC requests over HTTP.

  Mount in your router:

      forward "/a2a", A2aEngine.Transport.Http.Plug,
        handler: MyApp.A2A.Handler,
        auth: A2aEngine.Auth.Bearer,
        auth_opts: [tokens: %{"secret" => "my-agent"}]

  ## Behaviour

    * POST `/` — unary JSON-RPC. Returns 200 with JSON-RPC response
      envelope, or 401 / 400 on auth / decode failure.
    * POST `/` with `Accept: text/event-stream` AND a method in the
      streaming set (`message/stream`, `tasks/resubscribe`) — responds
      with SSE chunks. Each event frame follows `A2aEngine.Codec.SSE`.
    * Any other path or method → 404.

  The plug reads and decodes the request body itself; no upstream parser is
  required. Do not mount it behind a body-consuming parser (for example,
  `Plug.Parsers` configured for JSON), because the plug reads the raw request
  body itself.

  ## Options

    * `:handler` — required. Module implementing `A2aEngine.Handler`.
    * `:auth` — required. Module implementing `A2aEngine.Auth`.
    * `:auth_opts` — keyword list passed to the auth module.
  """

  @behaviour Plug

  import Plug.Conn

  alias A2aEngine.Codec.{JsonRpc, SSE}
  alias A2aEngine.{Errors, Handler}

  @streaming_methods MapSet.new(["message/stream", "tasks/resubscribe"])

  @impl true
  def init(opts) do
    _handler = Keyword.fetch!(opts, :handler)
    _auth = Keyword.fetch!(opts, :auth)
    opts
  end

  @impl true
  def call(%Plug.Conn{method: "POST"} = conn, opts) do
    dispatch(conn, opts)
  end

  def call(conn, _opts) do
    send_resp(conn, 404, "A2A endpoint only accepts POST")
  end

  # ---- main dispatch ----

  defp dispatch(conn, opts) do
    with {:ok, body, conn} <- read_full_body(conn),
         {:ok, envelope} <- Jason.decode(body),
         %{"jsonrpc" => _} <- envelope do
      handle_envelope(conn, envelope, opts)
    else
      %{} ->
        respond_json(
          conn,
          400,
          JsonRpc.encode_error(nil, Errors.parse_error(), "Body is not a JSON-RPC envelope")
        )

      {:error, %Jason.DecodeError{} = err} ->
        respond_json(
          conn,
          400,
          JsonRpc.encode_error(nil, Errors.parse_error(), Exception.message(err))
        )

      {:error, :body_too_large} ->
        respond_json(conn, 413, JsonRpc.encode_error(nil, Errors.parse_error(), "Body too large"))

      {:error, reason} ->
        respond_json(
          conn,
          400,
          JsonRpc.encode_error(nil, Errors.parse_error(), inspect(reason))
        )
    end
  end

  @max_body_bytes 16 * 1024 * 1024

  defp read_full_body(conn, acc \\ "") do
    case Plug.Conn.read_body(conn) do
      {:ok, body, conn} ->
        {:ok, acc <> body, conn}

      {:more, partial, conn} ->
        if byte_size(acc) + byte_size(partial) > @max_body_bytes do
          {:error, :body_too_large}
        else
          read_full_body(conn, acc <> partial)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_envelope(conn, envelope, opts) do
    request_info = build_request_info(conn)
    auth_mod = Keyword.fetch!(opts, :auth)
    auth_opts = Keyword.get(opts, :auth_opts, [])

    with {:ok, decoded} <- JsonRpc.decode_request(envelope),
         {:ok, auth_ctx} <- auth_mod.authenticate(request_info, auth_opts) do
      route(conn, decoded, auth_ctx, opts)
    else
      {:error, :unauthenticated} ->
        conn
        |> put_resp_header("www-authenticate", ~s|Bearer realm="a2a"|)
        |> respond_json(401, %{"error" => "unauthenticated"})

      {:error, :forbidden} ->
        respond_json(conn, 403, %{"error" => "forbidden"})

      {:error, reason} ->
        respond_json(
          conn,
          400,
          JsonRpc.encode_error(envelope["id"], Errors.invalid_request(), inspect(reason))
        )
    end
  end

  defp route(conn, decoded, auth_ctx, opts) do
    handler = Keyword.fetch!(opts, :handler)
    extra_ctx = Keyword.get(opts, :handler_ctx, %{})
    ctx = Map.merge(%{auth: auth_ctx, id: decoded.id}, extra_ctx)

    if MapSet.member?(@streaming_methods, decoded.method) and accepts_sse?(conn) do
      run_streaming(conn, decoded, ctx, handler)
    else
      run_unary(conn, decoded, ctx, handler)
    end
  end

  # ---- unary ----

  defp run_unary(conn, decoded, ctx, handler) do
    response =
      case Handler.dispatch(handler, decoded, ctx, nil) do
        {:ok, result} ->
          JsonRpc.encode_success(decoded.id, result)

        {:error, error} ->
          JsonRpc.encode_error(decoded.id, error)
      end

    respond_json(conn, 200, response)
  end

  # ---- streaming (SSE) ----

  defp run_streaming(conn, decoded, ctx, handler) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    task_id = extract_task_id(decoded)
    seq_ref = :counters.new(1, [:atomics])

    emit_fn = fn event ->
      :counters.add(seq_ref, 1, 1)
      seq = :counters.get(seq_ref, 1)
      event_name = event_kind(event)

      frame = SSE.encode_event(task_id, event_name, seq, event)

      case chunk(conn, frame) do
        {:ok, _} -> :ok
        {:error, _} = err -> throw({:chunk_error, err})
      end
    end

    try do
      case Handler.dispatch(handler, decoded, ctx, emit_fn) do
        {:ok, _final} ->
          _ = chunk(conn, SSE.encode_event(task_id, "end", next_seq(seq_ref), %{}))
          conn

        {:error, error} ->
          _ = chunk(conn, SSE.encode_event(task_id, "error", next_seq(seq_ref), error))
          conn
      end
    catch
      {:chunk_error, _} -> conn
    end
  end

  defp next_seq(ref) do
    :counters.add(ref, 1, 1)
    :counters.get(ref, 1)
  end

  defp event_kind(%{"kind" => kind}), do: kind
  defp event_kind(_), do: "message"

  defp extract_task_id(%{params: %{"message" => %{"taskId" => tid}}}), do: tid
  defp extract_task_id(%{params: %{"id" => id}}), do: id
  defp extract_task_id(_), do: "stream"

  # ---- helpers ----

  defp build_request_info(conn) do
    %{
      headers: headers_to_map(conn.req_headers),
      peer: {:tcp, conn.remote_ip},
      transport: :http
    }
  end

  defp headers_to_map(list) when is_list(list) do
    Enum.into(list, %{}, fn {k, v} -> {String.downcase(k), v} end)
  end

  defp accepts_sse?(conn) do
    case get_req_header(conn, "accept") do
      [] -> false
      values -> Enum.any?(values, &String.contains?(&1, "text/event-stream"))
    end
  end

  defp respond_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  @doc """
  Whether a method is one of the A2A streaming methods that this plug
  will respond to with an SSE stream (provided the client sends
  `Accept: text/event-stream`).
  """
  @spec streaming?(String.t()) :: boolean()
  def streaming?(method), do: MapSet.member?(@streaming_methods, method)
end
