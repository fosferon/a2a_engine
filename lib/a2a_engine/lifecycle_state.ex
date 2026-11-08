defmodule A2aEngine.LifecycleState do
  @moduledoc """
  A2A Task lifecycle states.

  Wire values are lowercase, hyphen-separated strings — exactly as the spec
  defines them. We keep them as strings (not atoms) to round-trip the wire
  format faithfully.

  ## States

    * `"submitted"` — task received, not yet being worked on
    * `"working"` — in progress
    * `"input-required"` — worker needs caller input before continuing
    * `"completed"` — terminal success
    * `"canceled"` — terminal, user-requested
    * `"failed"` — terminal, error
    * `"rejected"` — terminal, worker refused
    * `"auth-required"` — caller needs to re-authenticate
    * `"unknown"` — fallback / indeterminate
  """

  @states ~w(submitted working input-required completed canceled failed rejected auth-required unknown)

  @type t :: String.t()

  @doc "All valid state strings."
  @spec all() :: [t()]
  def all, do: @states

  @doc "Whether `value` is a recognised A2A lifecycle state."
  @spec valid?(any()) :: boolean()
  def valid?(value), do: value in @states

  @doc """
  Terminal states — no further transitions possible.

      iex> A2aEngine.LifecycleState.terminal?("completed")
      true
      iex> A2aEngine.LifecycleState.terminal?("working")
      false
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(state), do: state in ~w(completed canceled failed rejected)
end
