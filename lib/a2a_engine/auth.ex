defmodule A2aEngine.Auth do
  @moduledoc """
  Behaviour for authenticating an inbound A2A request at the transport
  boundary.

  Hosts wire an `A2aEngine.Auth` implementation into each transport so
  request dispatch can either:

    * succeed with an `auth_context` that downstream handlers can inspect, or
    * reject the request without touching the handler.

  ## Built-in implementations

    * `A2aEngine.Auth.Bearer` — shared-secret tokens (with allowlist or
      custom validator). Day-1 default for external peers.
    * `A2aEngine.Auth.Localhost` — same-host bypass. Trusts requests whose
      peer socket is `127.0.0.1` or `::1`.

  OAuth2 / OIDC implementations slot in later as additional modules
  without changing the behaviour.

  ## request_info shape

  The transport layer normalises the incoming request into a uniform
  map before handing it to the auth impl:

      %{
        headers: %{"authorization" => "Bearer ..."},
        peer: {:tcp, {127, 0, 0, 1}} | {:beam, :"app@host"} | :local,
        transport: :http | :beam_native
      }

  ## auth_context shape

  On success, the impl returns an `auth_context` that travels into
  handler calls:

      %{
        scheme: :bearer | :localhost | :anonymous | atom(),
        principal: "agent_name" | nil,
        extra: %{...}   # impl-specific
      }

  ## Error kinds

  On rejection, impls return `{:error, :unauthenticated | :forbidden}`.
  Transports translate to HTTP 401/403 (for HTTP) or a JSON-RPC
  invalid-request / internal-error envelope (for BeamNative).
  """

  @type request_info :: %{
          required(:headers) => %{String.t() => String.t()},
          required(:peer) => {:tcp, :inet.ip_address()} | {:beam, node()} | :local,
          required(:transport) => :http | :beam_native
        }

  @type auth_context :: %{
          required(:scheme) => atom(),
          required(:principal) => String.t() | nil,
          required(:extra) => map()
        }

  @type error :: :unauthenticated | :forbidden | {atom(), map()}

  @callback authenticate(request_info(), opts :: keyword()) ::
              {:ok, auth_context()} | {:error, error()}

  @doc "Shortcut for building an auth_context with defaults filled in."
  @spec context(atom(), String.t() | nil, map()) :: auth_context()
  def context(scheme, principal \\ nil, extra \\ %{}) do
    %{scheme: scheme, principal: principal, extra: extra}
  end
end
