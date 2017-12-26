defmodule AmyqpTest do
  use ExUnit.Case
  doctest Amyqp

  test "greets the world" do
    assert Amyqp.hello() == :world
  end
end
