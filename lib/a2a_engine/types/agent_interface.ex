defmodule A2aEngine.Types.AgentInterface do
  @moduledoc """
  A (transport, url) pair declaring an available interface for an agent.

  Wire fields: `transport` (required — e.g. "JSONRPC", "GRPC", "HTTP+JSON"),
  `url` (required).
  """

  @type t :: %__MODULE__{transport: String.t(), url: String.t()}

  @enforce_keys [:transport, :url]
  defstruct [:transport, :url]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = i), do: %{"transport" => i.transport, "url" => i.url}

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"transport" => t, "url" => u}) when is_binary(t) and is_binary(u) do
    {:ok, %__MODULE__{transport: t, url: u}}
  end

  def from_map(_), do: {:error, :invalid_agent_interface}
end
