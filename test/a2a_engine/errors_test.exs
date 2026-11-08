defmodule A2aEngine.ErrorsTest do
  use ExUnit.Case, async: true

  alias A2aEngine.Errors

  test "canonical code constants match the A2A spec" do
    # Standard JSON-RPC
    assert Errors.parse_error() == -32_700
    assert Errors.invalid_request() == -32_600
    assert Errors.method_not_found() == -32_601
    assert Errors.invalid_params() == -32_602
    assert Errors.internal_error() == -32_603

    # A2A-specific (from a2a-js types.ts — canonical)
    assert Errors.task_not_found() == -32_001
    assert Errors.task_not_cancelable() == -32_002
    assert Errors.push_notification_not_supported() == -32_003
    assert Errors.unsupported_operation() == -32_004
    assert Errors.content_type_not_supported() == -32_005
    assert Errors.invalid_agent_response() == -32_006
    assert Errors.authenticated_extended_card_not_configured() == -32_007
  end

  test "build/1 fills in the canonical message" do
    assert Errors.build(Errors.task_not_found()) ==
             %{code: -32_001, message: "Task not found"}
  end

  test "build/3 accepts custom message and optional data" do
    assert Errors.build(-32_001, "Custom message", %{"hint" => "check id"}) ==
             %{code: -32_001, message: "Custom message", data: %{"hint" => "check id"}}
  end

  test "build/3 omits data when nil" do
    err = Errors.build(-32_001, "x", nil)
    refute Map.has_key?(err, :data)
  end

  test "default_message/1" do
    assert Errors.default_message(-32_001) == "Task not found"
    assert Errors.default_message(99_999) == nil
  end

  test "all_codes/0 is exhaustive" do
    codes = Errors.all_codes()

    assert -32_001 in codes
    assert -32_007 in codes
    assert length(codes) == 12
  end
end
