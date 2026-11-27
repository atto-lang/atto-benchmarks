# Actor messaging benchmark contract (v1)

This is a correctness-first result validator, not an implemented actor workload or a published comparison.

## Workloads to implement

| ID | Workload | What must be proven before timing |
| --- | --- | --- |
| M01 | Closed-loop ping-pong | Exactly one typed reply per sequence ID |
| M02 | Open-loop fan-in | Bounded admission, per-ID settlement, explicit rejection |
| M03 | Many-to-many | Per-sender ordering where promised; no duplicate completion |
| M04 | USER saturation with CONTROL and timer activity | Supervisor notices and unrelated timers progress; bounded USER backlog |
| M05 | Owned payload transfer (4 KiB and 1 MiB) | Payload integrity, ownership retained on rejection; measure copies separately |
| M06 | Mixed socket I/O and CPU actors | Real loopback I/O, bounded ready queues, unrelated work progresses |

Initial adapters: actual compiled Atto guest, Akka Typed, Vert.x EventBus, Apache Pekko and Erlang/OTP. Use equivalent delivery semantics; Vert.x verticles are not claimed to be full actors. No host-only Atto substitution. Run local and remote messaging as different workloads.

## Trial format

Run warm-up separately. Start the monotonic clock before first offered message; stop after all accepted messages settle. Each offered message ID is unique. Completion latency is measured from scheduled offer time (including generator delay), not dequeue time. Record every completion latency outside the timed hot path where possible; apply identical measurement policy to all adapters. No retries in v1. Admission is counted once per message; rejected is explicit and never counted as throughput. The trial must finish drained.

JSON fields: implementation, runtime_mode, workload, hardware_id, run_id, source_commit, harness_commit, correctness_passed, offered, accepted, rejected, completed, failed, elapsed_ns, queue_capacity, peak_queue_depth, duplicate_completions, pending_at_end, completion_latency_ns. All counts and nanoseconds are integers. Both commits are full SHA-1 Git IDs. Queue capacity and observed peak must refer to the same measured queue domain; use a single bounded mailbox for the initial adapter. Unbounded, unsupported and unmeasured modes are not eligible for this validator.

Run `python3 actor-messaging/validate.py trial.json` or `python3 actor-messaging/validate.py --self-test`. Throughput is completed messages per second over the entire timed interval; rejection is reported independently. Percentiles use nearest rank. Zero failures are required for this ordinary success workload; failure-injection tests need a separate contract.

## Qualification limits

The validator checks internal consistency only. It cannot authenticate adapter counters, source identity, unique message IDs, queue instrumentation, actual guest execution or hardware. Require independent correctness fixtures and exact source/build receipts. Keep raw trials; record CPU topology, affinity, OS, versions, compiler flags, memory, allocation/copy counters, payload, offered rate, warm-up, repeat count and configuration separately. Use controlled hardware and at least five repetitions per comparable configuration. Never compare closed-loop rates to open-loop rates or compare different rejection rates as if identical. For M04/M06 record supervisor/timer/I/O latencies separately; no claim of a hard real-time bound from a hosted CI run.

Tracks [shared runtime acceptance #659](https://github.com/atto-lang/atto-platform-conformance/issues/659). No measured performance results yet.
