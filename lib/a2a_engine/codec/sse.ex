defmodule A2aEngine.Codec.SSE do
  @moduledoc """
  Server-Sent Events codec with Last-Event-ID resumption.

  Event id scheme: `"<task_id>:<seq>"`. `seq` is a monotonic integer, so
  clients can use `Last-Event-ID` to request replay from a known point
  without ambiguity across tasks.

  Wire format per the HTML Living Standard:

      id: <task_id>:<seq>
      event: <name>
      data: <serialized JSON>
      <blank line>

  Multiple `data:` lines are supported (spec says consumer concatenates
  with `\\n`). This encoder emits a single line and JSON-encodes the payload
  verbatim, which is the common case and unambiguous.

  Comment frames (`: keep-alive`) are emitted via `keep_alive/0` to prevent
  intermediary timeouts on long-idle streams.
  """

  @doc """
  Encode one SSE event.

  `payload` may be a map (will be JSON-encoded) or an already-encoded string.
  """
  @spec encode_event(String.t(), String.t(), integer(), map() | String.t()) :: iodata()
  def encode_event(task_id, event_name, seq, payload)
      when is_binary(task_id) and is_binary(event_name) and is_integer(seq) do
    data =
      case payload do
        p when is_binary(p) -> p
        p -> Jason.encode!(p)
      end

    [
      "id: ",
      event_id(task_id, seq),
      "\n",
      "event: ",
      event_name,
      "\n",
      "data: ",
      data,
      "\n\n"
    ]
  end

  @doc "Build the canonical SSE event id for a `(task_id, seq)` pair."
  @spec event_id(String.t(), integer()) :: String.t()
  def event_id(task_id, seq) when is_binary(task_id) and is_integer(seq) do
    task_id <> ":" <> Integer.to_string(seq)
  end

  @doc """
  Parse an event id back into `{task_id, seq}`.

      iex> A2aEngine.Codec.SSE.parse_event_id("abc123:7")
      {:ok, {"abc123", 7}}
      iex> A2aEngine.Codec.SSE.parse_event_id("bogus")
      {:error, :invalid_event_id}
  """
  @spec parse_event_id(String.t()) :: {:ok, {String.t(), integer()}} | {:error, term()}
  def parse_event_id(id) when is_binary(id) do
    case String.split(id, ":", parts: 2) do
      [task_id, seq_str] when task_id != "" ->
        case Integer.parse(seq_str) do
          {seq, ""} -> {:ok, {task_id, seq}}
          _ -> {:error, :invalid_event_id}
        end

      _ ->
        {:error, :invalid_event_id}
    end
  end

  def parse_event_id(_), do: {:error, :invalid_event_id}

  @doc """
  Decode a full SSE event block (lines separated by `\\n`, terminated by
  blank line). Returns the parsed `{id, event, data}` tuple or an error.

  Does NOT parse the `data` as JSON — callers decide what to do with it.
  """
  @spec decode_event(String.t()) ::
          {:ok, %{id: String.t() | nil, event: String.t() | nil, data: String.t()}}
          | {:error, term()}
  def decode_event(block) when is_binary(block) do
    block
    |> String.split("\n", trim: false)
    |> Enum.reduce_while({:ok, %{id: nil, event: nil, data_lines: []}}, fn line, {:ok, acc} ->
      cond do
        line == "" ->
          {:halt, {:ok, acc}}

        String.starts_with?(line, ":") ->
          {:cont, {:ok, acc}}

        String.starts_with?(line, "id:") ->
          {:cont, {:ok, %{acc | id: trim_field(line, "id:")}}}

        String.starts_with?(line, "event:") ->
          {:cont, {:ok, %{acc | event: trim_field(line, "event:")}}}

        String.starts_with?(line, "data:") ->
          {:cont, {:ok, %{acc | data_lines: acc.data_lines ++ [trim_field(line, "data:")]}}}

        true ->
          {:cont, {:ok, acc}}
      end
    end)
    |> case do
      {:ok, %{data_lines: []}} ->
        {:error, :no_data}

      {:ok, %{id: id, event: event, data_lines: lines}} ->
        {:ok, %{id: id, event: event, data: Enum.join(lines, "\n")}}
    end
  end

  @doc "Emit a keep-alive comment frame to reset intermediary timeouts."
  @spec keep_alive() :: iodata()
  def keep_alive, do: ": keep-alive\n\n"

  @doc """
  Interpret a `Last-Event-ID` header value for stream resumption.

  Returns `{:ok, {task_id, seq}}` when the header is a well-formed A2A event
  id, or `{:error, _}` when the client has never connected before (header
  absent or malformed).
  """
  @spec resume_from(String.t() | nil) :: {:ok, {String.t(), integer()}} | {:error, term()}
  def resume_from(nil), do: {:error, :no_last_event_id}
  def resume_from(id), do: parse_event_id(id)

  # ---- private ----

  defp trim_field(line, prefix) do
    # SSE spec: optional single space after the colon, trimmed.
    rest = binary_part(line, byte_size(prefix), byte_size(line) - byte_size(prefix))

    case rest do
      <<" ", tail::binary>> -> tail
      tail -> tail
    end
  end
end
