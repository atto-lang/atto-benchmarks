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

## Actor lexical-boundary repair

On compiler head `36141de7b71eb03f27a568e34878e2b7ea55fce6` the executed integration run 45546689635 passed 122 compiler/runtime tests, but the actual application launch was rejected because an actor implicitly called file-scope `valid_symbol`. The workload now performs the same bounded ASCII validation directly in its receive body. This preserves actor isolation and keeps input validation before upstream I/O. The NativeHttpTest suite independently timed out. Neither the full workload nor scoring is admitted yet. The previous receipts are historical and not a new approved compiler lock.

## Current exact-head CI and lifecycle self-tests

Java integration head `7f2a97f35b1c5e2ec9bce2c6743103cae338373c`, root tree `b237804b8fa5804e262ed4ec79b77d81459460d5`, is executing three independent gates in https://github.com/canonical-cloud-test/monorepo-submodules-e2e/actions/runs/45665595766 . Public repository metadata and anonymous access were independently checked on the runner before exact head/tree verification; no private source was stored in the carrier. This is a pending candidate, not an approved lock or official score. Previous 122 regression passes apply only to the earlier compiler tree. Native HTTP now requires all 24 invocations.

`test_lifecycle.py` adds separate host-only controls of the unchanged lifecycle probe: real stalled upstream and recovery, rejection of a canned response, rejection of incorrect timeout status. The Python control is explicitly not Atto execution. The compiler's active exact tree and pinned workload inputs are not changed by these self-tests.
