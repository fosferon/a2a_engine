defmodule A2aEngine.Auth.Bearer do
  @moduledoc """
  Bearer-token authentication.

  Configuration (passed as opts to `authenticate/2`):

    * `:tokens` — a map of `token_string => principal_name`. Principal is
      returned in the auth_context for handler use (agent name, caller id).
    * `:validator` — alternative to `:tokens`: a 1-arity function
      `(token :: String.t()) :: {:ok, principal} | :error`.
    * `:realm` — string included in the `WWW-Authenticate` hint when
      transports emit 401 responses (optional).

  One of `:tokens` or `:validator` MUST be present.

  ## Behaviour

    * Reads the `authorization` header (case-insensitive via transport
      normalisation).
    * Accepts only the `Bearer <token>` scheme. Other schemes → `:unauthenticated`.
    * Missing header or unknown token → `:unauthenticated`.
    * On success → `%{scheme: :bearer, principal: "<name>", extra: %{}}`.
  """

  @behaviour A2aEngine.Auth

  alias A2aEngine.Auth

  @impl true
  def authenticate(%{headers: headers}, opts) do
    case extract_bearer(headers) do
      {:ok, token} -> validate(token, opts)
      :error -> {:error, :unauthenticated}
    end
  end

  defp extract_bearer(headers) when is_map(headers) do
    case Map.get(headers, "authorization") do
      "Bearer " <> token when token != "" -> {:ok, token}
      "bearer " <> token when token != "" -> {:ok, token}
      _ -> :error
    end
  end

  defp validate(token, opts) do
    cond do
      is_map(opts[:tokens]) ->
        case Map.fetch(opts[:tokens], token) do
          {:ok, principal} -> {:ok, Auth.context(:bearer, principal)}
          :error -> {:error, :unauthenticated}
        end

      is_function(opts[:validator], 1) ->
        case opts[:validator].(token) do
          {:ok, principal} -> {:ok, Auth.context(:bearer, principal)}
          :error -> {:error, :unauthenticated}
          {:error, reason} -> {:error, reason}
        end

      true ->
        raise ArgumentError,
              "A2aEngine.Auth.Bearer requires :tokens map or :validator function in opts"
    end
  end
end
