defmodule A2aEngine.Types.AgentCard do
  @moduledoc """
  Self-describing manifest for an A2A agent.

  Served at `/.well-known/agent.json` (single-agent host) or
  `/.well-known/agents/<name>.json` (multi-agent host).

  ## Required wire fields

    * `name`, `description`, `version`, `protocolVersion`, `url`
    * `capabilities`, `skills`
    * `defaultInputModes`, `defaultOutputModes`

  ## Optional wire fields

    * `preferredTransport` (defaults to `"JSONRPC"`)
    * `additionalInterfaces` — list of alternate (transport, url) pairs
    * `provider` — org info
    * `documentationUrl`, `iconUrl`
    * `security`, `securitySchemes` — OpenAPI-style declarations (passed
      through as opaque maps; not modelled as structs)
    * `signatures` — JWS signatures over the card (opaque)
    * `supportsAuthenticatedExtendedCard` (bool)
  """

  alias A2aEngine.Types.{AgentCapabilities, AgentInterface, AgentProvider, AgentSkill}

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          version: String.t(),
          protocol_version: String.t(),
          url: String.t(),
          capabilities: AgentCapabilities.t(),
          skills: [AgentSkill.t()],
          default_input_modes: [String.t()],
          default_output_modes: [String.t()],
          preferred_transport: String.t() | nil,
          additional_interfaces: [AgentInterface.t()] | nil,
          provider: AgentProvider.t() | nil,
          documentation_url: String.t() | nil,
          icon_url: String.t() | nil,
          security: [map()] | nil,
          security_schemes: map() | nil,
          signatures: [map()] | nil,
          supports_authenticated_extended_card: boolean() | nil
        }

  @enforce_keys [
    :name,
    :description,
    :version,
    :protocol_version,
    :url,
    :capabilities,
    :skills,
    :default_input_modes,
    :default_output_modes
  ]
  defstruct [
    :name,
    :description,
    :version,
    :protocol_version,
    :url,
    :capabilities,
    :skills,
    :default_input_modes,
    :default_output_modes,
    :preferred_transport,
    :additional_interfaces,
    :provider,
    :documentation_url,
    :icon_url,
    :security,
    :security_schemes,
    :signatures,
    :supports_authenticated_extended_card
  ]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = c) do
    %{
      "name" => c.name,
      "description" => c.description,
      "version" => c.version,
      "protocolVersion" => c.protocol_version,
      "url" => c.url,
      "capabilities" => AgentCapabilities.to_map(c.capabilities),
      "skills" => Enum.map(c.skills, &AgentSkill.to_map/1),
      "defaultInputModes" => c.default_input_modes,
      "defaultOutputModes" => c.default_output_modes
    }
    |> maybe_put("preferredTransport", c.preferred_transport)
    |> maybe_put(
      "additionalInterfaces",
      c.additional_interfaces && Enum.map(c.additional_interfaces, &AgentInterface.to_map/1)
    )
    |> maybe_put("provider", c.provider && AgentProvider.to_map(c.provider))
    |> maybe_put("documentationUrl", c.documentation_url)
    |> maybe_put("iconUrl", c.icon_url)
    |> maybe_put("security", c.security)
    |> maybe_put("securitySchemes", c.security_schemes)
    |> maybe_put("signatures", c.signatures)
    |> maybe_put("supportsAuthenticatedExtendedCard", c.supports_authenticated_extended_card)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(
        %{
          "name" => name,
          "description" => desc,
          "version" => version,
          "protocolVersion" => pv,
          "url" => url,
          "capabilities" => caps_map,
          "skills" => skills_list,
          "defaultInputModes" => default_in,
          "defaultOutputModes" => default_out
        } = m
      )
      when is_binary(name) and is_binary(desc) and is_binary(version) and is_binary(pv) and
             is_binary(url) and is_map(caps_map) and is_list(skills_list) and
             is_list(default_in) and is_list(default_out) do
    with {:ok, caps} <- AgentCapabilities.from_map(caps_map),
         {:ok, skills} <- decode_list(skills_list, &AgentSkill.from_map/1),
         {:ok, ifaces} <- decode_list(m["additionalInterfaces"], &AgentInterface.from_map/1),
         {:ok, provider} <- decode_optional(m["provider"], &AgentProvider.from_map/1) do
      {:ok,
       %__MODULE__{
         name: name,
         description: desc,
         version: version,
         protocol_version: pv,
         url: url,
         capabilities: caps,
         skills: skills,
         default_input_modes: default_in,
         default_output_modes: default_out,
         preferred_transport: m["preferredTransport"],
         additional_interfaces: ifaces,
         provider: provider,
         documentation_url: m["documentationUrl"],
         icon_url: m["iconUrl"],
         security: m["security"],
         security_schemes: m["securitySchemes"],
         signatures: m["signatures"],
         supports_authenticated_extended_card: m["supportsAuthenticatedExtendedCard"]
       }}
    end
  end

  def from_map(_), do: {:error, :invalid_agent_card}

  defp decode_list(nil, _fn), do: {:ok, nil}

  defp decode_list(list, decode_fn) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case decode_fn.(item) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _} = e -> e
    end
  end

  defp decode_optional(nil, _fn), do: {:ok, nil}
  defp decode_optional(v, decode_fn), do: decode_fn.(v)

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
