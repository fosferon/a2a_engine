defmodule A2aEngine.Types.PushNotificationAuthenticationInfo do
  @moduledoc """
  Optional authentication block for a PushNotificationConfig.

  Wire fields: `schemes` (required — list of supported scheme names like
  "Bearer", "Basic"), `credentials` (optional opaque credential payload).
  """

  @type t :: %__MODULE__{
          schemes: [String.t()],
          credentials: String.t() | nil
        }

  @enforce_keys [:schemes]
  defstruct [:schemes, :credentials]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = a) do
    %{"schemes" => a.schemes}
    |> maybe_put("credentials", a.credentials)
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"schemes" => schemes} = m) when is_list(schemes) do
    {:ok, %__MODULE__{schemes: schemes, credentials: m["credentials"]}}
  end

  def from_map(_), do: {:error, :invalid_push_auth_info}

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
