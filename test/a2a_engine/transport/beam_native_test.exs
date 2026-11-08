defmodule A2aEngine.Transport.BeamNativeTest do
  use ExUnit.Case, async: false

  alias A2aEngine.Transport.BeamNative
  alias A2aEngine.Transport.BeamNative.Server
  alias A2aEngine.Codec.JsonRpc
  alias A2aEngine.TestSupport.EchoHandler

  setup do
    # Each test gets a uniquely-named server so they can run concurrently.
    name = :"beam_native_test_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      Server.start_link(
        name: name,
        handler: EchoHandler,
        auth: A2aEngine.Auth.Localhost,
        pubsub: A2aEngine.TestPubSub
      )

    on_exit(fn -> Process.exit(pid, :normal) end)

    {:ok, server: name}
  end

  describe "send_request/3 (unary)" do
    test "returns a Task on message/send", %{server: server} do
      request =
        JsonRpc.encode_request(
          "message/send",
          %{
            "message" => %{
              "kind" => "message",
              "messageId" => "m1",
              "role" => "user",
              "parts" => [%{"kind" => "text", "text" => "hello"}]
            }
          },
          "req_1"
        )

      assert {:ok, response} = BeamNative.send_request(server, request)

      assert %{"jsonrpc" => "2.0", "id" => "req_1", "result" => %{"kind" => "task"} = task} =
               response

      assert task["status"]["state"] == "completed"
      assert List.first(task["history"])["messageId"] == "m1"
    end

    test "returns a Task on tasks/get", %{server: server} do
      request = JsonRpc.encode_request("tasks/get", %{"id" => "some-task"}, 42)

      assert {:ok, %{"result" => task}} = BeamNative.send_request(server, request)
      assert task["id"] == "some-task"
      assert task["status"]["state"] == "working"
    end

    test "returns JSON-RPC error for unknown method", %{server: server} do
      request = JsonRpc.encode_request("nonexistent/method", %{}, "err_1")

      assert {:ok, response} = BeamNative.send_request(server, request)
      assert response["error"]["code"] == -32_601
      assert response["error"]["message"] =~ "nonexistent/method"
    end

    test "noproc error for dead target" do
      request = JsonRpc.encode_request("message/send", %{}, 1)
      assert {:error, :noproc} = BeamNative.send_request(:nonexistent_server, request)
    end

    test "auth failure rejects the request" do
      name = :"beam_auth_test_#{:erlang.unique_integer([:positive])}"

      # Localhost with beam disabled → peer {:beam, _} is unauthenticated
      {:ok, pid} =
        Server.start_link(
          name: name,
          handler: EchoHandler,
          auth: A2aEngine.Auth.Localhost,
          auth_opts: [allow_beam_native: false]
        )

      on_exit(fn -> Process.exit(pid, :normal) end)

      request = JsonRpc.encode_request("message/send", %{}, 1)

      assert {:ok, response} = BeamNative.send_request(name, request)
      assert response["error"]["message"] == "Unauthenticated"
    end
  end

  describe "stream_request/3" do
    test "receives ordered status-update events on message/stream", %{server: server} do
      request = JsonRpc.encode_request("message/stream", %{}, "stream_1")

      assert {:ok, stream} =
               BeamNative.stream_request(server, request, pubsub: A2aEngine.TestPubSub)

      events = Enum.to_list(stream)

      assert length(events) == 2
      [first, second] = events
      assert first["kind"] == "status-update"
      assert first["status"]["state"] == "working"
      assert first["final"] == false
      assert second["status"]["state"] == "completed"
      assert second["final"] == true
    end

    test "errors propagate to stream consumers", %{server: server} do
      request = JsonRpc.encode_request("tasks/resubscribe", %{"id" => "x"}, 1)

      {:ok, stream} = BeamNative.stream_request(server, request, pubsub: A2aEngine.TestPubSub)

      # EchoHandler doesn't implement tasks/resubscribe → stream emits error then ends
      events = Enum.to_list(stream)
      assert Enum.any?(events, &match?({:error, _}, &1))
    end

    test "requires :pubsub in opts" do
      request = JsonRpc.encode_request("message/stream", %{}, 1)

      assert_raise ArgumentError, ~r/:pubsub/, fn ->
        BeamNative.stream_request(:anything, request, [])
      end
    end
  end
end
