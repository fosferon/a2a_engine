defmodule A2aEngine.Types.TaskArtifactUpdateEvent do
  @moduledoc """
  A streaming event published when an artifact is generated or updated.
  Emitted during `message/stream` and `tasks/resubscribe`.

  Wire shape requires `kind: "artifact-update"`, `taskId`, `contextId`,
  `artifact`. Optional: `append` (concatenate to prior artifact with same id),
  `lastChunk` (final chunk marker).
  """

  alias A2aEngine.Types.Artifact

  @type t :: %__MODULE__{
          task_id: String.t(),
          context_id: String.t(),
          artifact: Artifact.t(),
          append: boolean() | nil,
          last_chunk: boolean() | nil,
          metadata: map() | nil
        }

  @enforce_keys [:task_id, :context_id, :artifact]
  defstruct [:task_id, :context_id, :artifact, :append, :last_chunk, :metadata]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = e) do
    %{
      "kind" => "artifact-update",
      "taskId" => e.task_id,
      "contextId" => e.context_id,
      "artifact" => Artifact.to_map(e.artifact)
    }
    |> maybe_put("append", e.append)
    |> maybe_put("lastChunk", e.last_chunk)
    |> maybe_put("metadata", e.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(
        %{
          "kind" => "artifact-update",
          "taskId" => tid,
          "contextId" => ctx,
          "artifact" => artifact_map
        } = m
      )
      when is_binary(tid) and is_binary(ctx) and is_map(artifact_map) do
    with {:ok, artifact} <- Artifact.from_map(artifact_map) do
      {:ok,
       %__MODULE__{
         task_id: tid,
         context_id: ctx,
         artifact: artifact,
         append: m["append"],
         last_chunk: m["lastChunk"],
         metadata: m["metadata"]
       }}
    end
  end

  def from_map(_), do: {:error, :invalid_artifact_update_event}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
