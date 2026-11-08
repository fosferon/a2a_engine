defmodule A2aEngine.Codec.Keys do
  @moduledoc """
  Key-case conversion between A2A wire format (camelCase strings) and
  Elixir conventions (snake_case atoms).

    * `to_wire/1` — struct/map/list → camelCase-keyed map (strings), recursive
    * `from_wire/1` — camelCase-keyed map → snake_case atom-keyed map, recursive

  Both preserve values unchanged; only keys are transformed.
  """

  @doc """
  Recursively camelCase-ify map keys. Preserves non-map/list values.
  Atom keys are stringified; string keys are camelized; other keys pass through.
  """
  @spec to_wire(any()) :: any()
  def to_wire(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {camelize_key(k), to_wire(v)} end)
  end

  def to_wire(list) when is_list(list), do: Enum.map(list, &to_wire/1)
  def to_wire(other), do: other

  @doc """
  Recursively snake_case-ify map keys into atoms. Preserves non-map/list values.
  Uses `String.to_atom/1` to accept unknown keys — only call on trusted input
  sources (the A2A spec has a known key set).
  """
  @spec from_wire(any()) :: any()
  def from_wire(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {underscore_key(k), from_wire(v)} end)
  end

  def from_wire(list) when is_list(list), do: Enum.map(list, &from_wire/1)
  def from_wire(other), do: other

  # ---- private ----

  defp camelize_key(k) when is_atom(k), do: k |> Atom.to_string() |> camelize_str()
  defp camelize_key(k) when is_binary(k), do: camelize_str(k)
  defp camelize_key(k), do: k

  defp camelize_str(""), do: ""

  defp camelize_str(s) do
    case String.split(s, "_") do
      [""] -> ""
      [first] -> first
      [first | rest] -> first <> Enum.map_join(rest, "", &capitalize_first/1)
    end
  end

  defp capitalize_first(""), do: ""

  defp capitalize_first(<<c::utf8, rest::binary>>),
    do: <<String.upcase(<<c::utf8>>)::binary, rest::binary>>

  defp underscore_key(k) when is_binary(k), do: k |> Macro.underscore() |> String.to_atom()
  defp underscore_key(k) when is_atom(k), do: k
end
