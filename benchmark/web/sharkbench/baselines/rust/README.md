# Official upstream Rust/Axum reference candidate

The upstream pinned tree already contains a Rust Axum 0.8.9 / Rust 1.98.1 adapter. It fetches and deserializes the complete relevant mapping on each request, then selects and serializes the element or shell array. Use this official workload, not a new hand-written substitute. The upstream synthetic validation corpus differs from Atto's adversarial fixtures (e.g. Axum uses u8); do not claim equal malformed-input semantics.

On a dedicated Linux host, with local Docker, Cargo and a clean checkout of upstream commit `3e1d4b1c0dbe820da2f1cf4a620bf00be8ba2b3f`, run:

```sh
bash benchmark/web/sharkbench/baselines/rust/run.sh /path/to/sharkbench /path/to/new-results-dir
```

The wrapper verifies the exact upstream root tree, uses a disposable local clone, refuses stale CSV output, verifies exactly one task, runs official validation followed by the unchanged official timed command, and requires one fresh matching result row with zero reported errors. It preserves logs, raw CSV, host/toolchain inventory and SHA256 hashes. The upstream runner uses one container CPU, default concurrency 32, one warmup and five 15-second measured iterations. Use a fresh output directory per run, identical host/runtime configuration and repeat at least three times. Do not run Docker workloads on shared correctness CI.

**Limits:** upstream adapter Docker base tags and adapter Cargo dependencies are not fully digest/lock pinned; image inventory is diagnostic and is not proof of the exact transient builder or dependency graph. A captured row requires independent review, reproducible resolved image/dependency identities, equivalent Atto execution and host conditions before any public score or 70% comparison. Do not compare this to host microbenchmarks. No Rust/Docker run has occurred in this implementation wave. Local source-free validator tests: 11/11, including missing/duplicate rows, mismatched identity, nonzero errors and invalid measurements.
