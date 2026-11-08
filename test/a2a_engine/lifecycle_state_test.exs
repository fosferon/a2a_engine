defmodule A2aEngine.LifecycleStateTest do
  use ExUnit.Case, async: true
  doctest A2aEngine.LifecycleState

  alias A2aEngine.LifecycleState, as: LS

  test "all/0 lists every canonical state string" do
    assert LS.all() ==
             ~w(submitted working input-required completed canceled failed rejected auth-required unknown)
  end

  test "valid?/1 accepts canonical strings only" do
    for state <- LS.all(), do: assert(LS.valid?(state))

    refute LS.valid?("pending")
    refute LS.valid?("Working")
    refute LS.valid?(:working)
    refute LS.valid?(nil)
  end

  describe "terminal?/1" do
    test "terminal states" do
      for state <- ~w(completed canceled failed rejected) do
        assert LS.terminal?(state), "#{state} should be terminal"
      end
    end

    test "non-terminal states" do
      for state <- ~w(submitted working input-required auth-required unknown) do
        refute LS.terminal?(state), "#{state} should not be terminal"
      end
    end
  end
end
