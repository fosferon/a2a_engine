defmodule A2aEngine.Codec.SSETest do
  use ExUnit.Case, async: true
  doctest A2aEngine.Codec.SSE

  alias A2aEngine.Codec.SSE

  describe "event_id/2 and parse_event_id/1" do
    test "round-trip" do
      id = SSE.event_id("task_abc", 42)
      assert id == "task_abc:42"
      assert {:ok, {"task_abc", 42}} = SSE.parse_event_id(id)
    end

    test "rejects malformed ids" do
      assert {:error, :invalid_event_id} = SSE.parse_event_id("no_colon")
      assert {:error, :invalid_event_id} = SSE.parse_event_id(":42")
      assert {:error, :invalid_event_id} = SSE.parse_event_id("t:not_an_int")
    end
  end

  describe "encode_event/4" do
    test "emits spec-compliant SSE frame with id, event, data" do
      frame =
        SSE.encode_event("task_1", "status-update", 3, %{"state" => "working"})
        |> IO.iodata_to_binary()

      assert frame ==
               "id: task_1:3\nevent: status-update\ndata: {\"state\":\"working\"}\n\n"
    end

    test "accepts pre-encoded string payload" do
      frame =
        SSE.encode_event("t", "ping", 1, "raw-string-payload")
        |> IO.iodata_to_binary()

      assert frame == "id: t:1\nevent: ping\ndata: raw-string-payload\n\n"
    end
  end

  describe "decode_event/1" do
    test "parses a well-formed frame" do
      frame = "id: t1:7\nevent: status-update\ndata: {\"state\":\"working\"}\n\n"

      assert {:ok, %{id: "t1:7", event: "status-update", data: data}} =
               SSE.decode_event(frame)

      assert data == ~s({"state":"working"})
    end

    test "ignores comment lines starting with ':'" do
      frame = ": keep-alive\nid: t1:7\nevent: e\ndata: x\n\n"
      assert {:ok, %{data: "x"}} = SSE.decode_event(frame)
    end

    test "concatenates multi-line data with \\n" do
      frame = "id: t1:1\nevent: m\ndata: line1\ndata: line2\n\n"
      assert {:ok, %{data: "line1\nline2"}} = SSE.decode_event(frame)
    end

    test "rejects frames with no data" do
      frame = "id: t1:1\nevent: m\n\n"
      assert {:error, :no_data} = SSE.decode_event(frame)
    end
  end

  describe "resume_from/1" do
    test "parses a Last-Event-ID header" do
      assert {:ok, {"task_x", 12}} = SSE.resume_from("task_x:12")
    end

    test "signals no-prior-connection when header absent" do
      assert {:error, :no_last_event_id} = SSE.resume_from(nil)
    end

    test "errors on malformed header" do
      assert {:error, :invalid_event_id} = SSE.resume_from("garbage")
    end
  end

  describe "keep_alive/0" do
    test "emits a comment frame" do
      assert SSE.keep_alive() == ": keep-alive\n\n"
    end
  end
end
