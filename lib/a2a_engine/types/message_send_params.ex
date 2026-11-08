defmodule A2aEngine.Types.MessageSendParams do
  @moduledoc """
  Params wrapper for `message/send` and `message/stream` JSON-RPC methods.

  Wire fields: `message` (required), `configuration` (optional), `metadata`.
  """

  alias A2aEngine.Types.{Message, MessageSendConfiguration}

  @type t :: %__MODULE__{
          message: Message.t(),
          configuration: MessageSendConfiguration.t() | nil,
          metadata: map() | nil
        }

  @enforce_keys [:message]
  defstruct [:message, :configuration, :metadata]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = p) do
    %{"message" => Message.to_map(p.message)}
    |> maybe_put(
      "configuration",
      p.configuration && MessageSendConfiguration.to_map(p.configuration)
    )
    |> maybe_put("metadata", p.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"message" => message_map} = m) when is_map(message_map) do
    with {:ok, message} <- Message.from_map(message_map),
         {:ok, config} <- decode_config(m["configuration"]) do
      {:ok, %__MODULE__{message: message, configuration: config, metadata: m["metadata"]}}
    end
  end

  def from_map(_), do: {:error, :invalid_message_send_params}

  defp decode_config(nil), do: {:ok, nil}
  defp decode_config(%{} = m), do: MessageSendConfiguration.from_map(m)

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
