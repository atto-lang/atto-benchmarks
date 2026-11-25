# JVM admission (not a benchmark)

On a machine authorized to access both private repositories, provision a clean checkout of atto-lang/atto-source.java at the compiler_audit commit in ../../upstream.lock.json. Use GraalVM JDK25, Maven and Python 3. Run:

    bash benchmark/web/sharkbench/adapters/jvm/run-transport.sh /path/to/atto-source.java

The script checks the compiler commit, complete root tree and clean checkout before and after building. It invokes the existing OresMain guest launcher with only the two loopback network scopes. No host substitute is selected. The test owns ports 5001 and 5002, launches the candidate, checks 32 concurrent successful requests, no upstream I/O for three invalid requests, upstream non-200/empty/oversize rejection, exact-limit acceptance, recovery, and exact 37 upstream requests. The source is a transport-only candidate and must not be used for measurement. No compiler source is checked into this repository. No cross-org token or export is authorized by this script.

## Evidence

Prior revision host-only control (before hardening): Python compiled the probe and exercised real loopback sockets against a Python control adapter (NOT Atto): 32 concurrent successes, 3 faults, 1 recovery, 36 upstream requests, PASS. Local transport_probe.py Git blob 641b228d4b9d821fdd567d9167169b250b1727af; verify against committed blob before relying on this receipt. Compiler launch and guest compilation NOT_EXECUTED: the local environment has JDK21, no Maven and no provisioned private compiler checkout. Prior benchmark Actions runs 45456522028 and 45474602731 completed without steps; NOT_EXECUTED, not test failures. A separate authorized runner is required; do not export private source without independent exact-tree authorization.

## JSON gate (canonical compiler integration)

Existing Java PRs #1118, #1124, #1125, #1126, #1133 and #1134 are the relevant ownership, parse, stringify and typed-decode stack. #1133 head 6fb8934ebd058f1d2e6891695e91c337dd637979; #1134 head a29651ec7d26d1aa0b947bc27f119852ec09e466. #1134 explicitly rejects Map decode in its checker/evaluator. #1787 validates JSON text, not full dynamic lookup. A complete solution must admit dynamic symbol keys through canonical JsonValue object lookup or checked Map<String, record{...}> and Map<String,List<int>> decoding, plus strict UTF-8 conversion from the bounded outbound body. Do not introduce a second JSON or host Map implementation. Verify exact-base integrated compiler stack with actual guest execution including malformed JSON, duplicate keys, arbitrary keys, missing keys, wrong types, quota, ownership and AOT negatives. Then implement both benchmark handlers and run check_contract.py and official upstream validation. No benchmark.yaml or Docker score adapter until these gates pass.


## Two-route guest candidate

`sharkbench-web.atto` is the initial all-Atto workload candidate. It requires an
integrated, independently verified compiler containing HTTP repairs (Java #1809),
strict UTF-8 (#1812) and allocator JSON guest bindings (#1814). Those branches are combined in Java integration PR #1816, but the resulting compiler tree is not yet execution-verified. Do not change the existing transport
lock to an arbitrary unverified candidate or publish a benchmark score.

The candidate uses fixed loopback upstream URLs, a 128 KiB streamed input limit,
explicit close in finally, strict UTF-8 after complete body assembly, dynamic
symbol lookup, scalar validation for element fields, bounded shell-array checks
and canonical JSON serialization. The listener binds loopback for local
admission. Docker packaging must separately review external listener scope.
Only canonical ASCII symbol query spelling is admitted in this candidate;
percent-encoded/ambiguous query forms are rejected. Error statuses and the
32-shell provisional bound are internal admission policy, not upstream score
claims. The integrated candidate now uses direct owned subtree copying with count-only canonical wire accounting; the previous 1 MiB snapshot budget and parser limits remain in force. Performance and compiler execution are unverified.

**NOT_EXECUTED:** guest source compilation, concurrent workload, negative HTTP
fixtures, cancellation/cleanup under load, AOT and official SharkBench scoring.

## Integrated admission candidate (not an approved compiler lock)

- Java integration PR: https://github.com/atto-lang/atto-source.java/pull/1816
- Candidate compiler head: `237b6c3c420c8834b6003f66674d172ec119bb7c`
- Candidate root tree: `6f718b331cdd0516e450fb30852fbc9f850d795e`
- The original pinned guest application and 72-request probe remain unchanged.
- Run the separate 23-case negative/recovery probe with `python3 -B benchmark/web/sharkbench/check_faults.py` after the positive probe exits, with the guest still running and port 5002 free. This is byte-identical to compiler fixture blob `7dd3671428f87aff533444b0e5a76e99b729c74c`.
- Direct-copy regression tests cover previous wire round-trip equivalence, immutable scalar reuse, independent container ownership, parser depth/token limits, escaped and multibyte wire quotas, and rejection of host numeric subclasses.
- No executed JDK25 guest results yet; no change to the accepted compiler lock, Docker or official score admission. Do not transfer compiler source across organizations without independent authorization.

## First executed compiler receipt and lifecycle candidate

The prior integration head `237b6c3c420c8834b6003f66674d172ec119bb7c` entered a JDK25 runner and failed javac before any guest test (runs 45522471358 and 45522471185). Two private helper declarations inside the sealed JSON interface were illegal. Java integration head `e75e57cad57ef4092c605d1447aea493b48e450c`, tree `4cb6ac371839a9de2e0efdea494afd2a12d43416`, relocates them to package-private implementation classes. Follow-up run: https://github.com/atto-lang/atto-source.java/actions/runs/45533865871 . This is not an approved compiler lock.

After both earlier probes pass and with port 5002 free, run `python3 -B benchmark/web/sharkbench/check_lifecycle.py` against the same live guest. It holds an upstream body open, requires the other route to make progress and the listener to return 504, abandons a second inbound client socket, then checks recovery and exact upstream counts. This is a provisional internal lifecycle policy, not official SharkBench behavior. The fixture releases blocked handlers in finally; socket-level success alone cannot prove actor/handle reclamation. Use NativeHttpTest and OutboundHttpRequestGuestTest for internal cleanup assertions. The lifecycle candidate has not been executed and is not yet wired into the compiler gate; keep the current compiler CI revision stable until its build result is known.

## Exact workload synchronization — 2026-11-25

The actor-local symbol validation candidate is synchronized to benchmark-owned source commit `d546d81dec7aaf209f619943d2368f9212c0b10f`, workload blob `85d33dae2ea2021fbfdf6e6e87311adb96e1ff28`, byte-identical to the fixture on Java #1816 head `7f2a97f35b1c5e2ec9bce2c6743103cae338373c`, compiler root tree `b237804b8fa5804e262ed4ec79b77d81459460d5`. The previous PR #5 spelling was semantically similar but a different blob; it could not inherit this fixture's evidence. The three correctness probe blobs also match the compiler fixture lock. No new compiler export is required.

Separate focused Java gates now executed successfully: [strict UTF-8 guest tests](https://github.com/atto-lang/atto-source.java/actions/runs/45518973442) and [canonical JSON runtime and linked guest tests](https://github.com/atto-lang/atto-source.java/actions/runs/45547521440). Component PRs #1812 and #1814 are merged. These receipts do not attest the combined application. [Integrated run 45660512640](https://github.com/atto-lang/atto-source.java/actions/runs/45660512640) was queued with no executed jobs at this checkpoint. Java #1816 is not mergeable against current main; its integration-specific changes need semantic forward-port after the candidate test results. No performance score, native image or approved compiler lock yet.

### Local integrated correctness entrypoint

On an authorized host with separate clean checkouts, run:

```sh
bash benchmark/web/sharkbench/adapters/jvm/run-admission.sh /path/to/atto-source.java 271015d6c1ab10132f5285c82db2aa56dd47928a 11fad1c5b370e5874401434873c978666ebf7018
```

This wrapper verifies the explicit compiler commit/root tree, both clean worktrees, and byte equality of all four workload/probe fixtures before delegating to the compiler's integrated runner. It rechecks identities afterward. The example pins a candidate, not an approved scoring compiler. Local wrapper-only tests (mock runner, no guest): valid identity and matching fixtures passed; wrong tree and committed fixture mismatch rejected. No timing or private source copying. Script blob `704007d9ab6ec2f04738d5818314254c725711c3`.

## Current-main integration checkpoint — 2026-11-25

Java #1816 now includes main `9a5d745b164c300ddffbad2f9cabe7b699f26b21` as a merge parent. Candidate commit `271015d6c1ab10132f5285c82db2aa56dd47928a`, tree `11fad1c5b370e5874401434873c978666ebf7018`, is zero commits behind that main snapshot. All 3,824 resulting file blobs were verified against the expected combined tree. The 19 changed paths retain main's evaluator/ownership updates and add only the audited integration-specific TypeChecker changes, JSON direct-copy candidate and tests/fixtures. The application blob remains `85d33dae2ea2021fbfdf6e6e87311adb96e1ff28`. The new compiler head has no visible Actions run yet; prior run 45660512640 remains queued and cannot certify this tree. The command above is a candidate correctness command, not an approved compiler lock. Do not publish throughput or merge on this source-level evidence alone.
