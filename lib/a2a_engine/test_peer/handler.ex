defmodule A2aEngine.TestPeer.Handler do
  @moduledoc false
  # Bridge between A2aEngine.Handler and A2aEngine.TestPeer. Reads the
  # peer pid from the request context and delegates dispatch decisions
  # to the peer's scripted state.

  @behaviour A2aEngine.Handler

  alias A2aEngine.TestPeer

  @impl true
  def handle_request(method, params, %{peer: peer}) when is_pid(peer) do
    TestPeer.dispatch_unary(peer, method, params)
  end

  def handle_request(_method, _params, _ctx) do
    {:error, %{code: -32_603, message: "TestPeer.Handler: missing :peer in context"}}
  end

  @impl true
  def handle_stream(method, params, %{peer: peer}, emit_fn) when is_pid(peer) do
    case TestPeer.fetch_stream_script(peer, method, params) do
      {:ok, fun} -> fun.(params || %{}, emit_fn)
      :error -> {:error, %{code: -32_601, message: "TestPeer has no stream script for #{method}"}}
    end
  end

  def handle_stream(_method, _params, _ctx, _emit_fn) do
    {:error, %{code: -32_603, message: "TestPeer.Handler: missing :peer in context"}}
  end
end
