# AttoLang Benchmarks

Reproducible, correctness-first performance benchmarks for AttoLang compiler backends and runtime libraries.

## First workload: SharkBench Web

See [SharkBench](https://sharkbench.dev/web) and [upstream source](https://github.com/sharkbench/sharkbench). The first integration will implement the periodic-table HTTP workload in actual compiled .atto code. The upstream harness, not a custom load generator, is authoritative for comparable scores.

Proposed implementation order: Java/GraalVM JVM, .NET JIT and NativeAOT, LLVM native, Forge/Cranelift, then supported Wasm/JS server environments. Each mode is a distinct result; unsupported modes remain blocked, not simulated by host code.

## Evidence policy

- Pin the upstream harness commit, compiler commit/tree, application commit, dependencies and image digest.
- Verify output correctness, real per-request upstream HTTP I/O, JSON decoding and encoding, concurrency, and failure behavior before any timed run.
- Use identical hardware, resource limits and upstream parameters for comparisons; report requests/s, median and p99 latency, memory and build time, with raw results and repeat runs.
- No host-only substitute, canned responses, caching away workload I/O or fabricated results. Label host bridges and runtime modes accurately.
- A green job without executed steps is not evidence. Hosted CI is for correctness; performance claims require a controlled benchmark machine.

## Status

Project initialized; no verified Atto performance results. See the SharkBench workstream PR for the contract-checking scaffold and implementation plan.
