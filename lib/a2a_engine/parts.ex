defmodule A2aEngine.Parts do
  @moduledoc """
  Helpers that operate on a list of decoded Part maps (the shape
  Parts take once JSON-decoded but before being encoded back for
  transport).

  ## Owner filtering

  The checkpoint-in-envelope convention (see `A2aEngine.Types.DataPart`)
  stores worker/caller resumable state as a `DataPart` tagged
  `metadata: {"type" => "checkpoint", "owner" => <agent>, "session" => <id>}`.
  A broker forwarding a message to the next hop should only include
  checkpoints whose owner matches the recipient — otherwise each
  side's private state leaks to the other.

  `filter_by_owner/2` enforces that rule. TextParts, FileParts, and
  DataParts without checkpoint metadata pass through unchanged —
  this function only acts on tagged checkpoints.
  """

  @doc """
  Keep only the Parts that the named recipient is allowed to see.

  * TextPart / FilePart → always kept.
  * DataPart without checkpoint metadata → always kept.
  * DataPart with `metadata.type == "checkpoint"` → kept **only** if
    `metadata.owner == recipient`.
  """
  @spec filter_by_owner([map()], String.t()) :: [map()]
  def filter_by_owner(parts, recipient) when is_list(parts) and is_binary(recipient) do
    Enum.filter(parts, &visible_to?(&1, recipient))
  end

  def filter_by_owner(_, _), do: []

  @doc """
  Same rule at the part level. Useful for artifact-carried
  DataParts where the artifact itself is public but an embedded
  DataPart may be private.
  """
  @spec visible_to?(map(), String.t()) :: boolean()
  def visible_to?(
        %{"kind" => "data", "metadata" => %{"type" => "checkpoint", "owner" => owner}},
        recipient
      ) do
    owner == recipient
  end

  def visible_to?(_part, _recipient), do: true
end
