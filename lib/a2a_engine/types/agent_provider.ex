defmodule A2aEngine.Types.AgentProvider do
  @moduledoc """
  Agent provider organization info.

  Wire fields: `organization` (required), `url` (required).
  """

  @type t :: %__MODULE__{
          organization: String.t(),
          url: String.t()
        }

  @enforce_keys [:organization, :url]
  defstruct [:organization, :url]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = p), do: %{"organization" => p.organization, "url" => p.url}

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"organization" => org, "url" => url})
      when is_binary(org) and is_binary(url) do
    {:ok, %__MODULE__{organization: org, url: url}}
  end

  def from_map(_), do: {:error, :invalid_agent_provider}
end
