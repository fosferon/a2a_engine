defmodule A2aEngine.ConformanceTest do
  @moduledoc """
  Transport conformance suite — the semantic contract enforced across
  every `A2aEngine.Transport` implementation.

  Each scenario runs against BOTH `Transport.BeamNative` and
  `Transport.Http`. Any semantic drift between transports is a bug.
  """

  use ExUnit.Case, async: false

  alias A2aEngine.Codec.JsonRpc
  alias A2aEngine.Transport.{BeamNative, Http}
  alias A2aEngine.Transport.BeamNative.Server
  alias A2aEngine.TestSupport.EchoHandler

  @sample_message %{
    "kind" => "message",
    "messageId" => "m1",
    "role" => "user",
    "parts" => [%{"kind" => "text", "text" => "hello"}]
  }

  # ---- fixtures ----

  defp beam_native_fixture(auth_opts \\ []) do
    name = :"conformance_beam_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      Server.start_link(
        name: name,
        handler: EchoHandler,
        auth: Keyword.get(auth_opts, :auth, A2aEngine.Auth.Localhost),
        auth_opts: Keyword.get(auth_opts, :auth_opts, []),
        pubsub: A2aEngine.TestPubSub
      )

    %{
      name: :beam_native,
      send_request: fn req -> BeamNative.send_request(name, req) end,
      stream_request: fn req ->
        BeamNative.stream_request(name, req, pubsub: A2aEngine.TestPubSub)
      end,
      cleanup: fn -> if Process.alive?(pid), do: Process.exit(pid, :normal) end
    }
  end

  defp http_fixture(auth_opts \\ []) do
    plug_opts = [
      handler: EchoHandler,
      auth: Keyword.get(auth_opts, :auth, A2aEngine.Auth.Localhost),
      auth_opts: Keyword.get(auth_opts, :auth_opts, [])
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

    request_headers = Keyword.get(auth_opts, :headers, [])

    %{
      name: :http,
      send_request: fn req -> Http.send_request(url, req, headers: request_headers) end,
      stream_request: fn req -> Http.stream_request(url, req, headers: request_headers) end,
      cleanup: fn -> if Process.alive?(bandit), do: Process.exit(bandit, :normal) end
    }
  end

  # ---- scenario assertions (shared across transports) ----

  defp assert_happy_unary(ctx) do
    request =
      JsonRpc.encode_request(
        "message/send",
        %{"message" => @sample_message},
        "req_happy"
      )

    assert {:ok, response} = ctx.send_request.(request)
    assert %{"jsonrpc" => "2.0", "id" => "req_happy"} = response
    assert %{"kind" => "task", "status" => %{"state" => "completed"}} = response["result"]
  end

  defp assert_id_preserved(ctx) do
    for id <- ["str-id", 42, nil] do
      request = JsonRpc.encode_request("tasks/get", %{"id" => "x"}, id)
      assert {:ok, response} = ctx.send_request.(request)
      assert response["id"] == id, "id #{inspect(id)} was not preserved"
    end
  end

  defp assert_unknown_method_error(ctx) do
    request = JsonRpc.encode_request("unknown/method", %{}, "req_err")
    assert {:ok, response} = ctx.send_request.(request)
    assert response["error"]["code"] == -32_601
    assert response["id"] == "req_err"
  end

  defp assert_tasks_get_returns_task(ctx) do
    request = JsonRpc.encode_request("tasks/get", %{"id" => "some-task"}, 7)
    assert {:ok, response} = ctx.send_request.(request)
    assert %{"kind" => "task", "id" => "some-task"} = response["result"]
  end

  defp assert_tasks_cancel_returns_canceled(ctx) do
    request = JsonRpc.encode_request("tasks/cancel", %{"id" => "t-cancel"}, 8)
    assert {:ok, response} = ctx.send_request.(request)
    assert response["result"]["status"]["state"] == "canceled"
  end

  defp assert_stream_happy(ctx) do
    request = JsonRpc.encode_request("message/stream", %{}, "sh")
    assert {:ok, stream} = ctx.stream_request.(request)

    events = Enum.to_list(stream) |> Enum.reject(&match?({:error, _}, &1))

    assert length(events) >= 2
    assert List.first(events)["status"]["state"] == "working"
    assert Enum.any?(events, &(&1["status"]["state"] == "completed"))
    assert List.last(events)["final"] == true
  end

  defp assert_stream_unknown_method(ctx) do
    # EchoHandler.handle_stream returns {:error, _} for non-message/stream methods
    request = JsonRpc.encode_request("tasks/resubscribe", %{"id" => "x"}, 1)
    assert {:ok, stream} = ctx.stream_request.(request)

    events = Enum.to_list(stream)

    # Either an explicit error tuple (BeamNative) or no status-update events (Http sends error via SSE)
    assert events == [] or Enum.any?(events, &match?({:error, _}, &1))
  end

  defp assert_auth_rejection(ctx) do
    request = JsonRpc.encode_request("message/send", %{"message" => @sample_message}, "req_auth")
    result = ctx.send_request.(request)

    # Both transports must REJECT when auth says no:
    # - BeamNative: {:ok, error_envelope}
    # - Http: {:error, {:http_status, 401, _}}
    case result do
      {:ok, %{"error" => %{"message" => msg}}} -> assert msg =~ "nauthenticated"
      {:error, {:http_status, 401, _}} -> :ok
      other -> flunk("expected auth rejection, got #{inspect(other)}")
    end
  end

  # ---- BeamNative conformance ----

  describe "BeamNative transport" do
    setup do
      ctx = beam_native_fixture()
      on_exit(ctx.cleanup)
      {:ok, ctx: ctx}
    end

    test("1. unary happy path (message/send)", %{ctx: ctx}, do: assert_happy_unary(ctx))
    test("2. id preservation", %{ctx: ctx}, do: assert_id_preserved(ctx))
    test("3. unknown method → -32601", %{ctx: ctx}, do: assert_unknown_method_error(ctx))
    test("4. tasks/get → Task", %{ctx: ctx}, do: assert_tasks_get_returns_task(ctx))
    test("5. tasks/cancel → canceled", %{ctx: ctx}, do: assert_tasks_cancel_returns_canceled(ctx))
    test("6. stream happy path", %{ctx: ctx}, do: assert_stream_happy(ctx))
    test("7. stream unknown method", %{ctx: ctx}, do: assert_stream_unknown_method(ctx))

    test "8. auth rejection (allow_beam_native: false)" do
      ctx = beam_native_fixture(auth_opts: [allow_beam_native: false])
      on_exit(ctx.cleanup)
      assert_auth_rejection(ctx)
    end
  end

  # ---- Http conformance ----

  describe "Http transport" do
    setup do
      ctx = http_fixture()
      on_exit(ctx.cleanup)
      {:ok, ctx: ctx}
    end

    test("1. unary happy path (message/send)", %{ctx: ctx}, do: assert_happy_unary(ctx))
    test("2. id preservation", %{ctx: ctx}, do: assert_id_preserved(ctx))
    test("3. unknown method → -32601", %{ctx: ctx}, do: assert_unknown_method_error(ctx))
    test("4. tasks/get → Task", %{ctx: ctx}, do: assert_tasks_get_returns_task(ctx))
    test("5. tasks/cancel → canceled", %{ctx: ctx}, do: assert_tasks_cancel_returns_canceled(ctx))
    test("6. stream happy path", %{ctx: ctx}, do: assert_stream_happy(ctx))
    test("7. stream unknown method", %{ctx: ctx}, do: assert_stream_unknown_method(ctx))

    test "8. auth rejection (Bearer with wrong token)" do
      ctx =
        http_fixture(
          auth: A2aEngine.Auth.Bearer,
          auth_opts: [tokens: %{"valid" => "p"}],
          headers: [{"authorization", "Bearer wrong"}]
        )

      on_exit(ctx.cleanup)
      assert_auth_rejection(ctx)
    end
  end
end
