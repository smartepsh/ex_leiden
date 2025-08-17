# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ExLeiden is a pure Elixir implementation of the Leiden algorithm for community detection in networks. The Leiden algorithm improves upon the Louvain method by addressing resolution limits and ensuring well-connected communities, supporting both modularity and CPM quality functions.

## Development Commands

### Building and Dependencies
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `mix deps.compile` - Compile dependencies

### Testing
- `mix test` - Run all tests
- `mix test test/specific_test.exs` - Run a specific test file
- `mix test --cover` - Run tests with coverage report
- `mix test --export-coverage default` - Export coverage data for analysis
- Coverage minimum requirement: 90% (configured in coveralls.json)

### Code Quality
- `mix format` - Format code according to Elixir standards
- `mix format --check-formatted` - Check if code is properly formatted
- `mix dialyzer` - Run static analysis with Dialyzer (requires initial setup with `mix dialyzer --plt`)
- `mix deps.audit` - Security audit of dependencies
- `mix deps.unlock --check-unused` - Check for unused dependencies

### Documentation
- `mix docs` - Generate documentation (outputs to `doc/`)
- Documentation is configured to include README.md and CHANGELOG.md

## Architecture

This is currently a minimal Elixir OTP application with the following structure:

### Core Modules (Planned)
Based on the documentation configuration in mix.exs, the planned architecture includes:

**Core Algorithm**
- `ExLeiden` - Main module interface
- `ExLeiden.Algorithm` - Core Leiden algorithm implementation

**Quality Functions**
- `ExLeiden.Quality` - Quality function interface
- `ExLeiden.Quality.Modularity` - Modularity quality function
- `ExLeiden.Quality.CPM` - Constant Potts Model quality function

**Graph Utilities**
- `ExLeiden.GraphUtils` - Graph manipulation utilities

**Caching System**
- `ExLeiden.Cache` - Cache interface
- `ExLeiden.Cache.ETS` - ETS-based caching
- `ExLeiden.Cache.Manager` - Cache management

**Utilities**
- `ExLeiden.Utils` - General utilities

### Dependencies
- `libgraph` (~> 0.16) - Core graph data structure library
- `ex_doc` (dev) - Documentation generation
- `dialyxir` (dev) - Static analysis tool
- `mix_audit` (dev/test) - Security auditing
- `excoveralls` (test) - Test coverage analysis

### Current State
The project is in early development with minimal implementation. The main ExLeiden module has a comprehensive API design with detailed type specifications and documentation, but the actual algorithm implementation is not yet complete. The application structure is set up as an OTP application with supervisor.

### Code Quality Standards
- Minimum test coverage: 90%
- Dialyzer PLT files cached in `priv/plts/`