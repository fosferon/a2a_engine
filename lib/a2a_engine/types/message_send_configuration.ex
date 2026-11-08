defmodule A2aEngine.Types.MessageSendConfiguration do
  @moduledoc """
  Optional configuration block for `message/send` and `message/stream` params.

  Wire fields: `acceptedOutputModes` (list of MIME strings), `blocking`
  (client waits for completion), `historyLength` (how many prior messages
  to include in the response), `pushNotificationConfig`.
  """

  alias A2aEngine.Types.PushNotificationConfig

  @type t :: %__MODULE__{
          accepted_output_modes: [String.t()] | nil,
          blocking: boolean() | nil,
          history_length: non_neg_integer() | nil,
          push_notification_config: PushNotificationConfig.t() | nil
        }

  defstruct [:accepted_output_modes, :blocking, :history_length, :push_notification_config]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = c) do
    %{}
    |> maybe_put("acceptedOutputModes", c.accepted_output_modes)
    |> maybe_put("blocking", c.blocking)
    |> maybe_put("historyLength", c.history_length)
    |> maybe_put(
      "pushNotificationConfig",
      c.push_notification_config && PushNotificationConfig.to_map(c.push_notification_config)
    )
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{} = m) do
    with {:ok, push} <- decode_push(m["pushNotificationConfig"]) do
      {:ok,
       %__MODULE__{
         accepted_output_modes: m["acceptedOutputModes"],
         blocking: m["blocking"],
         history_length: m["historyLength"],
         push_notification_config: push
       }}
    end
  end

  defp decode_push(nil), do: {:ok, nil}
  defp decode_push(%{} = m), do: PushNotificationConfig.from_map(m)

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
