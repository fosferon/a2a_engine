defmodule A2aEngine.Types.FileWithUri do
  @moduledoc """
  A file whose content is referenced by URI.

  Wire fields: `uri` (required), `mimeType`, `name`.
  """

  @type t :: %__MODULE__{
          uri: String.t(),
          mime_type: String.t() | nil,
          name: String.t() | nil
        }

  @enforce_keys [:uri]
  defstruct [:uri, :mime_type, :name]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = t) do
    %{"uri" => t.uri}
    |> maybe_put("mimeType", t.mime_type)
    |> maybe_put("name", t.name)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"uri" => uri} = m) when is_binary(uri) do
    {:ok, %__MODULE__{uri: uri, mime_type: m["mimeType"], name: m["name"]}}
  end

  def from_map(_), do: {:error, :missing_uri}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
