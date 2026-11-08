defmodule A2aEngine.TestFixtures do
  @moduledoc """
  Shared test helpers — loads canonical JSON fixtures from `test/fixtures/`.
  """

  @fixtures_dir Path.expand("../fixtures", __DIR__)

  @doc "Load a fixture file (pass name without .json) and return it as a decoded map."
  @spec load(String.t()) :: map()
  def load(name) do
    @fixtures_dir
    |> Path.join(name <> ".json")
    |> File.read!()
    |> Jason.decode!()
  end

  @doc "List every fixture name (without extension) available on disk."
  @spec all() :: [String.t()]
  def all do
    @fixtures_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(&Path.rootname/1)
    |> Enum.sort()
  end
end
