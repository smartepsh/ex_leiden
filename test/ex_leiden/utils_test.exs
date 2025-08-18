defmodule ExLeiden.UtilsTest do
  use ExUnit.Case, async: true

  alias ExLeiden.Utils

  describe "take_by_indices/2" do
    test "takes elements at specified indices from list" do
      list = [:a, :b, :c, :d, :e]
      indices = [0, 2, 4]

      assert Utils.take_by_indices(list, indices) == [:a, :c, :e]
    end

    test "handles empty indices list" do
      list = [:a, :b, :c]
      indices = []

      assert Utils.take_by_indices(list, indices) == []
    end

    test "handles empty list" do
      list = []
      indices = [0, 1]

      assert Utils.take_by_indices(list, indices) == []
    end

    test "handles indices out of range" do
      list = [:a, :b]
      indices = [0, 5, 1]

      assert Utils.take_by_indices(list, indices) == [:a, :b]
    end

    test "handles duplicate indices" do
      list = [:a, :b, :c]
      indices = [1, 1, 0, 1]

      assert Utils.take_by_indices(list, indices) == [:a, :b]
    end

    test "works with different data types" do
      list = [1, "two", :three, %{four: 4}]
      indices = [0, 3, 1]

      assert Utils.take_by_indices(list, indices) == [1, "two", %{four: 4}]
    end

    test "maintains order of indices" do
      list = [:a, :b, :c, :d, :e]
      indices = [4, 1, 3, 0]

      assert Utils.take_by_indices(list, indices) == [:a, :b, :d, :e]
    end
  end
end
