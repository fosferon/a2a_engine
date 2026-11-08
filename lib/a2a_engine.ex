defmodule A2aEngine do
  @moduledoc """
  A2A (Agent-to-Agent) protocol engine — pure spec library.

  Implements Google's A2A protocol types, JSON-RPC 2.0 codec, SSE codec,
  and a transport behaviour. Stateless. No broker. No DB. No HTTP server.

  Host applications pull this in to speak A2A over any
  transport they choose.

  ## Layout

    * `A2aEngine.Types.*` — spec data types (Task, Message, Part, Artifact,
      AgentCard, PushNotificationConfig, lifecycle events, …)
    * `A2aEngine.LifecycleState` — task state enum
    * `A2aEngine.Codec.JsonRpc` — JSON-RPC 2.0 request/response envelopes
    * `A2aEngine.Codec.SSE` — Server-Sent Events encoder/decoder with
      Last-Event-ID resumption
    * `A2aEngine.Codec.Keys` — camelCase ↔ snake_case key conversion
      (A2A wire format is camelCase; Elixir is snake_case)
    * `A2aEngine.Errors` — A2A-specific JSON-RPC error codes

  ## Checkpoint-in-envelope convention

  In the "checkpoint-in-envelope" pattern we use for ephemeral-worker
  resumption, the worker stashes its opaque resumable state
  in a `DataPart` with metadata:

      %{
        "type" => "checkpoint",
        "owner" => "<producer-agent-name>",
        "session" => "<conv-engine-session-id>"
      }

  The A2A spec has no opinion on metadata contents; this convention lives
  in application code. Brokers MUST route DataParts tagged as checkpoints
  back to their producer only, never to the counter-party.
  """
end
