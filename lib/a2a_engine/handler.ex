defmodule A2aEngine.Handler do
  @moduledoc """
  Contract for the A2A request handler — the module that actually fulfils
  JSON-RPC method calls once the transport has decoded + authenticated.

  The handler is transport-agnostic: both `A2aEngine.Transport.Http` and
  `A2aEngine.Transport.BeamNative` dispatch to the same handler contract.

  Hosts implement this behaviour in their own module (e.g.
  `MyApp.A2A.Broker`) and pass it to transports via opts.

  ## Callbacks

    * `handle_request/3` — for unary methods (`message/send`,
      `tasks/get`, `tasks/cancel`, `tasks/pushNotificationConfig/*`,
      `agent/getAuthenticatedExtendedCard`). Returns `{:ok, result}` on
      success or `{:error, error_map}` on failure.

    * `handle_stream/4` — for streaming methods (`message/stream`,
      `tasks/resubscribe`). Receives an `emit` callback that pushes events
      back to the caller. Returns `{:ok, final_result}` when the stream
      completes cleanly, or `{:error, error_map}` on failure.

  ## Method dispatch

  Transports call `dispatch/4` (this module) which pattern-matches known
  A2A streaming methods to `handle_stream/4` and everything else to
  `handle_request/3`. Hosts don't need to write that wiring themselves.
  """

  alias A2aEngine.Auth

  @type method :: String.t()
  @type params :: map() | nil
  @type context :: %{
          required(:auth) => Auth.auth_context(),
          required(:id) => String.t() | integer() | nil,
          optional(atom()) => any()
        }

  @type emit_fn :: (map() -> :ok)
  @type error_map :: %{
          required(:code) => integer(),
          required(:message) => String.t(),
          optional(:data) => map()
        }

  @callback handle_request(method(), params(), context()) ::
              {:ok, term()} | {:error, error_map()}

  @callback handle_stream(method(), params(), context(), emit_fn()) ::
              {:ok, term()} | {:error, error_map()}

  @streaming_methods MapSet.new(["message/stream", "tasks/resubscribe"])

  @doc """
  Dispatch a decoded JSON-RPC request to the right handler callback.

  Streaming methods go to `handle_stream/4` with the provided `emit_fn`;
  all other methods go to `handle_request/3`.
  """
  @spec dispatch(module(), map(), context(), emit_fn() | nil) ::
          {:ok, term()} | {:error, error_map()} | {:streaming, term()}
  def dispatch(handler_mod, decoded_request, context, emit_fn \\ nil) do
    %{method: method, params: params} = decoded_request

    if MapSet.member?(@streaming_methods, method) do
      stream_emit = emit_fn || raise ArgumentError, "streaming method requires emit_fn"
      handler_mod.handle_stream(method, params, context, stream_emit)
    else
      handler_mod.handle_request(method, params, context)
    end
  end

  @doc "Whether a method is an A2A streaming method (message/stream or tasks/resubscribe)."
  @spec streaming?(method()) :: boolean()
  def streaming?(method), do: MapSet.member?(@streaming_methods, method)
end
