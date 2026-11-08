defmodule A2aEngine.Types.DataPart do
  @moduledoc """
  A structured data segment within a message or artifact.

  Wire shape: `{"kind": "data", "data": <object>, "metadata": <map?>}`.

  ## Checkpoint-in-envelope convention

  DataPart is the carrier for the "checkpoint-in-envelope" pattern. A worker
  (or caller) stashes opaque resumable state here and tags the part via
  `metadata` so the broker can route it back to the producer only:

      %A2aEngine.Types.DataPart{
        data: %{ ... serialized worker/session state ... },
        metadata: %{
          "type" => "checkpoint",
          "owner" => "my-worker",
          "session" => "sess_abc123"
        }
      }

  The A2A spec treats `data` and `metadata` as opaque; the convention lives
  in application code. See `A2aEngine` moduledoc.
  """

  @type t :: %__MODULE__{
          data: map(),
          metadata: map() | nil
        }

  @enforce_keys [:data]
  defstruct [:data, metadata: nil]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = t) do
    %{"kind" => "data", "data" => t.data}
    |> maybe_put("metadata", t.metadata)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"kind" => "data", "data" => data} = m) when is_map(data) do
    {:ok, %__MODULE__{data: data, metadata: m["metadata"]}}
  end

  def from_map(_), do: {:error, :invalid_data_part}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
