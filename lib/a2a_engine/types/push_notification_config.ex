defmodule A2aEngine.Types.PushNotificationConfig do
  @moduledoc """
  Webhook configuration for receiving asynchronous task updates.

  Wire fields: `url` (required), `id` (client-assigned, supports multiple
  callbacks per task), `token` (opaque per-task validation token),
  `authentication` (optional auth info).
  """

  alias A2aEngine.Types.PushNotificationAuthenticationInfo, as: AuthInfo

  @type t :: %__MODULE__{
          url: String.t(),
          id: String.t() | nil,
          token: String.t() | nil,
          authentication: AuthInfo.t() | nil
        }

  @enforce_keys [:url]
  defstruct [:url, :id, :token, :authentication]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = c) do
    %{"url" => c.url}
    |> maybe_put("id", c.id)
    |> maybe_put("token", c.token)
    |> maybe_put("authentication", c.authentication && AuthInfo.to_map(c.authentication))
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"url" => url} = m) when is_binary(url) do
    with {:ok, auth} <- decode_auth(m["authentication"]) do
      {:ok,
       %__MODULE__{
         url: url,
         id: m["id"],
         token: m["token"],
         authentication: auth
       }}
    end
  end

  def from_map(_), do: {:error, :invalid_push_config}

  defp decode_auth(nil), do: {:ok, nil}
  defp decode_auth(%{} = m), do: AuthInfo.from_map(m)

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
