defmodule A2aEngine.Types.TextPart do
  @moduledoc """
  A text segment within a message or artifact.

  Wire shape: `{"kind": "text", "text": <string>, "metadata": <map?>}`.
  """

  @type t :: %__MODULE__{
          text: String.t(),
          metadata: map() | nil
        }

  @enforce_keys [:text]
  defstruct [:text, metadata: nil]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = t) do
    %{"kind" => "text", "text" => t.text}
    |> maybe_put("metadata", t.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"kind" => "text", "text" => text} = m) when is_binary(text) do
    {:ok, %__MODULE__{text: text, metadata: m["metadata"]}}
  end

  def from_map(_), do: {:error, :invalid_text_part}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
