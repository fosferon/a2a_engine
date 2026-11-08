defmodule A2aEngine.Transport.BeamNative.Server do
  @moduledoc """
  GenServer that receives A2A requests over the BEAM-native transport.

  Hosts start this under their supervision tree with a handler module and
  an auth module:

      {A2aEngine.Transport.BeamNative.Server,
       name: :my_agent_a2a,
       handler: MyApp.A2A.Handler,
       auth: A2aEngine.Auth.Localhost,
       auth_opts: [],
       pubsub: MyApp.PubSub}

  The `name` becomes the call target (`GenServer.call(:my_agent_a2a, ...)`).
  """

  use GenServer

  alias A2aEngine.Codec.JsonRpc
  alias A2aEngine.Errors
  alias A2aEngine.Transport.BeamNative

  @type opts :: [
          handler: module(),
          auth: module(),
          auth_opts: keyword(),
          pubsub: atom(),
          name: atom()
        ]

  def start_link(opts) do
    {name_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, name_opts)
  end

  @impl true
  def init(opts) do
    state = %{
      handler: Keyword.fetch!(opts, :handler),
      auth: Keyword.fetch!(opts, :auth),
      auth_opts: Keyword.get(opts, :auth_opts, []),
      handler_ctx: Keyword.get(opts, :handler_ctx, %{}),
      pubsub: Keyword.get(opts, :pubsub)
    }

    {:ok, state}
  end

  # ---- unary request ----

  @impl true
  def handle_call({:a2a_request, request}, {from_pid, _tag}, state) do
    from_info = %{
      headers: %{},
      peer: {:beam, node(from_pid)},
      transport: :beam_native
    }

    response =
      BeamNative.handle_decoded(request, from_info,
        handler: state.handler,
        auth: state.auth,
        auth_opts: state.auth_opts,
        handler_ctx: state.handler_ctx
      )

    {:reply, response, state}
  end

  # ---- streaming request ----

  def handle_call({:a2a_stream, request, pubsub, topic}, {from_pid, _tag}, state) do
    from_info = %{
      headers: %{},
      peer: {:beam, node(from_pid)},
      transport: :beam_native
    }

    Task.start(fn -> run_stream(request, from_info, state, pubsub, topic) end)

    {:reply, :ok, state}
  end

  # ---- stream task ----

  defp run_stream(request, from_info, state, pubsub, topic) do
    with {:ok, decoded} <- JsonRpc.decode_request(request),
         {:ok, auth_ctx} <- state.auth.authenticate(from_info, state.auth_opts) do
      ctx = Map.merge(%{auth: auth_ctx, id: decoded.id}, state.handler_ctx)

      emit_fn = fn event ->
        Phoenix.PubSub.broadcast(pubsub, topic, {:a2a_event, event})
        :ok
      end

      case A2aEngine.Handler.dispatch(state.handler, decoded, ctx, emit_fn) do
        {:ok, _final} ->
          Phoenix.PubSub.broadcast(pubsub, topic, :a2a_stream_end)

        {:error, error} ->
          Phoenix.PubSub.broadcast(pubsub, topic, {:a2a_stream_error, error})
          Phoenix.PubSub.broadcast(pubsub, topic, :a2a_stream_end)
      end
    else
      {:error, reason} ->
        error = %{code: Errors.invalid_request(), message: inspect(reason)}
        Phoenix.PubSub.broadcast(pubsub, topic, {:a2a_stream_error, error})
        Phoenix.PubSub.broadcast(pubsub, topic, :a2a_stream_end)
    end
  end
end
