defmodule A2aEngine.TestSupport.EchoHandler do
  @moduledoc """
  Minimal A2A handler used by transport tests. Echoes the incoming message
  back as a completed Task; streams two status updates on `message/stream`.
  """

  @behaviour A2aEngine.Handler

  @impl true
  def handle_request("message/send", %{"message" => message}, _ctx) do
    task = %{
      "kind" => "task",
      "id" => "echo_task_#{:rand.uniform(1_000_000)}",
      "contextId" => "echo_ctx",
      "status" => %{"state" => "completed", "timestamp" => now()},
      "history" => [message]
    }

    {:ok, task}
  end

  def handle_request("tasks/get", %{"id" => id}, _ctx) do
    {:ok,
     %{
       "kind" => "task",
       "id" => id,
       "contextId" => "echo_ctx",
       "status" => %{"state" => "working", "timestamp" => now()}
     }}
  end

  def handle_request("tasks/cancel", %{"id" => id}, _ctx) do
    {:ok,
     %{
       "kind" => "task",
       "id" => id,
       "contextId" => "echo_ctx",
       "status" => %{"state" => "canceled", "timestamp" => now()}
     }}
  end

  def handle_request(method, _params, _ctx) do
    {:error, %{code: -32_601, message: "Method not found: #{method}"}}
  end

  @impl true
  def handle_stream("message/stream", _params, _ctx, emit_fn) do
    task_id = "stream_task_#{:rand.uniform(1_000_000)}"

    :ok =
      emit_fn.(%{
        "kind" => "status-update",
        "taskId" => task_id,
        "contextId" => "echo_ctx",
        "status" => %{"state" => "working", "timestamp" => now()},
        "final" => false
      })

    :ok =
      emit_fn.(%{
        "kind" => "status-update",
        "taskId" => task_id,
        "contextId" => "echo_ctx",
        "status" => %{"state" => "completed", "timestamp" => now()},
        "final" => true
      })

    {:ok, :done}
  end

  def handle_stream(method, _params, _ctx, _emit_fn) do
    {:error, %{code: -32_601, message: "Streaming method not found: #{method}"}}
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
