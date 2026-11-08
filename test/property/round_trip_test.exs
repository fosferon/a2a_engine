defmodule A2aEngine.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias A2aEngine.Types.{
    Message,
    Task,
    TaskStatus,
    Artifact,
    TextPart,
    FilePart,
    DataPart,
    FileWithBytes,
    FileWithUri
  }

  alias A2aEngine.Codec.JsonRpc

  # ---- generators ----

  defp short_string, do: StreamData.string(:printable, min_length: 1, max_length: 20)
  defp opt(gen), do: StreamData.one_of([StreamData.constant(nil), gen])

  defp part_gen do
    StreamData.one_of([
      StreamData.bind(short_string(), fn t -> StreamData.constant(%TextPart{text: t}) end),
      StreamData.bind(short_string(), fn d ->
        StreamData.constant(%DataPart{data: %{"v" => d}})
      end),
      StreamData.bind(short_string(), fn uri ->
        StreamData.constant(%FilePart{file: %FileWithUri{uri: "https://x/" <> uri}})
      end),
      StreamData.bind(short_string(), fn bytes ->
        StreamData.constant(%FilePart{
          file: %FileWithBytes{bytes: Base.encode64(bytes), mime_type: "text/plain"}
        })
      end)
    ])
  end

  defp parts_gen, do: StreamData.list_of(part_gen(), min_length: 1, max_length: 4)

  defp message_gen do
    gen all(
          mid <- short_string(),
          role <- StreamData.member_of(["user", "agent"]),
          parts <- parts_gen(),
          ctx <- opt(short_string()),
          tid <- opt(short_string())
        ) do
      %Message{message_id: mid, role: role, parts: parts, context_id: ctx, task_id: tid}
    end
  end

  defp state_gen do
    StreamData.member_of(
      ~w(submitted working input-required completed canceled failed rejected auth-required unknown)
    )
  end

  defp status_gen do
    gen all(state <- state_gen(), ts <- opt(short_string())) do
      %TaskStatus{state: state, timestamp: ts}
    end
  end

  defp artifact_gen do
    gen all(aid <- short_string(), parts <- parts_gen(), name <- opt(short_string())) do
      %Artifact{artifact_id: aid, parts: parts, name: name}
    end
  end

  defp task_gen do
    gen all(
          id <- short_string(),
          ctx <- short_string(),
          status <- status_gen(),
          artifacts <- opt(StreamData.list_of(artifact_gen(), max_length: 3))
        ) do
      %Task{id: id, context_id: ctx, status: status, artifacts: artifacts}
    end
  end

  # ---- properties ----

  property "Message round-trips" do
    check all(m <- message_gen()) do
      encoded = Message.to_map(m)
      assert {:ok, decoded} = Message.from_map(encoded)
      assert Message.to_map(decoded) == encoded
    end
  end

  property "Task round-trips" do
    check all(t <- task_gen()) do
      encoded = Task.to_map(t)
      assert {:ok, decoded} = Task.from_map(encoded)
      assert Task.to_map(decoded) == encoded
    end
  end

  property "TextPart round-trips" do
    check all(text <- short_string()) do
      p = %TextPart{text: text}
      assert {:ok, decoded} = TextPart.from_map(TextPart.to_map(p))
      assert decoded == p
    end
  end

  property "JSON-RPC envelopes round-trip" do
    check all(
            method <- StreamData.member_of(Map.keys(JsonRpc.methods())),
            id <-
              StreamData.one_of([short_string(), StreamData.integer(), StreamData.constant(nil)]),
            params_key <- short_string(),
            params_val <- short_string()
          ) do
      method_str = JsonRpc.method(method)
      params = %{params_key => params_val}

      req = JsonRpc.encode_request(method_str, params, id)

      assert {:ok, %{id: ^id, method: ^method_str, params: ^params}} =
               JsonRpc.decode_request(req)
    end
  end
end
