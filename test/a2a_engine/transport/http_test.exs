defmodule A2aEngine.Transport.HttpTest do
  use ExUnit.Case, async: false

  alias A2aEngine.Codec.JsonRpc
  alias A2aEngine.Transport.Http
  alias A2aEngine.TestSupport.EchoHandler

  setup_all do
    plug_opts = [
      handler: EchoHandler,
      auth: A2aEngine.Auth.Localhost,
      auth_opts: []
    ]

    {:ok, bandit} =
      Bandit.start_link(
        plug: {A2aEngine.Transport.Http.Plug, plug_opts},
        scheme: :http,
        port: 0,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)

    on_exit(fn ->
      if Process.alive?(bandit), do: Process.exit(bandit, :normal)
    end)

    {:ok, url: "http://127.0.0.1:#{port}"}
  end

  describe "send_request/3 (unary)" do
    test "returns a Task on message/send", %{url: url} do
      request =
        JsonRpc.encode_request(
          "message/send",
          %{
            "message" => %{
              "kind" => "message",
              "messageId" => "m1",
              "role" => "user",
              "parts" => [%{"kind" => "text", "text" => "hello http"}]
            }
          },
          "req_1"
        )

      assert {:ok, response} = Http.send_request(url, request)

      assert %{"jsonrpc" => "2.0", "id" => "req_1", "result" => %{"kind" => "task"} = task} =
               response

      assert task["status"]["state"] == "completed"
      assert List.first(task["history"])["messageId"] == "m1"
    end

    test "returns JSON-RPC error for unknown method", %{url: url} do
      request = JsonRpc.encode_request("nonexistent/method", %{}, "err_1")

      assert {:ok, response} = Http.send_request(url, request)
      assert response["error"]["code"] == -32_601
    end

    test "returns 400 for malformed body", %{url: url} do
      assert {:error, {:http_status, 400, _body}} =
               Http.send_request(url, %{"not" => "a jsonrpc envelope"})
    end
  end

  describe "stream_request/3 (SSE)" do
    test "receives ordered status-update events", %{url: url} do
      request = JsonRpc.encode_request("message/stream", %{}, "stream_http_1")

      assert {:ok, stream} = Http.stream_request(url, request)
      events = Enum.to_list(stream)

      assert length(events) >= 2
      [first, second | _] = events
      assert first["kind"] == "status-update"
      assert first["status"]["state"] == "working"
      assert second["status"]["state"] == "completed"
      assert second["final"] == true
    end
  end

  describe "auth layer" do
    test "Bearer rejects requests with wrong token (separate server)" do
      plug_opts = [
        handler: EchoHandler,
        auth: A2aEngine.Auth.Bearer,
        auth_opts: [tokens: %{"good-token" => "agent"}]
      ]

      {:ok, bandit} =
        Bandit.start_link(
          plug: {A2aEngine.Transport.Http.Plug, plug_opts},
          scheme: :http,
          port: 0,
          startup_log: false
        )

      {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
      url = "http://127.0.0.1:#{port}"
      on_exit(fn -> if Process.alive?(bandit), do: Process.exit(bandit, :normal) end)

      request =
        JsonRpc.encode_request(
          "message/send",
          %{
            "message" => %{
              "kind" => "message",
              "messageId" => "m",
              "role" => "user",
              "parts" => []
            }
          },
          1
        )

      # No auth header → 401
      assert {:error, {:http_status, 401, _}} = Http.send_request(url, request)

      # Wrong token → 401
      assert {:error, {:http_status, 401, _}} =
               Http.send_request(url, request, headers: [{"authorization", "Bearer wrong"}])

      # Good token → 200
      assert {:ok, %{"result" => _}} =
               Http.send_request(url, request, headers: [{"authorization", "Bearer good-token"}])
    end
  end
end
