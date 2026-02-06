defmodule CoverageDiffTest do
  use ExUnit.Case
  doctest CoverageDiff

  test "greets the world" do
    assert CoverageDiff.hello() == :world
  end
end
