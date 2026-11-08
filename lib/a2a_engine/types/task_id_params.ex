defmodule A2aEngine.Types.TaskIdParams do
  @moduledoc """
  Params wrapper for `tasks/cancel`, `tasks/resubscribe`, and similar methods
  that identify a task by id only.

  Wire fields: `id` (required), `metadata`.
  """

  @type t :: %__MODULE__{id: String.t(), metadata: map() | nil}

  @enforce_keys [:id]
  defstruct [:id, :metadata]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = p) do
    %{"id" => p.id}
    |> maybe_put("metadata", p.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"id" => id} = m) when is_binary(id) do
    {:ok, %__MODULE__{id: id, metadata: m["metadata"]}}
  end

  def from_map(_), do: {:error, :invalid_task_id_params}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
