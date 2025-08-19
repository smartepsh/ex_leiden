defmodule ExLeiden.QualityTest do
  use ExUnit.Case, async: true
  
  alias ExLeiden.Quality

  describe "modularity/3" do
    test "calculates modularity for simple triangle network" do
      # Triangle network
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      # All nodes in same community
      communities = [0, 0, 0]
      modularity = Quality.modularity(matrix, communities, 1.0)
      
      # For a triangle where all nodes are in same community
      # modularity should be negative (random network would have 0)
      assert modularity < 0
      assert is_float(modularity)
    end

    test "calculates modularity for two community network" do
      # Two separate triangles connected by one edge
      matrix = Nx.tensor([
        [0, 1, 1, 0, 0, 0],
        [1, 0, 1, 1, 0, 0], 
        [1, 1, 0, 0, 0, 0],
        [0, 1, 0, 0, 1, 1],
        [0, 0, 0, 1, 0, 1],
        [0, 0, 0, 1, 1, 0]
      ])
      
      # Two communities: [0,1,2] and [3,4,5]
      communities = [0, 0, 0, 1, 1, 1]
      modularity = Quality.modularity(matrix, communities, 1.0)
      
      # This should have positive modularity (good community structure)
      assert modularity > 0
      assert is_float(modularity)
    end

    test "handles empty communities gracefully" do
      matrix = Nx.tensor([[0, 1], [1, 0]])
      communities = [0, 1]
      
      modularity = Quality.modularity(matrix, communities, 1.0)
      assert is_float(modularity)
    end

    test "respects gamma parameter" do
      matrix = Nx.tensor([
        [0, 1, 0],
        [1, 0, 1], 
        [0, 1, 0]
      ])
      
      communities = [0, 0, 1]
      
      mod_low = Quality.modularity(matrix, communities, 0.5)
      mod_high = Quality.modularity(matrix, communities, 2.0)
      
      # Higher gamma should give different (typically lower) modularity
      assert mod_low != mod_high
    end
  end

  describe "cpm/3" do
    test "calculates CPM for simple network" do
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      # All nodes in same community
      communities = [0, 0, 0]
      cpm = Quality.cpm(matrix, communities, 1.0)
      
      assert is_float(cpm)
    end

    test "handles different community sizes" do
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      # Two communities of size 2 each
      communities = [0, 0, 1, 1]
      cpm = Quality.cpm(matrix, communities, 1.0)
      
      assert is_float(cmp)
    end

    test "handles singleton communities" do
      matrix = Nx.tensor([
        [0, 1, 0],
        [1, 0, 1],
        [0, 1, 0]
      ])
      
      # Each node in its own community
      communities = [0, 1, 2]
      cpm = Quality.cpm(matrix, communities, 1.0)
      
      # Singleton communities should have 0 CPM contribution
      assert cpm == 0.0
    end
  end

  describe "quality_gain/7" do
    test "calculates modularity gain correctly" do
      matrix = Nx.tensor([
        [0, 1, 1, 0],
        [1, 0, 1, 1],
        [1, 1, 0, 0],
        [0, 1, 0, 0]
      ])
      
      communities = [0, 0, 0, 1]
      
      # Calculate gain for moving node 3 from community 1 to community 0
      gain = Quality.quality_gain(:modularity, matrix, communities, 3, 1, 0, 1.0)
      
      assert is_float(gain)
    end

    test "calculates CPM gain correctly" do
      matrix = Nx.tensor([
        [0, 1, 1, 0],
        [1, 0, 1, 1],
        [1, 1, 0, 0],
        [0, 1, 0, 0]
      ])
      
      communities = [0, 0, 0, 1]
      
      # Calculate gain for moving node 3 from community 1 to community 0
      gain = Quality.quality_gain(:cpm, matrix, communities, 3, 1, 0, 1.0)
      
      assert is_float(gain)
    end

    test "returns zero gain for same community move" do
      matrix = Nx.tensor([[0, 1], [1, 0]])
      communities = [0, 1]
      
      gain = Quality.quality_gain(:modularity, matrix, communities, 0, 0, 0, 1.0)
      assert gain == 0.0
    end

    test "handles invalid quality function" do
      matrix = Nx.tensor([[0, 1], [1, 0]])
      communities = [0, 1]
      
      assert_raise FunctionClauseError, fn ->
        Quality.quality_gain(:invalid, matrix, communities, 0, 0, 1, 1.0)
      end
    end
  end

  describe "edge cases" do
    test "handles single node network" do
      matrix = Nx.tensor([[0]])
      communities = [0]
      
      modularity = Quality.modularity(matrix, communities, 1.0)
      cpm = Quality.cpm(matrix, communities, 1.0)
      
      assert modularity == 0.0
      assert cpm == 0.0
    end

    test "handles disconnected network" do
      matrix = Nx.tensor([
        [0, 0, 0],
        [0, 0, 0],
        [0, 0, 0]
      ])
      
      communities = [0, 1, 2]
      
      modularity = Quality.modularity(matrix, communities, 1.0)
      cpm = Quality.cpm(matrix, communities, 1.0)
      
      assert modularity == 0.0
      assert cpm == 0.0
    end

    test "handles weighted networks" do
      matrix = Nx.tensor([
        [0, 2, 3],
        [2, 0, 1], 
        [3, 1, 0]
      ])
      
      communities = [0, 0, 1]
      
      modularity = Quality.modularity(matrix, communities, 1.0)
      cpm = Quality.cpm(matrix, communities, 1.0)
      
      assert is_float(modularity)
      assert is_float(cpm)
    end
  end
end