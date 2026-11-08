defmodule A2aEngine.Errors do
  @moduledoc """
  A2A-specific JSON-RPC 2.0 error codes.

  Standard JSON-RPC codes are in the `-327xx` range (parse, invalid request,
  method not found, invalid params, internal). A2A-specific codes occupy
  `-32001` through `-32007`.

  Every error is wire-shaped as:

      %{"code" => integer, "message" => string, "data" => optional map}
  """

  @type code :: integer()
  @type error :: %{code: code(), message: String.t(), data: map() | nil}

  # Standard JSON-RPC 2.0 codes
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603

  # A2A-specific codes (from a2a-js types.ts, canonical)
  @task_not_found -32_001
  @task_not_cancelable -32_002
  @push_notification_not_supported -32_003
  @unsupported_operation -32_004
  @content_type_not_supported -32_005
  @invalid_agent_response -32_006
  @authenticated_extended_card_not_configured -32_007

  # ---- code accessors ----
  def parse_error, do: @parse_error
  def invalid_request, do: @invalid_request
  def method_not_found, do: @method_not_found
  def invalid_params, do: @invalid_params
  def internal_error, do: @internal_error
  def task_not_found, do: @task_not_found
  def task_not_cancelable, do: @task_not_cancelable
  def push_notification_not_supported, do: @push_notification_not_supported
  def unsupported_operation, do: @unsupported_operation
  def content_type_not_supported, do: @content_type_not_supported
  def invalid_agent_response, do: @invalid_agent_response
  def authenticated_extended_card_not_configured, do: @authenticated_extended_card_not_configured

  @default_messages %{
    @parse_error => "Parse error",
    @invalid_request => "Invalid Request",
    @method_not_found => "Method not found",
    @invalid_params => "Invalid params",
    @internal_error => "Internal error",
    @task_not_found => "Task not found",
    @task_not_cancelable => "Task cannot be canceled",
    @push_notification_not_supported => "Push Notification is not supported",
    @unsupported_operation => "This operation is not supported",
    @content_type_not_supported => "Incompatible content types",
    @invalid_agent_response => "Invalid agent response",
    @authenticated_extended_card_not_configured => "Authenticated Extended Card not configured"
  }

  @doc "Build an error map with the default message for the given code."
  @spec build(code()) :: %{code: code(), message: String.t()}
  def build(code) when is_integer(code) do
    %{code: code, message: Map.get(@default_messages, code, "Unknown error")}
  end

  @doc "Build an error map with a custom message and optional `data` payload."
  @spec build(code(), String.t(), map() | nil) :: map()
  def build(code, message, data \\ nil) when is_integer(code) and is_binary(message) do
    base = %{code: code, message: message}
    if data, do: Map.put(base, :data, data), else: base
  end

  @doc "The canonical default message for an error code."
  @spec default_message(code()) :: String.t() | nil
  def default_message(code), do: Map.get(@default_messages, code)

  @doc "Every error code defined by the spec (standard + A2A)."
  @spec all_codes() :: [code()]
  def all_codes, do: Map.keys(@default_messages)
end
