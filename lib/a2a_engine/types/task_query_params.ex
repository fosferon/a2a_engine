defmodule A2aEngine.Types.TaskQueryParams do
  @moduledoc """
  Params wrapper for `tasks/get`.

  Wire fields: `id` (required), `historyLength` (optional), `metadata`.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          history_length: non_neg_integer() | nil,
          metadata: map() | nil
        }

  @enforce_keys [:id]
  defstruct [:id, :history_length, :metadata]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = p) do
    %{"id" => p.id}
    |> maybe_put("historyLength", p.history_length)
    |> maybe_put("metadata", p.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"id" => id} = m) when is_binary(id) do
    {:ok, %__MODULE__{id: id, history_length: m["historyLength"], metadata: m["metadata"]}}
  end

  def from_map(_), do: {:error, :invalid_task_query_params}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
