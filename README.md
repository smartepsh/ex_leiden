# ExLeiden

[![Hex.pm Version](https://img.shields.io/hexpm/v/ex_leiden.svg)](https://hex.pm/packages/ex_leiden) [![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_leiden/)

A pure Elixir implementation of the Leiden algorithm for community detection in networks.

The Leiden algorithm improves upon the Louvain method by addressing the resolution limit problem and ensuring communities that are well-connected internally.

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

ExLeiden will support two quality functions for community detection:

#### Modularity (Planned)
$$H = \frac{1}{2m} \sum_c \left( e_c - \gamma \frac{K_c^2}{2m} \right)$$

#### Constant Potts Model (CPM) (Planned)
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
  format: :communities_and_bridges
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

- `:format` - Result format (`:communities_and_bridges` or `:graph`, default: `:communities_and_bridges`)
  - `:communities_and_bridges` - Returns communities and bridges between them
  - `:graph` - Returns Graph structs for continued graph operations

## Result Formats

The algorithm can return results in two different formats, controlled by the `:format` option:

### `:communities_and_bridges` Format (Default)

Returns a map with integer keys (hierarchical levels) and values containing communities and bridges:

```elixir
%{
  0 => %{
    communities: %{
      {0, 0} => [1, 2, 3],      # Community {0, 0} contains original vertices [1, 2, 3]
      {0, 1} => [4, 5],         # Community {0, 1} contains original vertices [4, 5]
      {0, 2} => [6, 7, 8]       # Community {0, 2} contains original vertices [6, 7, 8]
    },
    bridges: [
      {{0, 0}, {0, 1}, 0.5},    # Bridge between communities {0, 0} and {0, 1} with weight 0.5
      {{0, 1}, {0, 2}, 0.3}     # Bridge between communities {0, 1} and {0, 2} with weight 0.3
    ]
  },
  1 => %{
    communities: %{
      {1, 0} => [{0, 0}, {0, 1}], # Level 1 community containing level 0 communities
      {1, 1} => [{0, 2}]          # Level 1 community containing level 0 community
    },
    bridges: [
      {{1, 0}, {1, 1}, 0.2}     # Bridge between level 1 communities
    ]
  }
}
```

### `:graph` Format

Returns a map with integer keys (hierarchical levels) and `Graph.t()` struct values:

```elixir
%{
  0 => #Graph<vertices: [1, 2, 3, {0, 0}, {0, 1}, {0, 2}], edges: [...], ...>,
  1 => #Graph<vertices: [{0, 0}, {0, 1}, {0, 2}, {1, 0}, {1, 1}], edges: [...], ...>
}
```

This format is useful when you need to perform additional graph operations using the `libgraph` library.

### Community IDs

Community IDs are represented as `{level, index}` tuples:

- `level` - The hierarchical level (0 = original vertices + level 0 communities, 1 = level 1 communities, etc.)
- `index` - The community index within that level (0, 1, 2, ...)

Examples:
- `{0, 0}` - First community at level 0
- `{0, 1}` - Second community at level 0
- `{1, 0}` - First community at level 1 (contains level 0 communities)

## Error Handling

The only source of errors is option validation. The Leiden algorithm itself cannot fail - it always produces a valid community detection result. Invalid options return `{:error, reason}` tuples:

```elixir
# Invalid options - returns map of option -> reason
{:error, %{
  resolution: "must be a positive number",
  quality_function: "must be :modularity or :cpm"
}}
```

## TODOs

- [ ] **Vectorized Tensor Operations**: Implement fully vectorized matrix operations throughout the algorithm for significant performance improvements
- [ ] **Quality Function Implementations**: Implement the two main quality functions for community detection
  - [ ] **Modularity**
  - [ ] **Constant Potts Model (CPM)**
- [ ] **Benchmarking Suite**: Implement comprehensive performance benchmarks
  - [ ] Network size scalability tests (100 to 100,000+ nodes)
  - [ ] GPU vs CPU performance comparisons
