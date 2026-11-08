defmodule A2aEngine.Types.TaskStatusUpdateEvent do
  @moduledoc """
  A streaming event published when a task's status changes. Emitted during
  `message/stream` and `tasks/resubscribe`.

  Wire shape requires `kind: "status-update"`, `taskId`, `contextId`,
  `status`, `final` (boolean — true if this is the last event in the stream).
  """

  alias A2aEngine.Types.TaskStatus

  @type t :: %__MODULE__{
          task_id: String.t(),
          context_id: String.t(),
          status: TaskStatus.t(),
          final: boolean(),
          metadata: map() | nil
        }

  @enforce_keys [:task_id, :context_id, :status, :final]
  defstruct [:task_id, :context_id, :status, :final, :metadata]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = e) do
    %{
      "kind" => "status-update",
      "taskId" => e.task_id,
      "contextId" => e.context_id,
      "status" => TaskStatus.to_map(e.status),
      "final" => e.final
    }
    |> maybe_put("metadata", e.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(
        %{
          "kind" => "status-update",
          "taskId" => tid,
          "contextId" => ctx,
          "status" => s,
          "final" => final
        } = m
      )
      when is_binary(tid) and is_binary(ctx) and is_map(s) and is_boolean(final) do
    with {:ok, status} <- TaskStatus.from_map(s) do
      {:ok,
       %__MODULE__{
         task_id: tid,
         context_id: ctx,
         status: status,
         final: final,
         metadata: m["metadata"]
       }}
    end
  end

  def from_map(_), do: {:error, :invalid_status_update_event}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
