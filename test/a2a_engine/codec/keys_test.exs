defmodule A2aEngine.Codec.KeysTest do
  use ExUnit.Case, async: true

  alias A2aEngine.Codec.Keys

  describe "to_wire/1" do
    test "camelCase-ifies atom keys" do
      assert Keys.to_wire(%{message_id: "m", role: "user"}) ==
               %{"messageId" => "m", "role" => "user"}
    end

    test "camelCase-ifies string keys" do
      assert Keys.to_wire(%{"message_id" => "m"}) == %{"messageId" => "m"}
    end

    test "recurses into nested maps" do
      assert Keys.to_wire(%{outer_key: %{inner_key: 1}}) ==
               %{"outerKey" => %{"innerKey" => 1}}
    end

    test "recurses into lists" do
      assert Keys.to_wire([%{foo_bar: 1}, %{baz_qux: 2}]) ==
               [%{"fooBar" => 1}, %{"bazQux" => 2}]
    end

    test "preserves struct values unchanged (they get encoded by the type module)" do
      struct = %Range{first: 1, last: 3, step: 1}
      assert Keys.to_wire(struct) == struct
    end

    test "leaves scalar values alone" do
      assert Keys.to_wire(42) == 42
      assert Keys.to_wire("hello") == "hello"
      assert Keys.to_wire(nil) == nil
      assert Keys.to_wire(true) == true
    end
  end

  describe "from_wire/1" do
    test "underscores camelCase keys into atoms" do
      assert Keys.from_wire(%{"messageId" => "m"}) == %{message_id: "m"}
    end

    test "recurses" do
      assert Keys.from_wire(%{"outerKey" => %{"innerKey" => 1}}) ==
               %{outer_key: %{inner_key: 1}}
    end
  end

  describe "round-trip" do
    test "camelize → underscore is stable for A2A-shaped keys" do
      original = %{message_id: "x", parts: [%{kind: "text", text: "hi"}]}
      assert Keys.from_wire(Keys.to_wire(original)) == original
    end
  end
end
