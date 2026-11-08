defmodule A2aEngine.Types.AgentExtension do
  @moduledoc """
  Declaration of a protocol extension supported by an Agent.

  Wire fields: `uri` (required), `required` (bool), `description`, `params`.
  """

  @type t :: %__MODULE__{
          uri: String.t(),
          required: boolean() | nil,
          description: String.t() | nil,
          params: map() | nil
        }

  @enforce_keys [:uri]
  defstruct [:uri, :required, :description, :params]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = e) do
    %{"uri" => e.uri}
    |> maybe_put("required", e.required)
    |> maybe_put("description", e.description)
    |> maybe_put("params", e.params)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"uri" => uri} = m) when is_binary(uri) do
    {:ok,
     %__MODULE__{
       uri: uri,
       required: m["required"],
       description: m["description"],
       params: m["params"]
     }}
  end

  def from_map(_), do: {:error, :invalid_agent_extension}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
