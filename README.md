# ExLeiden

[![Hex.pm Version](https://img.shields.io/hexpm/v/ex_leiden.svg)](https://hex.pm/packages/ex_leiden) [![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_leiden/)

A pure Elixir implementation of the Leiden algorithm for community detection in networks.

The Leiden algorithm improves upon the Louvain method by addressing the resolution limit problem and ensuring communities that are well-connected internally.

> **Note:** This is a work-in-progress implementation. The core algorithm structure is complete, but the API and result format may change before v1.0.

> **Note:** For the best reading experience with properly rendered mathematical formulas, view this README on [GitHub](https://github.com/smartepsh/ex_leiden#readme).

## Installation

Add `ex_leiden` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_leiden, "~> 0.1"}
  ]
end
```

## Leiden Algorithm Overview

The Leiden algorithm consists of three main phases:

1. **Local moving phase** - Moves nodes between communities to optimize the quality function
2. **Refinement phase** - Splits disconnected communities to ensure well-connected communities
3. **Aggregation phase** - Creates aggregate networks for the next iteration

This approach guarantees well-connected communities and addresses the resolution limit problem found in the Louvain method.

**References: From Louvain to Leiden: guaranteeing well-connected communities**

- [arXiv](https://arxiv.org/abs/1810.08473)
- [DOI](https://doi.org/10.1038/s41598-019-41695-z)

### Quality Functions

ExLeiden supports two quality functions for community detection:

#### Modularity
$$H = \frac{1}{2m} \sum_c \left( e_c - \gamma \frac{K_c^2}{2m} \right)$$

#### Constant Potts Model (CPM)
$$H = \sum_c \left( e_c - \gamma \binom{n_c}{2} \right)$$

**Where:**
- $e_c$ = actual number of edges in community $c$
- $K_c$ = sum of the degrees of the nodes in community $c$
- $m$ = total number of edges in the network
- $\gamma$ = resolution parameter (γ > 0)
- $n_c$ = number of nodes in community $c$

## Usage

ExLeiden accepts graphs in multiple formats and converts them internally to adjacency matrices for efficient computation.

```elixir
# From edge list (unweighted)
edges = [{1, 2}, {2, 3}, {3, 1}]
{:ok, result} = ExLeiden.call(edges)

# From edge list (weighted)
weighted_edges = [{:a, :b, 0.5}, {:b, :c, 1.2}, {:c, :a, 0.8}]
{:ok, result} = ExLeiden.call(weighted_edges)

# From explicit vertices and edges
vertices = ["alice", "bob", "carol"]
edges = [{"alice", "bob"}, {"bob", "carol"}]
{:ok, result} = ExLeiden.call({vertices, edges})

# From adjacency matrix (2D list)
matrix = [
  [0, 1, 1],
  [1, 0, 1],
  [1, 1, 0]
]
{:ok, result} = ExLeiden.call(matrix)

# From Nx tensor adjacency matrix
tensor = Nx.tensor([[0, 1, 0], [1, 0, 1], [0, 1, 0]])
{:ok, result} = ExLeiden.call(tensor)

# From libgraph Graph struct
graph = Graph.new()
        |> Graph.add_vertices([1, 2, 3])
        |> Graph.add_edges([{1, 2}, {2, 3}])
{:ok, result} = ExLeiden.call(graph)

# With options
{:ok, result} = ExLeiden.call(edges, [
  resolution: 1.5,
  quality_function: :cpm,
  community_size_threshold: 10  # Stop when communities ≤ 10 nodes
])
```

### Options

The algorithm behavior can be customized using various options:

- `:quality_function` - Quality function to optimize (`:modularity` or `:cpm`, default: `:modularity`)
  - `:modularity` - See [Modularity](#modularity) section for mathematical details
  - `:cpm` - See [Constant Potts Model (CPM)](#constant-potts-model-cpm) section for mathematical details

- `:resolution` - Resolution parameter γ controlling community granularity (default: 1.0)
  - Higher values (> 1.0) favor smaller, tighter communities
  - Lower values (< 1.0) favor larger, looser communities
  - Higher γ → smaller communities
  - Lower γ → larger communities

- `:max_level` - Maximum hierarchical levels to create (default: 5)
  - Controls depth of community hierarchy
  - Higher values allow more fine-grained community structure
  - Algorithm may stop early if no further improvements can be made, even before reaching max_level

- `:community_size_threshold` - Minimum community size threshold for termination (default: `nil`)
  - When set to an integer, algorithm terminates if all communities are at or below this size
  - Takes precedence over `:max_level` when both are set
  - Useful for stopping early when communities reach desired granularity
  - Set to `nil` to disable (algorithm uses `:max_level` instead)

## Result Format

Returns a map with integer keys (hierarchical levels) and values containing communities and bridges:

```elixir
%{
  1 => %{
    communities: [
      %{id: 0, children: [1, 2, 3]},    # Community 0 contains nodes [1, 2, 3]
      %{id: 1, children: [4, 5]},       # Community 1 contains nodes [4, 5]
      %{id: 2, children: [6, 7, 8]}     # Community 2 contains nodes [6, 7, 8]
    ],
    bridges: [
      {0, 1, 0.5},    # Bridge between community 0 and 1 with weight 0.5
      {1, 2, 0.3}     # Bridge between community 1 and 2 with weight 0.3
    ]
  },
  2 => %{
    communities: [
      %{id: 0, children: [0, 1]},       # Level 2 community contains level 1 communities 0 and 1
      %{id: 1, children: [2]}           # Level 2 community contains level 1 community 2
    ],
    bridges: [
      {0, 1, 0.2}     # Bridge between level 2 communities
    ]
  }
}
```

### Structure Details

- **Level Keys**: Integer keys represent hierarchical levels (1, 2, 3, ...)
- **Communities**: List of community assignments with:
  - `id`: Community identifier within the level
  - `children`: List of node indices (level 1) or community IDs (higher levels)
- **Bridges**: List of inter-community connections as `{community_a, community_b, weight}` tuples

## Error Handling

The only source of errors is option validation. The Leiden algorithm itself cannot fail - it always produces a valid community detection result. Invalid options return `{:error, reason}` tuples:

```elixir
# Invalid options - returns map of option -> reason
{:error, %{
  resolution: "must be a positive number",
  quality_function: "must be :modularity or :cpm"
}}
```

## Implementation Status

### ✅ Completed Features

- **Core Algorithm**: All three phases of the Leiden algorithm are fully implemented
  - **Local Moving Phase**: Queue-based node processing with matrix-optimized delta calculations
  - **Refinement Phase**: Well-connected community splitting with γ-connectivity validation
  - **Aggregation Phase**: Hierarchical community network construction
- **Quality Functions**: Both main quality functions are fully implemented
  - **Modularity**: Complete vectorized implementation with resolution parameter support
  - **Constant Potts Model (CPM)**: Complete implementation with linear penalty calculation

### 🚧 TODOs

- [ ] **Iteration Implementation**: Replace memory-intensive matrix operations with streaming approaches
  - [ ] **Memory-efficient Data Structures**: Use sparse representations and lazy evaluation for large networks
  - [ ] **Flow Parallel Processing**: Implement GenStage/Flow pipelines for parallel node processing
- [ ] **Performance Optimizations**: Additional optimizations for large graphs
  - [ ] Memory usage optimization for very large networks
  - [ ] Parallel processing for independent community refinement
- [ ] **Benchmarking Suite**: Implement comprehensive performance benchmarks
  - [ ] Network size scalability tests (100 to 100,000+ nodes)
  - [ ] Comparison with reference implementations
