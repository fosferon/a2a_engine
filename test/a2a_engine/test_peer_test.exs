defmodule A2aEngine.TestPeerTest do
  use ExUnit.Case, async: true

  alias A2aEngine.Codec.JsonRpc
  alias A2aEngine.{TestPeer, Transport.Http}

  setup do
    {:ok, peer} = TestPeer.start_link()
    on_exit(fn -> if Process.alive?(peer), do: TestPeer.stop(peer) end)
    {:ok, peer: peer, url: TestPeer.url(peer)}
  end

  test "unary script is dispatched + recorded", %{peer: peer, url: url} do
    :ok =
      TestPeer.script(peer, "message/send", fn params ->
        assert params["message"]["messageId"] == "m1"

        {:ok,
         %{
           "kind" => "task",
           "id" => "scripted_t1",
           "contextId" => "c1",
           "status" => %{"state" => "completed"}
         }}
      end)

    request =
      JsonRpc.encode_request(
        "message/send",
        %{
          "message" => %{
            "kind" => "message",
            "messageId" => "m1",
            "role" => "user",
            "parts" => [%{"kind" => "text", "text" => "hi"}]
          }
        },
        "req_a"
      )

    assert {:ok, %{"result" => %{"id" => "scripted_t1"}}} = Http.send_request(url, request)

    assert [{"message/send", params}] = TestPeer.received(peer)
    assert params["message"]["messageId"] == "m1"
  end

  test "unscripted method returns JSON-RPC 'method not found'", %{peer: peer, url: url} do
    request = JsonRpc.encode_request("tasks/get", %{"id" => "x"}, 1)

    assert {:ok, %{"error" => %{"code" => -32_601, "message" => msg}}} =
             Http.send_request(url, request)

    assert msg =~ "tasks/get"
    assert [{"tasks/get", _}] = TestPeer.received(peer)
  end

  test "streaming script emits events to the SSE consumer", %{peer: peer, url: url} do
    :ok =
      TestPeer.script_stream(peer, "message/stream", fn _params, emit ->
        emit.(%{
          "kind" => "status-update",
          "taskId" => "t",
          "contextId" => "c",
          "status" => %{"state" => "working"},
          "final" => false
        })

        emit.(%{
          "kind" => "status-update",
          "taskId" => "t",
          "contextId" => "c",
          "status" => %{"state" => "completed"},
          "final" => true
        })

        {:ok, :done}
      end)

    request = JsonRpc.encode_request("message/stream", %{}, "s1")

    {:ok, stream} = Http.stream_request(url, request)
    events = Enum.to_list(stream)

    assert [first, second | _] = events
    assert first["status"]["state"] == "working"
    assert second["status"]["state"] == "completed"
  end

  test "clear_received/1", %{peer: peer, url: url} do
    :ok =
      TestPeer.script(peer, "tasks/get", fn _ ->
        {:ok,
         %{"kind" => "task", "id" => "x", "contextId" => "c", "status" => %{"state" => "working"}}}
      end)

    _ = Http.send_request(url, JsonRpc.encode_request("tasks/get", %{"id" => "x"}, 1))
    assert length(TestPeer.received(peer)) == 1
    :ok = TestPeer.clear_received(peer)
    assert TestPeer.received(peer) == []
  end

  test "multiple peers run concurrently on different ports" do
    {:ok, a} = TestPeer.start_link()
    {:ok, b} = TestPeer.start_link()
    on_exit(fn -> if Process.alive?(a), do: TestPeer.stop(a) end)
    on_exit(fn -> if Process.alive?(b), do: TestPeer.stop(b) end)

    assert TestPeer.port(a) != TestPeer.port(b)

    :ok = TestPeer.script(a, "message/send", fn _ -> {:ok, %{"from" => "a"}} end)
    :ok = TestPeer.script(b, "message/send", fn _ -> {:ok, %{"from" => "b"}} end)

    req =
      JsonRpc.encode_request(
        "message/send",
        %{
          "message" => %{"kind" => "message", "messageId" => "m", "role" => "user", "parts" => []}
        },
        1
      )

    assert {:ok, %{"result" => %{"from" => "a"}}} = Http.send_request(TestPeer.url(a), req)
    assert {:ok, %{"result" => %{"from" => "b"}}} = Http.send_request(TestPeer.url(b), req)
  end
end
