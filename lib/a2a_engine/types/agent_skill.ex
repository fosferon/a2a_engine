defmodule A2aEngine.Types.AgentSkill do
  @moduledoc """
  A distinct capability an agent can perform.

  Required wire fields: `id`, `name`, `description`, `tags`. Optional:
  `examples`, `inputModes`, `outputModes`, `security`.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          tags: [String.t()],
          examples: [String.t()] | nil,
          input_modes: [String.t()] | nil,
          output_modes: [String.t()] | nil,
          security: [map()] | nil
        }

  @enforce_keys [:id, :name, :description, :tags]
  defstruct [:id, :name, :description, :tags, :examples, :input_modes, :output_modes, :security]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = s) do
    %{
      "id" => s.id,
      "name" => s.name,
      "description" => s.description,
      "tags" => s.tags
    }
    |> maybe_put("examples", s.examples)
    |> maybe_put("inputModes", s.input_modes)
    |> maybe_put("outputModes", s.output_modes)
    |> maybe_put("security", s.security)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"id" => id, "name" => name, "description" => desc, "tags" => tags} = m)
      when is_binary(id) and is_binary(name) and is_binary(desc) and is_list(tags) do
    {:ok,
     %__MODULE__{
       id: id,
       name: name,
       description: desc,
       tags: tags,
       examples: m["examples"],
       input_modes: m["inputModes"],
       output_modes: m["outputModes"],
       security: m["security"]
     }}
  end

  def from_map(_), do: {:error, :invalid_agent_skill}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
