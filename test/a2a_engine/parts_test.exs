defmodule A2aEngine.PartsTest do
  use ExUnit.Case, async: true

  alias A2aEngine.Parts

  defp text_part(text), do: %{"kind" => "text", "text" => text}

  defp file_part(name), do: %{"kind" => "file", "file" => %{"name" => name}}

  defp data_part(data, metadata \\ nil) do
    base = %{"kind" => "data", "data" => data}
    if metadata, do: Map.put(base, "metadata", metadata), else: base
  end

  defp checkpoint(owner, data \\ %{"cursor" => 1}) do
    data_part(data, %{"type" => "checkpoint", "owner" => owner, "session" => "s-1"})
  end

  describe "filter_by_owner/2" do
    test "keeps text parts regardless of recipient" do
      parts = [text_part("hello")]
      assert Parts.filter_by_owner(parts, "anybody") == parts
    end

    test "keeps file parts regardless of recipient" do
      parts = [file_part("out.md")]
      assert Parts.filter_by_owner(parts, "anybody") == parts
    end

    test "keeps DataParts without checkpoint metadata" do
      parts = [data_part(%{"public" => true})]
      assert Parts.filter_by_owner(parts, "anybody") == parts
    end

    test "keeps DataPart with non-checkpoint metadata (unrelated type)" do
      parts = [data_part(%{"x" => 1}, %{"type" => "schema", "id" => "foo"})]
      assert Parts.filter_by_owner(parts, "anybody") == parts
    end

    test "keeps checkpoint whose owner matches the recipient" do
      parts = [checkpoint("planner")]
      assert Parts.filter_by_owner(parts, "planner") == parts
    end

    test "drops checkpoint whose owner differs from the recipient" do
      parts = [checkpoint("planner")]
      assert Parts.filter_by_owner(parts, "reviewer") == []
    end

    test "mixed: keeps public parts and recipient-owned checkpoint, drops foreign checkpoint" do
      parts = [
        text_part("public narrative"),
        checkpoint("planner"),
        checkpoint("reviewer"),
        data_part(%{"public_data" => true})
      ]

      result = Parts.filter_by_owner(parts, "planner")

      assert length(result) == 3

      refute Enum.any?(result, fn p ->
               p["kind"] == "data" and get_in(p, ["metadata", "owner"]) == "reviewer"
             end)
    end

    test "preserves order of kept parts" do
      a = text_part("a")
      b = checkpoint("reviewer")
      c = text_part("c")
      d = checkpoint("planner")

      assert Parts.filter_by_owner([a, b, c, d], "planner") == [a, c, d]
    end

    test "non-list input returns []" do
      assert Parts.filter_by_owner(%{"not" => "a list"}, "anybody") == []
    end
  end

  describe "visible_to?/2" do
    test "false for foreign checkpoint" do
      refute Parts.visible_to?(checkpoint("reviewer"), "planner")
    end

    test "true for own checkpoint" do
      assert Parts.visible_to?(checkpoint("planner"), "planner")
    end

    test "true for any non-checkpoint part" do
      assert Parts.visible_to?(text_part("x"), "anybody")
      assert Parts.visible_to?(file_part("f.bin"), "anybody")
      assert Parts.visible_to?(data_part(%{"x" => 1}), "anybody")
    end
  end
end
