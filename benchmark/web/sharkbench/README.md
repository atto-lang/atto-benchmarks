# SharkBench Web integration

Status: correctness harness only. No compiled Atto server, Docker image, or timed result yet.

## Workload

Implement two GET routes at 0.0.0.0:5001:

- /api/v1/periodic-table/element?symbol=He -> {"name":"Helium","number":2,"group":18}
- /api/v1/periodic-table/shells?symbol=He -> {"shells":[2]}

On every request, fetch http://127.0.0.1:5002/element.json or /shells.json respectively, deserialize the complete relevant mapping, select the requested symbol, and serialize the result. The shells mapping contains arrays; the returned JSON wraps the selected array under the shells key. Both routes must run concurrently. Use the official upstream source for timed runs. The test source below deliberately changes its data and is never a measurement source.

## Correctness probe

Start the compiled application on port 5001, with no other process listening on port 5002. Run from the repository root:

    python3 benchmark/web/sharkbench/check_contract.py

The probe starts a local synthetic data source, issues 72 mixed concurrent requests over two phases (32 then 40), verifies exact JSON values and content type, and checks one upstream request per application request. A changed Unicode sentinel and synthetic symbol Xx introduced only in phase two reject stale/canned data and fixed symbol tables. These deliberately nonphysical fixtures are not official benchmark inputs. Strict output decoding rejects malformed UTF-8, lone surrogates, duplicate object keys and nonfinite numbers. The test assumes lazy request-time fetching and no unrelated upstream traffic; start the server without a startup fetch. Probe success is necessary but not sufficient for benchmark admission. Add tests for missing/unknown symbols, non-200 upstream responses, malformed upstream JSON, timeouts, concurrency and cancellation with bounded queues and resource cleanup. Error response semantics are an internal policy until upstream rules are checked.

## Implementation sequence

1. Pin upstream SharkBench commit and inspect its runner, symbol corpus, warmup, concurrency, validation and Docker conventions. Record the commit in a lock file.
2. Inventory working Atto HTTP server/client, JSON, async task and build APIs from exact compiler/library revisions. Use a single shared .atto workload where supported. Keep platform adapters minimal and separately disclosed.
3. Implement JVM variant; verify compiled guest handler performs parsing, network I/O orchestration, lookup and serialization. Prove exact source/build tree and run the probe plus negative tests.
4. Add .NET JIT/NativeAOT and LLVM variants; then GraalVM native, Forge/Cranelift and supported Wasm/JS modes. Mark unavailable capabilities explicitly; do not substitute host-only benchmark code.
5. Add upstream-style benchmark.yaml, Dockerfile and pinned build inputs for each validated variant. Ensure listener port 5001 and host-network data source port 5002. Keep upstream CPU quota and runner parameters unchanged for official-style comparisons.
6. On a controlled Linux benchmark host run official SharkBench with `cargo run --release -- --web --lang atto` after placing valid adapters in the pinned upstream checkout; confirm discovery first. Run peer baselines on the same host and repeat trials. Archive all raw measurements and manifest.
7. Prepare upstream contribution only when eligibility and reproducible builds are established. The upstream project generally expects active maintenance, at least three months of history and evidence of production use. Private source/dependency access is a submission blocker unless resolved.

## Suggested internal tracks

- JVM and GraalVM JIT/native: separate rows
- .NET JIT and NativeAOT: separate rows
- LLVM and Forge/Cranelift: separate rows
- Wasm/JS server runtimes: separate rows only where equivalent server/client behavior is supported
- Structured tasks versus actor-based request execution: separate experimental rows, same workload

## Measurement receipt

Record upstream harness commit, application/compiler/library commit and tree SHAs, image digest, exact commands, CPU model and quota, OS/kernel, memory limit, runtime configuration, trial/warmup parameters, raw responses and errors, throughput, p50/p99 latency, stability metric as defined upstream, memory and build duration. Keep CI correctness separate from dedicated-host scores; reject zero-step jobs and mismatched trees. No public ranking claims before comparable verified measurements.

## Planned layout

- shared/ — actual .atto request handlers
- adapters/ — runtime-specific packaging, Dockerfiles and benchmark.yaml
- tests/ — negative and integration tests
- results/ — manifests and raw results, not placeholders
- check_contract.py — initial correctness-only probe

References: https://sharkbench.dev/web and https://github.com/sharkbench/sharkbench (Apache-2.0 upstream; retain notices if copying upstream code).

The [upstream Rust/Axum baseline entrypoint](baselines/rust/README.md) prepares fresh candidate receipts on a dedicated host. No comparative score yet.
