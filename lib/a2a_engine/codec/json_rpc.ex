defmodule A2aEngine.Codec.JsonRpc do
  @moduledoc """
  JSON-RPC 2.0 envelope codec with A2A method registry.

  Keeps the envelope layer thin: `params` and `result` are passed through
  as plain maps. Callers handle A2A type encoding/decoding (via the
  `A2aEngine.Types.*` modules) before/after.

  ## A2A methods

  The known method strings are registered in `@methods`. Use `method/1` to
  resolve an atom key to a string, and `atom_for_method/1` to parse a string
  back to an atom.
  """

  alias A2aEngine.Errors

  @jsonrpc "2.0"

  @methods %{
    message_send: "message/send",
    message_stream: "message/stream",
    tasks_get: "tasks/get",
    tasks_cancel: "tasks/cancel",
    tasks_resubscribe: "tasks/resubscribe",
    tasks_push_notification_config_set: "tasks/pushNotificationConfig/set",
    tasks_push_notification_config_get: "tasks/pushNotificationConfig/get",
    tasks_push_notification_config_list: "tasks/pushNotificationConfig/list",
    tasks_push_notification_config_delete: "tasks/pushNotificationConfig/delete",
    agent_get_authenticated_extended_card: "agent/getAuthenticatedExtendedCard"
  }

  @method_strings @methods |> Map.values() |> MapSet.new()

  @type id :: String.t() | integer() | nil
  @type request :: %{String.t() => term()}
  @type response :: %{String.t() => term()}
  @type decoded_request :: %{id: id(), method: String.t(), params: map() | nil}
  @type decoded_response ::
          {:success, id(), term()}
          | {:error, id(), %{code: integer(), message: String.t(), data: map() | nil}}

  @doc "All known A2A method atoms → wire strings."
  @spec methods() :: %{atom() => String.t()}
  def methods, do: @methods

  @doc "Look up the wire string for a known A2A method atom."
  @spec method(atom()) :: String.t()
  def method(atom), do: Map.fetch!(@methods, atom)

  @doc """
  Look up the atom for a wire method string. Returns `:unknown` if the
  method isn't in the A2A registry (still valid JSON-RPC, just not A2A).
  """
  @spec atom_for_method(String.t()) :: atom() | :unknown
  def atom_for_method(str) when is_binary(str) do
    case Enum.find(@methods, fn {_k, v} -> v == str end) do
      {k, _v} -> k
      nil -> :unknown
    end
  end

  @doc "Whether a wire method string is one of the known A2A methods."
  @spec known_method?(String.t()) :: boolean()
  def known_method?(str), do: MapSet.member?(@method_strings, str)

  # ---- encode ----

  @doc "Build a JSON-RPC 2.0 request envelope."
  @spec encode_request(String.t(), map() | nil, id()) :: request()
  def encode_request(method, params, id) when is_binary(method) do
    base = %{"jsonrpc" => @jsonrpc, "id" => id, "method" => method}
    if is_nil(params), do: base, else: Map.put(base, "params", params)
  end

  @doc "Build a JSON-RPC 2.0 success response envelope."
  @spec encode_success(id(), term()) :: response()
  def encode_success(id, result) do
    %{"jsonrpc" => @jsonrpc, "id" => id, "result" => result}
  end

  @doc """
  Build a JSON-RPC 2.0 error response envelope.

  Accepts either an `%{code, message, data}` map or a code integer (in which
  case the default message for that code is used).
  """
  @spec encode_error(id(), integer() | map(), String.t() | nil, map() | nil) :: response()
  def encode_error(id, code_or_error, message \\ nil, data \\ nil)

  def encode_error(id, %{code: _, message: _} = error_map, _, _) do
    error = %{"code" => error_map.code, "message" => error_map.message}
    error = if error_map[:data], do: Map.put(error, "data", error_map.data), else: error
    %{"jsonrpc" => @jsonrpc, "id" => id, "error" => error}
  end

  def encode_error(id, code, message, data) when is_integer(code) do
    msg = message || Errors.default_message(code) || "Unknown error"
    error = %{"code" => code, "message" => msg}
    error = if data, do: Map.put(error, "data", data), else: error
    %{"jsonrpc" => @jsonrpc, "id" => id, "error" => error}
  end

  # ---- decode ----

  @doc """
  Decode a JSON-RPC 2.0 request envelope.

  Returns `{:ok, %{id, method, params}}` or `{:error, reason}`.
  """
  @spec decode_request(map()) :: {:ok, decoded_request()} | {:error, term()}
  def decode_request(%{"jsonrpc" => @jsonrpc, "method" => method} = m)
      when is_binary(method) do
    id =
      case Map.fetch(m, "id") do
        {:ok, v} -> v
        :error -> nil
      end

    {:ok, %{id: id, method: method, params: Map.get(m, "params")}}
  end

  def decode_request(%{"jsonrpc" => v}) when v != @jsonrpc do
    {:error, {:unsupported_jsonrpc_version, v}}
  end

  def decode_request(_), do: {:error, :invalid_request}

  @doc """
  Decode a JSON-RPC 2.0 response envelope.

  Returns `{:ok, {:success, id, result}}`, `{:ok, {:error, id, error_map}}`,
  or `{:error, reason}`.
  """
  @spec decode_response(map()) :: {:ok, decoded_response()} | {:error, term()}
  def decode_response(%{"jsonrpc" => @jsonrpc, "id" => id, "result" => result}) do
    {:ok, {:success, id, result}}
  end

  def decode_response(%{
        "jsonrpc" => @jsonrpc,
        "id" => id,
        "error" => %{"code" => code, "message" => msg} = err
      })
      when is_integer(code) and is_binary(msg) do
    {:ok, {:error, id, %{code: code, message: msg, data: err["data"]}}}
  end

  def decode_response(%{"jsonrpc" => v}) when v != @jsonrpc do
    {:error, {:unsupported_jsonrpc_version, v}}
  end

  def decode_response(_), do: {:error, :invalid_response}
end
