defmodule A2aEngine.Types.Task do
  @moduledoc """
  An A2A Task: the unit of inter-agent work.

  Wire shape requires `kind: "task"`, `id`, `contextId`, `status`. Optional:
  `artifacts`, `history`, `metadata`.

  Note: per spec, `contextId` is REQUIRED on Task (though not on Message).
  """

  alias A2aEngine.Types.{Artifact, Message, TaskStatus}

  @type t :: %__MODULE__{
          id: String.t(),
          context_id: String.t(),
          status: TaskStatus.t(),
          artifacts: [Artifact.t()] | nil,
          history: [Message.t()] | nil,
          metadata: map() | nil
        }

  @enforce_keys [:id, :context_id, :status]
  defstruct [:id, :context_id, :status, :artifacts, :history, :metadata]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = t) do
    %{
      "kind" => "task",
      "id" => t.id,
      "contextId" => t.context_id,
      "status" => TaskStatus.to_map(t.status)
    }
    |> maybe_put("artifacts", t.artifacts && Enum.map(t.artifacts, &Artifact.to_map/1))
    |> maybe_put("history", t.history && Enum.map(t.history, &Message.to_map/1))
    |> maybe_put("metadata", t.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"id" => id, "contextId" => ctx, "status" => status_map} = m)
      when is_binary(id) and is_binary(ctx) and is_map(status_map) do
    cond do
      Map.get(m, "kind") not in [nil, "task"] ->
        {:error, {:invalid_kind, m["kind"]}}

      true ->
        with {:ok, status} <- TaskStatus.from_map(status_map),
             {:ok, artifacts} <- decode_list(m["artifacts"], &Artifact.from_map/1),
             {:ok, history} <- decode_list(m["history"], &Message.from_map/1) do
          {:ok,
           %__MODULE__{
             id: id,
             context_id: ctx,
             status: status,
             artifacts: artifacts,
             history: history,
             metadata: m["metadata"]
           }}
        end
    end
  end

  def from_map(_), do: {:error, :invalid_task}

  defp decode_list(nil, _fn), do: {:ok, nil}

  defp decode_list(list, decode_fn) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case decode_fn.(item) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _} = e -> e
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
