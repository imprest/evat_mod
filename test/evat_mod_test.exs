defmodule EvatModTest do
  use ExUnit.Case
  doctest EvatMod

  test "greets the world" do
    assert EvatMod.hello() == :world
  end
end
