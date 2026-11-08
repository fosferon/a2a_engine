defmodule A2aEngine.Types.TaskPushNotificationConfig do
  @moduledoc """
  Params wrapper for `tasks/pushNotificationConfig/set` and related methods.

  Wire fields: `taskId` (required), `pushNotificationConfig` (required).
  """

  alias A2aEngine.Types.PushNotificationConfig

  @type t :: %__MODULE__{
          task_id: String.t(),
          push_notification_config: PushNotificationConfig.t()
        }

  @enforce_keys [:task_id, :push_notification_config]
  defstruct [:task_id, :push_notification_config]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = c) do
    %{
      "taskId" => c.task_id,
      "pushNotificationConfig" => PushNotificationConfig.to_map(c.push_notification_config)
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"taskId" => tid, "pushNotificationConfig" => cfg} = _m)
      when is_binary(tid) and is_map(cfg) do
    with {:ok, pc} <- PushNotificationConfig.from_map(cfg) do
      {:ok, %__MODULE__{task_id: tid, push_notification_config: pc}}
    end
  end

  def from_map(_), do: {:error, :invalid_task_push_config}
end
