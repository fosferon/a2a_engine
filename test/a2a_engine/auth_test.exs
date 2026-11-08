defmodule A2aEngine.AuthTest do
  use ExUnit.Case, async: true

  alias A2aEngine.Auth
  alias A2aEngine.Auth.{Bearer, Localhost}

  describe "Auth.context/3 helper" do
    test "builds with defaults" do
      assert Auth.context(:bearer) == %{scheme: :bearer, principal: nil, extra: %{}}
    end

    test "builds with principal and extra" do
      assert Auth.context(:bearer, "agent", %{trust: :high}) ==
               %{scheme: :bearer, principal: "agent", extra: %{trust: :high}}
    end
  end

  describe "Auth.Bearer with :tokens map" do
    setup do
      tokens = %{"secret-agent-token" => "agent", "secret-ops-token" => "ops"}
      {:ok, opts: [tokens: tokens]}
    end

    test "accepts valid Bearer token with principal", %{opts: opts} do
      req = %{
        headers: %{"authorization" => "Bearer secret-agent-token"},
        peer: :local,
        transport: :http
      }

      assert {:ok, %{scheme: :bearer, principal: "agent"}} = Bearer.authenticate(req, opts)
    end

    test "accepts lowercase bearer scheme", %{opts: opts} do
      req = %{
        headers: %{"authorization" => "bearer secret-ops-token"},
        peer: :local,
        transport: :http
      }

      assert {:ok, %{principal: "ops"}} = Bearer.authenticate(req, opts)
    end

    test "rejects unknown token", %{opts: opts} do
      req = %{headers: %{"authorization" => "Bearer wrong-token"}, peer: :local, transport: :http}

      assert {:error, :unauthenticated} = Bearer.authenticate(req, opts)
    end

    test "rejects wrong scheme", %{opts: opts} do
      req = %{headers: %{"authorization" => "Basic dXNlcjpwYXNz"}, peer: :local, transport: :http}

      assert {:error, :unauthenticated} = Bearer.authenticate(req, opts)
    end

    test "rejects missing Authorization header", %{opts: opts} do
      req = %{headers: %{}, peer: :local, transport: :http}

      assert {:error, :unauthenticated} = Bearer.authenticate(req, opts)
    end

    test "rejects empty token", %{opts: opts} do
      req = %{headers: %{"authorization" => "Bearer "}, peer: :local, transport: :http}

      assert {:error, :unauthenticated} = Bearer.authenticate(req, opts)
    end
  end

  describe "Auth.Bearer with :validator function" do
    test "passes through validator result" do
      validator = fn
        "good" -> {:ok, "alice"}
        _ -> :error
      end

      req = %{headers: %{"authorization" => "Bearer good"}, peer: :local, transport: :http}

      assert {:ok, %{principal: "alice"}} = Bearer.authenticate(req, validator: validator)

      bad_req = %{req | headers: %{"authorization" => "Bearer bad"}}
      assert {:error, :unauthenticated} = Bearer.authenticate(bad_req, validator: validator)
    end

    test "raises when neither :tokens nor :validator supplied" do
      req = %{headers: %{"authorization" => "Bearer x"}, peer: :local, transport: :http}

      assert_raise ArgumentError, fn -> Bearer.authenticate(req, []) end
    end
  end

  describe "Auth.Localhost" do
    test "accepts :local peer" do
      req = %{headers: %{}, peer: :local, transport: :beam_native}

      assert {:ok, %{scheme: :localhost, extra: %{peer: :local}}} =
               Localhost.authenticate(req, [])
    end

    test "accepts {:beam, _} peer by default" do
      req = %{headers: %{}, peer: {:beam, :node@host}, transport: :beam_native}
      assert {:ok, %{scheme: :localhost}} = Localhost.authenticate(req, [])
    end

    test "rejects {:beam, _} peer when disabled" do
      req = %{headers: %{}, peer: {:beam, :node@host}, transport: :beam_native}
      assert {:error, :unauthenticated} = Localhost.authenticate(req, allow_beam_native: false)
    end

    test "accepts loopback IPv4" do
      req = %{headers: %{}, peer: {:tcp, {127, 0, 0, 1}}, transport: :http}
      assert {:ok, %{scheme: :localhost}} = Localhost.authenticate(req, [])
    end

    test "accepts loopback IPv6" do
      req = %{headers: %{}, peer: {:tcp, {0, 0, 0, 0, 0, 0, 0, 1}}, transport: :http}
      assert {:ok, %{scheme: :localhost}} = Localhost.authenticate(req, [])
    end

    test "rejects non-loopback IP" do
      req = %{headers: %{}, peer: {:tcp, {10, 0, 0, 5}}, transport: :http}
      assert {:error, :unauthenticated} = Localhost.authenticate(req, [])
    end

    test "accepts extra_allowed_ips" do
      req = %{headers: %{}, peer: {:tcp, {10, 0, 0, 5}}, transport: :http}

      assert {:ok, %{scheme: :localhost}} =
               Localhost.authenticate(req, extra_allowed_ips: [{10, 0, 0, 5}])
    end
  end
end
