defmodule A2aEngine.Types.Message do
  @moduledoc """
  A single message in the conversation between a user and an agent.

  Required: `messageId`, `role` (`"user" | "agent"`), `parts`. Always carries
  `kind: "message"` on the wire.
  """

  alias A2aEngine.Types.Part

  @type role :: String.t()
  @type t :: %__MODULE__{
          message_id: String.t(),
          role: role(),
          parts: [Part.t()],
          context_id: String.t() | nil,
          task_id: String.t() | nil,
          reference_task_ids: [String.t()] | nil,
          extensions: [String.t()] | nil,
          metadata: map() | nil
        }

  @enforce_keys [:message_id, :role, :parts]
  defstruct [
    :message_id,
    :role,
    :parts,
    :context_id,
    :task_id,
    :reference_task_ids,
    :extensions,
    :metadata
  ]

  @valid_roles ~w(user agent)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = m) do
    %{
      "kind" => "message",
      "messageId" => m.message_id,
      "role" => m.role,
      "parts" => Enum.map(m.parts, &Part.encode/1)
    }
    |> maybe_put("contextId", m.context_id)
    |> maybe_put("taskId", m.task_id)
    |> maybe_put("referenceTaskIds", m.reference_task_ids)
    |> maybe_put("extensions", m.extensions)
    |> maybe_put("metadata", m.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"messageId" => mid, "role" => role, "parts" => parts_list} = m)
      when is_binary(mid) and is_list(parts_list) do
    cond do
      role not in @valid_roles ->
        {:error, {:invalid_role, role}}

      Map.get(m, "kind") not in [nil, "message"] ->
        {:error, {:invalid_kind, m["kind"]}}

      true ->
        with {:ok, parts} <- Part.decode_list(parts_list) do
          {:ok,
           %__MODULE__{
             message_id: mid,
             role: role,
             parts: parts,
             context_id: m["contextId"],
             task_id: m["taskId"],
             reference_task_ids: m["referenceTaskIds"],
             extensions: m["extensions"],
             metadata: m["metadata"]
           }}
        end
    end
  end

  def from_map(_), do: {:error, :invalid_message}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
