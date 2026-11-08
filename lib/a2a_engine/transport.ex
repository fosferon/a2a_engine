defmodule A2aEngine.Transport do
  @moduledoc """
  Behaviour for A2A transports.

  A transport abstracts HOW bytes move between A2A participants. The
  library ships two implementations:

    * `A2aEngine.Transport.Http` — JSON-RPC over HTTPS with SSE streaming.
      The standard A2A wire. Use for external peers and any over-network
      call.
    * `A2aEngine.Transport.BeamNative` — Phoenix.PubSub-backed messaging
      between always-on BEAM nodes. Same semantics as Http but with
      sub-millisecond latency and no serialisation overhead. Use for
      in-cluster calls.

  Both transports honour the same semantic contract — this is what the
  conformance suite enforces.

  ## Callbacks

    * `send_request/3` — unary call. Sends a JSON-RPC request envelope
      to `target` and returns the decoded response envelope.

    * `stream_request/3` — streaming call (`message/stream`,
      `tasks/resubscribe`). Returns a stream of decoded events
      (`Task`, `Message`, `TaskStatusUpdateEvent`, `TaskArtifactUpdateEvent`).

  Cancellation is done by a separate `tasks/cancel` request through
  `send_request/3` — no dedicated callback.

  ## target shape

  Transport-specific:

    * Http: URL string like `"https://host/a2a"`.
    * BeamNative: a registered atom (local process name) or a
      `{node, name}` tuple for cross-node calls.
  """

  alias A2aEngine.Codec.JsonRpc

  @type target :: any()
  @type request :: JsonRpc.request()
  @type response :: JsonRpc.response()
  @type opts :: keyword()

  @callback send_request(target(), request(), opts()) ::
              {:ok, response()} | {:error, term()}

  @callback stream_request(target(), request(), opts()) ::
              {:ok, Enumerable.t()} | {:error, term()}
end
