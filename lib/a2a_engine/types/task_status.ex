defmodule A2aEngine.Types.TaskStatus do
  @moduledoc """
  The current status of a task: state (required) + optional message + timestamp.

  Timestamp is ISO 8601. Message (if present) is an A2A Message.
  """

  alias A2aEngine.{LifecycleState}
  alias A2aEngine.Types.Message

  @type t :: %__MODULE__{
          state: LifecycleState.t(),
          message: Message.t() | nil,
          timestamp: String.t() | nil
        }

  @enforce_keys [:state]
  defstruct [:state, :message, :timestamp]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = s) do
    %{"state" => s.state}
    |> maybe_put("message", s.message && Message.to_map(s.message))
    |> maybe_put("timestamp", s.timestamp)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"state" => state} = m) when is_binary(state) do
    if LifecycleState.valid?(state) do
      with {:ok, message} <- decode_message(m["message"]) do
        {:ok, %__MODULE__{state: state, message: message, timestamp: m["timestamp"]}}
      end
    else
      {:error, {:invalid_state, state}}
    end
  end

  def from_map(_), do: {:error, :invalid_task_status}

  defp decode_message(nil), do: {:ok, nil}
  defp decode_message(%{} = m), do: Message.from_map(m)

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
