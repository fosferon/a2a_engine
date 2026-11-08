defmodule A2aEngine.Types.FileWithBytes do
  @moduledoc """
  A file whose content is inlined as base64-encoded bytes.

  Wire fields: `bytes` (required), `mimeType`, `name`.
  """

  @type t :: %__MODULE__{
          bytes: String.t(),
          mime_type: String.t() | nil,
          name: String.t() | nil
        }

  @enforce_keys [:bytes]
  defstruct [:bytes, :mime_type, :name]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = t) do
    %{"bytes" => t.bytes}
    |> maybe_put("mimeType", t.mime_type)
    |> maybe_put("name", t.name)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"bytes" => bytes} = m) when is_binary(bytes) do
    {:ok, %__MODULE__{bytes: bytes, mime_type: m["mimeType"], name: m["name"]}}
  end

  def from_map(_), do: {:error, :missing_bytes}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
