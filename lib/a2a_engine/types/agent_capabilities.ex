defmodule A2aEngine.Types.AgentCapabilities do
  @moduledoc """
  Optional capabilities advertised by an agent.

  All fields optional. Wire booleans default to absent (implies false when
  unspecified).
  """

  alias A2aEngine.Types.AgentExtension

  @type t :: %__MODULE__{
          streaming: boolean() | nil,
          push_notifications: boolean() | nil,
          state_transition_history: boolean() | nil,
          extensions: [AgentExtension.t()] | nil
        }

  defstruct [:streaming, :push_notifications, :state_transition_history, :extensions]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = c) do
    %{}
    |> maybe_put("streaming", c.streaming)
    |> maybe_put("pushNotifications", c.push_notifications)
    |> maybe_put("stateTransitionHistory", c.state_transition_history)
    |> maybe_put("extensions", c.extensions && Enum.map(c.extensions, &AgentExtension.to_map/1))
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{} = m) do
    with {:ok, extensions} <- decode_extensions(m["extensions"]) do
      {:ok,
       %__MODULE__{
         streaming: m["streaming"],
         push_notifications: m["pushNotifications"],
         state_transition_history: m["stateTransitionHistory"],
         extensions: extensions
       }}
    end
  end

  defp decode_extensions(nil), do: {:ok, nil}

  defp decode_extensions(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case AgentExtension.from_map(item) do
        {:ok, ext} -> {:cont, {:ok, [ext | acc]}}
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
