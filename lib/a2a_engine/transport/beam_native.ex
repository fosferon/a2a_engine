defmodule A2aEngine.Transport.BeamNative do
  @moduledoc """
  BEAM-native A2A transport.

  Uses `GenServer.call/3` for unary requests (request-reply semantics are
  a perfect fit; cross-node works natively) and `Phoenix.PubSub` for
  streaming (server broadcasts events on a per-stream topic; client
  subscribes and assembles a `Stream`).

  Same semantic contract as `A2aEngine.Transport.Http`, sub-ms latency
  for connected BEAM peers.

  ## Server

  Hosts add `A2aEngine.Transport.BeamNative.Server` to their supervision
  tree (or `start_link` directly). See that module's docs.

  ## Client

  `send_request/3` — unary call. `target` may be a local atom
  (`:my_agent`), a remote tuple (`{:my_agent, :"node@host"}`), or a pid.

  `stream_request/3` — streaming call. Host-level opts must include
  `:pubsub` naming a running `Phoenix.PubSub`.

  ## Targeting

  The standard Erlang `GenServer` call mechanics apply: atoms for local
  names, `{name, node}` tuples for remote names, or pids.
  """

  @behaviour A2aEngine.Transport

  alias A2aEngine.Codec.JsonRpc
  alias A2aEngine.Errors

  @default_timeout 30_000
  @stream_timeout 60_000

  # ---- Transport behaviour ----

  @impl true
  def send_request(target, request, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    try do
      response = GenServer.call(target, {:a2a_request, request}, timeout)
      {:ok, response}
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, {:noproc, _} -> {:error, :noproc}
      :exit, reason -> {:error, {:exit, reason}}
    end
  end

  @impl true
  def stream_request(target, request, opts \\ []) do
    pubsub =
      Keyword.get(opts, :pubsub) ||
        raise ArgumentError, "BeamNative.stream_request requires :pubsub in opts"

    timeout = Keyword.get(opts, :timeout, @stream_timeout)

    nonce = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    topic = "a2a_stream:" <> nonce

    :ok = Phoenix.PubSub.subscribe(pubsub, topic)

    case GenServer.call(target, {:a2a_stream, request, pubsub, topic}, timeout) do
      :ok ->
        {:ok, build_stream(pubsub, topic, timeout)}

      other ->
        :ok = Phoenix.PubSub.unsubscribe(pubsub, topic)
        {:error, {:server_rejected, other}}
    end
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, {:noproc, _} -> {:error, :noproc}
    :exit, reason -> {:error, {:exit, reason}}
  end

  # ---- helpers ----

  defp build_stream(pubsub, topic, timeout) do
    Stream.resource(
      fn -> %{pubsub: pubsub, topic: topic, timeout: timeout} end,
      fn state ->
        receive do
          {:a2a_event, event} -> {[event], state}
          {:a2a_stream_error, error} -> {[{:error, error}], put_in(state[:halt], true)}
          :a2a_stream_end -> {:halt, state}
        after
          state.timeout -> {:halt, state}
        end
      end,
      fn state ->
        Phoenix.PubSub.unsubscribe(state.pubsub, state.topic)
      end
    )
  end

  # ---- Server-side helpers (invoked by Server GenServer) ----

  @doc false
  # Shared request-processing pipeline: decode → auth → dispatch → encode.
  # Used by BeamNative.Server and by TestPeer so both share identical semantics.
  @spec handle_decoded(
          request :: map(),
          from_info :: A2aEngine.Auth.request_info(),
          opts :: keyword()
        ) :: map()
  def handle_decoded(request, from_info, opts) do
    handler = Keyword.fetch!(opts, :handler)
    auth = Keyword.fetch!(opts, :auth)
    auth_opts = Keyword.get(opts, :auth_opts, [])
    handler_ctx = Keyword.get(opts, :handler_ctx, %{})

    with {:ok, decoded} <- JsonRpc.decode_request(request),
         {:ok, auth_ctx} <- auth.authenticate(from_info, auth_opts) do
      ctx = Map.merge(%{auth: auth_ctx, id: decoded.id}, handler_ctx)

      case A2aEngine.Handler.dispatch(handler, decoded, ctx, nil) do
        {:ok, result} ->
          JsonRpc.encode_success(decoded.id, result)

        {:error, error} ->
          JsonRpc.encode_error(decoded.id, error)
      end
    else
      {:error, :unauthenticated} ->
        JsonRpc.encode_error(nil, Errors.invalid_request(), "Unauthenticated")

      {:error, :forbidden} ->
        JsonRpc.encode_error(nil, Errors.invalid_request(), "Forbidden")

      {:error, reason} ->
        JsonRpc.encode_error(nil, Errors.invalid_request(), inspect(reason))
    end
  end
end
