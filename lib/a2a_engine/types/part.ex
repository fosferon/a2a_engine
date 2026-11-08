defmodule A2aEngine.Types.Part do
  @moduledoc """
  Discriminated union of `TextPart`, `FilePart`, and `DataPart`.

  Dispatches on the `kind` field when decoding; delegates to the variant's
  own `to_map/1` when encoding. Use `decode/1` for decoding arbitrary part
  maps, and `encode/1` to encode any variant struct.
  """

  alias A2aEngine.Types.{TextPart, FilePart, DataPart}

  @type t :: TextPart.t() | FilePart.t() | DataPart.t()

  @doc "Encode any part variant to wire format."
  @spec encode(t()) :: map()
  def encode(%TextPart{} = p), do: TextPart.to_map(p)
  def encode(%FilePart{} = p), do: FilePart.to_map(p)
  def encode(%DataPart{} = p), do: DataPart.to_map(p)

  @doc "Decode a part map to the appropriate variant struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(%{"kind" => "text"} = m), do: TextPart.from_map(m)
  def decode(%{"kind" => "file"} = m), do: FilePart.from_map(m)
  def decode(%{"kind" => "data"} = m), do: DataPart.from_map(m)
  def decode(%{"kind" => kind}), do: {:error, {:unknown_part_kind, kind}}
  def decode(_), do: {:error, :missing_kind}

  @doc "Decode a list of part maps; returns `{:ok, [part]}` or first `{:error, _}`."
  @spec decode_list([map()]) :: {:ok, [t()]} | {:error, term()}
  def decode_list(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn part_map, {:ok, acc} ->
      case decode(part_map) do
        {:ok, part} -> {:cont, {:ok, [part | acc]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _} = e -> e
    end
  end
end
