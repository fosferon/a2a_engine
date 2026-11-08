defmodule A2aEngine.Codec.JsonRpcTest do
  use ExUnit.Case, async: true

  alias A2aEngine.Codec.JsonRpc
  alias A2aEngine.Errors
  alias A2aEngine.TestFixtures

  describe "method registry" do
    test "method/1 resolves known atoms to wire strings" do
      assert JsonRpc.method(:message_send) == "message/send"
      assert JsonRpc.method(:message_stream) == "message/stream"
      assert JsonRpc.method(:tasks_get) == "tasks/get"
      assert JsonRpc.method(:tasks_cancel) == "tasks/cancel"
      assert JsonRpc.method(:tasks_resubscribe) == "tasks/resubscribe"

      assert JsonRpc.method(:tasks_push_notification_config_set) ==
               "tasks/pushNotificationConfig/set"

      assert JsonRpc.method(:tasks_push_notification_config_get) ==
               "tasks/pushNotificationConfig/get"

      assert JsonRpc.method(:tasks_push_notification_config_list) ==
               "tasks/pushNotificationConfig/list"

      assert JsonRpc.method(:tasks_push_notification_config_delete) ==
               "tasks/pushNotificationConfig/delete"

      assert JsonRpc.method(:agent_get_authenticated_extended_card) ==
               "agent/getAuthenticatedExtendedCard"
    end

    test "atom_for_method/1 reverses the lookup" do
      assert JsonRpc.atom_for_method("message/send") == :message_send

      assert JsonRpc.atom_for_method("tasks/pushNotificationConfig/set") ==
               :tasks_push_notification_config_set
    end

    test "atom_for_method/1 returns :unknown for non-A2A methods" do
      assert JsonRpc.atom_for_method("rpc.ping") == :unknown
    end

    test "known_method?/1" do
      assert JsonRpc.known_method?("message/send")
      refute JsonRpc.known_method?("rpc.ping")
    end
  end

  describe "encode_request/3" do
    test "builds a well-formed envelope" do
      req = JsonRpc.encode_request("message/send", %{"message" => %{}}, "req_1")

      assert req == %{
               "jsonrpc" => "2.0",
               "id" => "req_1",
               "method" => "message/send",
               "params" => %{"message" => %{}}
             }
    end

    test "omits params when nil" do
      req = JsonRpc.encode_request("message/send", nil, 1)
      refute Map.has_key?(req, "params")
    end

    test "allows nil id for notifications" do
      req = JsonRpc.encode_request("tasks/cancel", %{"id" => "t"}, nil)
      assert req["id"] == nil
    end
  end

  describe "encode_success/2 and encode_error/2-4" do
    test "success envelope" do
      assert JsonRpc.encode_success("r1", %{"kind" => "task"}) == %{
               "jsonrpc" => "2.0",
               "id" => "r1",
               "result" => %{"kind" => "task"}
             }
    end

    test "error with explicit code and message" do
      env = JsonRpc.encode_error("r1", -32_001, "Task not found")

      assert env == %{
               "jsonrpc" => "2.0",
               "id" => "r1",
               "error" => %{"code" => -32_001, "message" => "Task not found"}
             }
    end

    test "error with code + message + data" do
      env = JsonRpc.encode_error("r1", -32_001, "Task not found", %{"taskId" => "t"})
      assert env["error"]["data"] == %{"taskId" => "t"}
    end

    test "error with default message when only code given" do
      env = JsonRpc.encode_error("r1", Errors.task_not_found(), nil)
      assert env["error"]["message"] == "Task not found"
    end

    test "error from pre-built error map" do
      err = Errors.build(Errors.push_notification_not_supported())
      env = JsonRpc.encode_error("r1", err)
      assert env["error"]["code"] == -32_003
      assert env["error"]["message"] == "Push Notification is not supported"
    end
  end

  describe "decode_request/1" do
    test "decodes the fixture" do
      fixture = TestFixtures.load("jsonrpc_request_send_message")

      assert {:ok, %{id: "req_01", method: "message/send", params: params}} =
               JsonRpc.decode_request(fixture)

      assert params["message"]["messageId"] == "msg_01"
    end

    test "allows absent id (notification)" do
      assert {:ok, %{id: nil}} =
               JsonRpc.decode_request(%{
                 "jsonrpc" => "2.0",
                 "method" => "tasks/cancel",
                 "params" => %{"id" => "t"}
               })
    end

    test "rejects wrong jsonrpc version" do
      assert {:error, {:unsupported_jsonrpc_version, "1.0"}} =
               JsonRpc.decode_request(%{"jsonrpc" => "1.0", "method" => "x"})
    end

    test "rejects missing method" do
      assert {:error, :invalid_request} = JsonRpc.decode_request(%{"jsonrpc" => "2.0"})
    end
  end

  describe "decode_response/1" do
    test "decodes a success response fixture" do
      fixture = TestFixtures.load("jsonrpc_response_success")

      assert {:ok, {:success, "req_01", %{"kind" => "task"}}} =
               JsonRpc.decode_response(fixture)
    end

    test "decodes an error response fixture" do
      fixture = TestFixtures.load("jsonrpc_response_error")

      assert {:ok, {:error, "req_02", error}} = JsonRpc.decode_response(fixture)
      assert error.code == -32_001
      assert error.message == "Task not found"
      assert error.data == %{"taskId" => "unknown_task"}
    end

    test "rejects invalid envelope" do
      assert {:error, :invalid_response} = JsonRpc.decode_response(%{"id" => 1})
    end
  end

  describe "request ↔ response round-trip through a pretend server" do
    test "full loop: encode request → decode → encode success → decode" do
      id = "loop_1"

      request = JsonRpc.encode_request("message/send", %{"foo" => "bar"}, id)
      {:ok, %{id: ^id, method: "message/send", params: params}} = JsonRpc.decode_request(request)
      assert params == %{"foo" => "bar"}

      success = JsonRpc.encode_success(id, %{"result_key" => "value"})
      {:ok, {:success, ^id, result}} = JsonRpc.decode_response(success)
      assert result == %{"result_key" => "value"}
    end
  end
end
