# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- [XLA] use `defn` and `defnp` to rewrite pure numeric functions. It will support accelerated by cpu SIMD or GPU.

## 0.3.1 - 2025-10-09

### Fixed

- [Source] fix empty edge list handling - now correctly creates adjacency matrix with all orphan vertices instead of failing with `Nx.tensor/1` error
- [Source] fix empty kept_index handling in `remove_orphans/2` - now returns original matrix instead of attempting to create invalid 0x0 tensor

## 0.3.0 - 2025-09-17

### Added

- [Behaviour] add entrypoint behaviour module, to make user can easily setup mock to test.

### Changed

- [Result] update format from map `%{communities: [community], bridges: [birdge]}` to tuple `{[community], [bridge]}`.

## 0.2.0 - 2025-09-12

### Added

- [Option] add `community_size_threshold` option for algorithm termination control. When set, the algorithm terminates if all communities are at or below the specified size threshold. Takes precedence over `max_level` when both are set.

## 0.1.0 - 2025-09-11

### Added

- [Option] add `validate_opts/2` for cast and validate options.
- [Source] add `build!/1` for converting various graph input formats to standardized `t:Source.t()` representation.
- [ExLeiden] add `ExLeiden.call/2`, we complete Leiden algorithm implementation with support for modularity and CPM quality functions
