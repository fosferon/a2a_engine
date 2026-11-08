defmodule A2aEngine.TypesTest do
  use ExUnit.Case, async: true

  alias A2aEngine.TestFixtures
  alias A2aEngine.Types.{Message, Task, AgentCard, PushNotificationConfig}
  alias A2aEngine.Types.{TaskStatusUpdateEvent, TaskArtifactUpdateEvent}
  alias A2aEngine.Types.{TextPart, FilePart, DataPart, FileWithBytes, FileWithUri}
  alias A2aEngine.Types.Part

  describe "Message round-trip" do
    test "text message fixture" do
      assert_round_trip(TestFixtures.load("text_message"), Message)
    end

    test "data message with checkpoint fixture" do
      map = TestFixtures.load("data_message_checkpoint")
      assert_round_trip(map, Message)

      # Also verify checkpoint metadata survives
      {:ok, %Message{parts: parts}} = Message.from_map(map)
      [_text, _data_unowned, checkpoint] = parts

      assert %DataPart{metadata: %{"owner" => "planner", "type" => "checkpoint"}} = checkpoint
    end

    test "file message (bytes) fixture" do
      map = TestFixtures.load("file_message_bytes")
      assert_round_trip(map, Message)

      {:ok, %Message{parts: [%FilePart{file: file}]}} = Message.from_map(map)
      assert %FileWithBytes{bytes: "SGVsbG8gZnJvbSBBMkE=", mime_type: "text/plain"} = file
    end

    test "file message (uri) fixture" do
      map = TestFixtures.load("file_message_uri")
      assert_round_trip(map, Message)

      {:ok, %Message{parts: [%FilePart{file: file}]}} = Message.from_map(map)

      assert %FileWithUri{uri: "https://example.com/report.pdf", mime_type: "application/pdf"} =
               file
    end

    test "rejects invalid role" do
      assert {:error, {:invalid_role, "system"}} =
               Message.from_map(%{
                 "messageId" => "m1",
                 "role" => "system",
                 "parts" => [%{"kind" => "text", "text" => "hi"}]
               })
    end

    test "rejects wrong kind" do
      assert {:error, {:invalid_kind, "task"}} =
               Message.from_map(%{
                 "kind" => "task",
                 "messageId" => "m1",
                 "role" => "user",
                 "parts" => []
               })
    end

    test "rejects missing required fields" do
      assert {:error, :invalid_message} = Message.from_map(%{"role" => "user"})
    end
  end

  describe "Task round-trip" do
    test "working task fixture" do
      assert_round_trip(TestFixtures.load("task_working"), Task)
    end

    test "input-required task fixture (with history + status message)" do
      assert_round_trip(TestFixtures.load("task_input_required"), Task)
    end

    test "completed task with artifacts fixture" do
      assert_round_trip(TestFixtures.load("task_completed_with_artifacts"), Task)
    end

    test "rejects invalid state" do
      assert {:error, {:invalid_state, "pending"}} =
               Task.from_map(%{
                 "id" => "t",
                 "contextId" => "c",
                 "status" => %{"state" => "pending"}
               })
    end

    test "contextId is required on Task" do
      # Per spec contextId is required on Task (vs optional on Message).
      assert {:error, :invalid_task} =
               Task.from_map(%{"id" => "t", "status" => %{"state" => "working"}})
    end
  end

  describe "AgentCard round-trip" do
    test "minimal card fixture" do
      assert_round_trip(TestFixtures.load("agent_card_minimal"), AgentCard)
    end

    test "full card fixture with all optional fields" do
      assert_round_trip(TestFixtures.load("agent_card_full"), AgentCard)
    end

    test "rejects missing required fields" do
      assert {:error, :invalid_agent_card} = AgentCard.from_map(%{"name" => "incomplete"})
    end
  end

  describe "PushNotificationConfig round-trip" do
    test "with authentication fixture" do
      assert_round_trip(TestFixtures.load("push_notification_config"), PushNotificationConfig)
    end

    test "minimal (url only)" do
      map = %{"url" => "https://example.com/webhook"}
      assert {:ok, cfg} = PushNotificationConfig.from_map(map)
      assert PushNotificationConfig.to_map(cfg) == map
    end
  end

  describe "Streaming events" do
    test "TaskStatusUpdateEvent round-trip" do
      assert_round_trip(TestFixtures.load("status_update_event"), TaskStatusUpdateEvent)
    end

    test "TaskArtifactUpdateEvent round-trip" do
      assert_round_trip(TestFixtures.load("artifact_update_event"), TaskArtifactUpdateEvent)
    end
  end

  describe "Part dispatcher" do
    test "decodes each variant by kind" do
      assert {:ok, %TextPart{}} = Part.decode(%{"kind" => "text", "text" => "hi"})
      assert {:ok, %FilePart{}} = Part.decode(%{"kind" => "file", "file" => %{"uri" => "x"}})
      assert {:ok, %DataPart{}} = Part.decode(%{"kind" => "data", "data" => %{}})
    end

    test "rejects unknown kind" do
      assert {:error, {:unknown_part_kind, "video"}} = Part.decode(%{"kind" => "video"})
    end

    test "rejects missing kind" do
      assert {:error, :missing_kind} = Part.decode(%{})
    end

    test "encodes every variant back to the canonical map" do
      assert Part.encode(%TextPart{text: "x"}) == %{"kind" => "text", "text" => "x"}

      assert Part.encode(%FilePart{file: %FileWithUri{uri: "u"}}) ==
               %{"kind" => "file", "file" => %{"uri" => "u"}}

      assert Part.encode(%DataPart{data: %{"k" => "v"}}) ==
               %{"kind" => "data", "data" => %{"k" => "v"}}
    end

    test "decode_list halts on first bad part" do
      bad = [
        %{"kind" => "text", "text" => "ok"},
        %{"kind" => "text"},
        %{"kind" => "text", "text" => "never seen"}
      ]

      assert {:error, :invalid_text_part} = Part.decode_list(bad)
    end
  end

  describe "Checkpoint routing convention" do
    test "checkpoint DataPart tags its owner" do
      cp = %DataPart{
        data: %{"resume_from" => "step_4"},
        metadata: %{
          "type" => "checkpoint",
          "owner" => "planner",
          "session" => "sess_xyz"
        }
      }

      encoded = DataPart.to_map(cp)

      assert encoded == %{
               "kind" => "data",
               "data" => %{"resume_from" => "step_4"},
               "metadata" => %{
                 "type" => "checkpoint",
                 "owner" => "planner",
                 "session" => "sess_xyz"
               }
             }

      assert {:ok, decoded} = DataPart.from_map(encoded)
      assert decoded == cp
    end
  end

  # ---- helpers ----

  defp assert_round_trip(fixture_map, type_module) do
    assert {:ok, decoded} = type_module.from_map(fixture_map),
           "from_map/1 failed for #{inspect(type_module)} on fixture: #{inspect(fixture_map)}"

    re_encoded = type_module.to_map(decoded)

    assert re_encoded == fixture_map, """
    Round-trip mismatch for #{inspect(type_module)}.

    fixture:
    #{inspect(fixture_map, pretty: true)}

    re-encoded:
    #{inspect(re_encoded, pretty: true)}
    """
  end
end
