defmodule A2aEngine.Auth.Localhost do
  @moduledoc """
  Same-host bypass. Accepts any request whose peer socket is a loopback
  address. Intended for the BeamNative transport and for HTTP deployments
  where the port is only bound to `127.0.0.1`.

  ## Options

    * `:allow_beam_native` (default `true`) — `:beam` peers are always
      loopback-equivalent (same node or clustered connected node).
    * `:extra_allowed_ips` — additional IP addresses to treat as loopback
      (tuples like `{192, 168, 1, 10}`). Useful for trusted LAN hosts.

  ## Behaviour

    * `peer: :local` or `{:beam, _}` → accepted.
    * `peer: {:tcp, {127, 0, 0, 1}}` or `{0, 0, 0, 0, 0, 0, 0, 1}` → accepted.
    * Anything else → `:unauthenticated`.

  Returns `%{scheme: :localhost, principal: nil, extra: %{peer: <info>}}`.
  """

  @behaviour A2aEngine.Auth

  alias A2aEngine.Auth

  @loopback_v4 {127, 0, 0, 1}
  @loopback_v6 {0, 0, 0, 0, 0, 0, 0, 1}

  @impl true
  def authenticate(%{peer: peer}, opts) do
    cond do
      peer == :local ->
        {:ok, Auth.context(:localhost, nil, %{peer: :local})}

      Keyword.get(opts, :allow_beam_native, true) and match?({:beam, _}, peer) ->
        {:ok, Auth.context(:localhost, nil, %{peer: peer})}

      match?({:tcp, ip} when ip == @loopback_v4 or ip == @loopback_v6, peer) ->
        {:ok, Auth.context(:localhost, nil, %{peer: peer})}

      match?({:tcp, _}, peer) and peer_ip(peer) in Keyword.get(opts, :extra_allowed_ips, []) ->
        {:ok, Auth.context(:localhost, nil, %{peer: peer})}

      true ->
        {:error, :unauthenticated}
    end
  end

  defp peer_ip({:tcp, ip}), do: ip
  defp peer_ip(_), do: nil
end
