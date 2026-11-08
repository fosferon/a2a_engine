# A2aEngine

> Pure-spec implementation of the [Agent2Agent (A2A) protocol](https://a2a-protocol.org/) — types, JSON-RPC 2.0 codec, SSE codec, and a transport behaviour.

A2A defines how agents call each other: JSON-RPC 2.0 envelopes over HTTPS
(with SSE for streaming), a typed `Task` / `Message` / `Part` / `Artifact`
model, `AgentCard` discovery, and push-notification config. **A2aEngine**
implements that wire contract in Elixir and nothing more.

It is deliberately **stateless**. There is no database, no broker, no process
registry, no opinion about where a Task lives or how it is resumed. The host
application owns all state — this library gives it the vocabulary and the
plumbing to move A2A messages over any transport it chooses.

## Why this shape?

Most protocol libraries bundle a server, a store, and a client. That's
convenient until two of your agents already live in the same BEAM cluster and
you'd rather not pay the HTTP/JSON round-trip. A2aEngine splits the contract
from the substrate:

* **One semantic contract** — `message/send`, `message/stream`, `tasks/get`,
  `tasks/cancel`, push-notification config, `agent/getAuthenticatedExtendedCard`.
* **Two interchangeable transports** that honour it — `Transport.Http`
  (JSON-RPC over HTTPS + SSE) and `Transport.BeamNative` (Phoenix.PubSub
  between always-on nodes, sub-millisecond, no serialisation).
* **A conformance suite** that runs every scenario against *both* transports,
  so semantic drift between them is a failing test, not a production surprise.

Bring your own handler, your own auth, your own task store — wire them into a
transport and you speak A2A.

## Installation

Add `a2a_engine` to your dependencies:

```elixir
def deps do
  [
    {:a2a_engine, "~> 0.1.1"}
  ]
end
```

Documentation is published at [https://hexdocs.pm/a2a_engine](https://hexdocs.pm/a2a_engine).

## What's in the box

| Area | Modules |
| --- | --- |
| **Spec types** | `A2aEngine.Types.*` — `Task`, `Message`, `Part` (`Text`/`File`/`Data`), `Artifact`, `AgentCard`, `PushNotificationConfig`, lifecycle events, … |
| **Codec** | `Codec.JsonRpc` (envelopes + A2A method registry), `Codec.SSE` (encode/decode + `Last-Event-ID` resumption), `Codec.Keys` (camelCase ↔ snake_case) |
| **Transport** | `Transport` (behaviour), `Transport.Http` (+ `.Plug`), `Transport.BeamNative` (+ `.Server`) |
| **Auth** | `Auth` (behaviour), `Auth.Bearer` (shared-secret), `Auth.Localhost` (same-host bypass) |
| **Core** | `Handler` (request/stream callback behaviour), `Errors` (A2A JSON-RPC codes), `LifecycleState` (task state enum), `Parts` (checkpoint-owner filtering) |
| **Testing** | `TestPeer` — a scriptable in-process A2A peer with a real HTTP server, shipped in `lib/` so hosts can reuse it |

## Quick tour

### JSON-RPC envelopes

```elixir
alias A2aEngine.Codec.JsonRpc

# Build an outbound request
request =
  JsonRpc.encode_request("message/send", %{"message" => msg}, "req-1")
  # => %{"jsonrpc" => "2.0", "id" => "req-1",
  #       "method" => "message/send", "params" => %{"message" => msg}}

# Decode an inbound request
{:ok, %{id: id, method: method, params: params}} =
  JsonRpc.decode_request(envelope)

# Decode a response (success or error)
{:ok, {:success, id, result}} = JsonRpc.decode_response(envelope)
{:ok, {:error, id, %{code: code, message: msg}}} = JsonRpc.decode_response(envelope)

# The A2A method registry
:true = JsonRpc.known_method?("message/send")
:message_send = JsonRpc.atom_for_method("message/send")
```

`params` and `result` pass through as plain maps — encode/decode the A2A types
(via `A2aEngine.Types.*`) on either side of the envelope.

### SSE streaming with resumption

```elixir
alias A2aEngine.Codec.SSE

# Encode an event frame (id scheme: "<task_id>:<seq>")
frame =
  "task-42"
  |> SSE.encode_event("status-update", 3, %{"kind" => "status-update", "status" => %{"state" => "working"}})
  |> IO.iodata_to_binary()
# => "id: task-42:3\nevent: status-update\ndata: {...}\n\n"

# Resume a stream from the Last-Event-ID header
{:ok, {"task-42", 3}} = SSE.resume_from(last_event_id)
{:error, :no_last_event_id} = SSE.resume_from(nil)
```

### Implement a handler

A handler is a behaviour that fulfils JSON-RPC methods. It is
transport-agnostic — both transports dispatch to the same callbacks.

```elixir
defmodule MyApp.A2A.Broker do
  @behaviour A2aEngine.Handler

  alias A2aEngine.Errors

  @impl true
  def handle_request("tasks/get", %{"id" => id}, _ctx) do
    {:ok, fetch_task!(id)}
  end

  def handle_request("message/send", params, ctx) do
    # ctx.auth carries the authenticated principal
    {:ok, run_message(params, ctx.auth)}
  end

  def handle_request(_method, _params, _ctx) do
    {:error, Errors.build(Errors.method_not_found())}
  end

  @impl true
  def handle_stream("message/stream", params, ctx, emit) do
    emit.(%{"kind" => "status-update", "status" => %{"state" => "working"}})
    emit.(%{"kind" => "status-update", "status" => %{"state" => "completed"}})
    {:ok, :done}
  end
end
```

### Call an agent over HTTP

```elixir
alias A2aEngine.{Codec.JsonRpc, Transport.Http}

request = JsonRpc.encode_request("message/send", %{"message" => msg}, "req-1")

# Unary
{:ok, response} =
  Http.send_request("https://agent.example/a2a", request,
    headers: [{"authorization", "Bearer " <> token}]
  )

# Streaming — returns a lazy Enumerable of decoded events
{:ok, stream} = Http.stream_request("https://agent.example/a2a", request)
for event <- stream, do: handle_event(event)
```

### Serve A2A from a Plug

```elixir
# in your router or Endpoint
forward "/a2a", A2aEngine.Transport.Http.Plug,
  handler: MyApp.A2A.Broker,
  auth: A2aEngine.Auth.Bearer,
  auth_opts: [tokens: %{"secret" => "my-agent"}]
```

The plug reads and decodes the request body itself, dispatches to the handler,
and returns a JSON-RPC response — or an SSE stream for `message/stream` /
`tasks/resubscribe`.

### Test against a scriptable peer

`TestPeer` spins up a real Bandit HTTP server on a random port and lets you
script responses per method. Ship your integration tests without standing up
a fake agent by hand.

Bandit is an optional dependency of `a2a_engine`: the library compiles and runs
without it unless you use `A2aEngine.TestPeer`, which starts a real Bandit
server. Add Bandit to your project's dependencies when you use `TestPeer` —
typically test-only:

```elixir
{:bandit, "~> 1.5", only: :test}
```

```elixir
{:ok, peer} = A2aEngine.TestPeer.start_link()
url = A2aEngine.TestPeer.url(peer)

A2aEngine.TestPeer.script(peer, "message/send", fn _params ->
  {:ok, %{"kind" => "task", "id" => "t1", "status" => %{"state" => "completed"}}}
end)

{:ok, response} = A2aEngine.Transport.Http.send_request(url, request)
```

## Design notes

* **camelCase on the wire, snake_case in Elixir.** The A2A wire format is
  camelCase; `Codec.Keys` converts between the two. Envelopes stay as plain
  maps so you decide when (and whether) to round-trip through the typed
  structs in `A2aEngine.Types.*`.
* **Auth at the boundary.** Each transport calls an `A2aEngine.Auth`
  implementation before touching the handler. A rejection never reaches your
  business logic. `Bearer` and `Localhost` ship built-in; OAuth2/OIDC
  implementations slot in as additional modules without changing the behaviour.
* **Checkpoint-in-envelope.** `A2aEngine.Parts` supports a convention where a
  worker stashes resumable state in a `DataPart` tagged
  `metadata: {"type" => "checkpoint", "owner" => <agent>, "session" => <id>}`.
  `Parts.filter_by_owner/2` ensures a broker only forwards each checkpoint to
  its producer, so per-agent private state never leaks across hops.

## Companion packages

<!-- public-guard: allow (Hex user profile URL) -->
Part of the [fosferon](https://hex.pm/users/fosferon) Elixir stack. Related
public packages include [`llm_core`](https://hex.pm/packages/llm_core) (LLM
orchestration), [`agent_engine`](https://hex.pm/packages/agent_engine) (agent
runtime), [`workflow_stem`](https://hex.pm/packages/workflow_stem) (workflow
runtime), and [`bee_tracker`](https://hex.pm/packages/bee_tracker) (work
coordination). The full list is on
[Hex](https://hex.pm/packages?search=fosferon).

## License

MIT. See [LICENSE](LICENSE).
