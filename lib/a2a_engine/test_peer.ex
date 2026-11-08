defmodule A2aEngine.TestPeer do
  @moduledoc """
  Scriptable in-process A2A peer for integration tests.

  Ships in `lib/` (not `test/`) so consuming hosts can use it in their
  own test suites without having to reimplement this machinery.

  ## Usage

      {:ok, peer} = A2aEngine.TestPeer.start_link()
      url = A2aEngine.TestPeer.url(peer)

      A2aEngine.TestPeer.script(peer, "message/send", fn _params ->
        {:ok, %{"kind" => "task", "id" => "t1", "contextId" => "c1",
                "status" => %{"state" => "completed"}}}
      end)

      {:ok, response} = A2aEngine.Transport.Http.send_request(url, request)

      # Assert the peer saw what we expected
      assert A2aEngine.TestPeer.received(peer) == [{"message/send", %{...}}]

      A2aEngine.TestPeer.stop(peer)

  ## Streaming

      A2aEngine.TestPeer.script_stream(peer, "message/stream", fn _params, emit ->
        emit.(event1)
        emit.(event2)
        {:ok, :done}
      end)

  ## Options

    * `:auth` — `A2aEngine.Auth` module. Defaults to `Localhost`.
    * `:auth_opts` — keyword list passed to the auth module.
    * `:port` — fixed port (default 0 → random).
  """

  use GenServer

  alias A2aEngine.TestPeer.Handler

  @default_timeout 5_000

  @bandit_missing ~s|A2aEngine.TestPeer requires Bandit, which is an optional dependency of a2a_engine.\n| <>
                    ~s|Add {:bandit, "~> 1.5"} to your project's dependencies (typically `only: :test`),\n| <>
                    ~s|then run `mix deps.get`.\n|

  @type request_fn :: (params :: map() -> {:ok, term()} | {:error, map()})
  @type stream_fn ::
          (params :: map(), emit :: (map() -> :ok) -> {:ok, term()} | {:error, map()})

  # ---- client API ----

  @doc "Start a test peer with its own Bandit HTTP server on a random port."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    ensure_bandit!()
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Full base URL (scheme://host:port) where this peer accepts A2A requests."
  @spec url(pid()) :: String.t()
  def url(peer), do: GenServer.call(peer, :url, @default_timeout)

  @doc "TCP port the peer is bound to."
  @spec port(pid()) :: non_neg_integer()
  def port(peer), do: GenServer.call(peer, :port, @default_timeout)

  @doc """
  Install a unary response function for a JSON-RPC method.

  The function receives the decoded `params` map and returns
  `{:ok, result}` or `{:error, error_map}`.
  """
  @spec script(pid(), String.t(), request_fn()) :: :ok
  def script(peer, method, fun) when is_binary(method) and is_function(fun, 1) do
    GenServer.call(peer, {:script, method, fun}, @default_timeout)
  end

  @doc """
  Install a streaming response function for a JSON-RPC method.

  The function receives `(params, emit_fn)` and may call `emit_fn.(event)`
  zero or more times before returning `{:ok, term}` or `{:error, map}`.
  """
  @spec script_stream(pid(), String.t(), stream_fn()) :: :ok
  def script_stream(peer, method, fun) when is_binary(method) and is_function(fun, 2) do
    GenServer.call(peer, {:script_stream, method, fun}, @default_timeout)
  end

  @doc """
  List of `{method, params}` tuples that the peer has received, in order.
  """
  @spec received(pid()) :: [{String.t(), map() | nil}]
  def received(peer), do: GenServer.call(peer, :received, @default_timeout)

  @doc "Clear the `received` log (useful between assertions in one test)."
  @spec clear_received(pid()) :: :ok
  def clear_received(peer), do: GenServer.call(peer, :clear_received, @default_timeout)

  @doc "Stop the peer and its underlying Bandit server."
  @spec stop(pid()) :: :ok
  def stop(peer), do: GenServer.stop(peer)

  # ---- handler-facing API (called by A2aEngine.TestPeer.Handler) ----

  @doc false
  @spec dispatch_unary(pid(), String.t(), map() | nil) ::
          {:ok, term()} | {:error, map()}
  def dispatch_unary(peer, method, params) do
    GenServer.call(peer, {:dispatch_unary, method, params}, @default_timeout)
  end

  @doc false
  @spec fetch_stream_script(pid(), String.t(), map() | nil) ::
          {:ok, stream_fn()} | :error
  def fetch_stream_script(peer, method, params) do
    GenServer.call(peer, {:fetch_stream_script, method, params}, @default_timeout)
  end

  # ---- GenServer ----

  @impl true
  def init(opts) do
    # Also guard here so a direct GenServer.start_link/2 bypass gets the same
    # actionable error instead of an UndefinedFunctionError from apply/3.
    ensure_bandit!()

    auth = Keyword.get(opts, :auth, A2aEngine.Auth.Localhost)
    auth_opts = Keyword.get(opts, :auth_opts, [])
    port = Keyword.get(opts, :port, 0)

    plug_opts = [
      handler: Handler,
      auth: auth,
      auth_opts: auth_opts,
      handler_ctx: %{peer: self()}
    ]

    bandit_opts = [
      plug: {A2aEngine.Transport.Http.Plug, plug_opts},
      scheme: :http,
      port: port,
      startup_log: false
    ]

    # Called through apply/3 so this module compiles without warnings when the
    # optional Bandit dependency (and its ThousandIsland transitive dep) is absent.
    {:ok, bandit} = apply(Bandit, :start_link, [bandit_opts])
    {:ok, {_ip, bound_port}} = apply(ThousandIsland, :listener_info, [bandit])

    state = %{
      bandit: bandit,
      port: bound_port,
      scripts: %{},
      stream_scripts: %{},
      received: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:url, _from, state) do
    {:reply, "http://127.0.0.1:#{state.port}", state}
  end

  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call({:script, method, fun}, _from, state) do
    {:reply, :ok, %{state | scripts: Map.put(state.scripts, method, fun)}}
  end

  def handle_call({:script_stream, method, fun}, _from, state) do
    {:reply, :ok, %{state | stream_scripts: Map.put(state.stream_scripts, method, fun)}}
  end

  def handle_call(:received, _from, state) do
    {:reply, Enum.reverse(state.received), state}
  end

  def handle_call(:clear_received, _from, state) do
    {:reply, :ok, %{state | received: []}}
  end

  def handle_call({:dispatch_unary, method, params}, _from, state) do
    state = %{state | received: [{method, params} | state.received]}

    case Map.fetch(state.scripts, method) do
      {:ok, fun} ->
        {:reply, fun.(params || %{}), state}

      :error ->
        {:reply, {:error, %{code: -32_601, message: "TestPeer has no script for #{method}"}},
         state}
    end
  end

  def handle_call({:fetch_stream_script, method, params}, _from, state) do
    state = %{state | received: [{method, params} | state.received]}

    case Map.fetch(state.stream_scripts, method) do
      {:ok, fun} -> {:reply, {:ok, fun}, state}
      :error -> {:reply, :error, state}
    end
  end

  defp ensure_bandit! do
    unless Code.ensure_loaded?(Bandit) do
      raise @bandit_missing
    end
  end

  @impl true
  def terminate(_reason, state) do
    if is_pid(state.bandit) and Process.alive?(state.bandit) do
      Process.exit(state.bandit, :normal)
    end

    :ok
  end
end
