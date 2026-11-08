defmodule A2aEngine.Types.FilePart do
  @moduledoc """
  A file segment within a message or artifact.

  Wire shape: `{"kind": "file", "file": <FileWithBytes|FileWithUri>, "metadata": <map?>}`.
  The nested `file` is discriminated by the presence of `bytes` vs `uri`.
  """

  alias A2aEngine.Types.{FileWithBytes, FileWithUri}

  @type file :: FileWithBytes.t() | FileWithUri.t()
  @type t :: %__MODULE__{
          file: file(),
          metadata: map() | nil
        }

  @enforce_keys [:file]
  defstruct [:file, metadata: nil]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{file: %FileWithBytes{} = f} = t) do
    %{"kind" => "file", "file" => FileWithBytes.to_map(f)}
    |> maybe_put("metadata", t.metadata)
  end

  def to_map(%__MODULE__{file: %FileWithUri{} = f} = t) do
    %{"kind" => "file", "file" => FileWithUri.to_map(f)}
    |> maybe_put("metadata", t.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"kind" => "file", "file" => file_map} = m) when is_map(file_map) do
    with {:ok, file} <- decode_file(file_map) do
      {:ok, %__MODULE__{file: file, metadata: m["metadata"]}}
    end
  end

  def from_map(_), do: {:error, :invalid_file_part}

  defp decode_file(%{"bytes" => _} = m), do: FileWithBytes.from_map(m)
  defp decode_file(%{"uri" => _} = m), do: FileWithUri.from_map(m)
  defp decode_file(_), do: {:error, :file_variant_undetermined}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
