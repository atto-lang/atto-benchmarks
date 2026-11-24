# JVM admission (not a benchmark)

On a machine authorized to access both private repositories, provision a clean checkout of atto-lang/atto-source.java at the compiler_audit commit in ../../upstream.lock.json. Use GraalVM JDK25, Maven and Python 3. Run:

    bash benchmark/web/sharkbench/adapters/jvm/run-transport.sh /path/to/atto-source.java

The script checks the compiler commit, complete root tree and clean checkout before and after building. It invokes the existing OresMain guest launcher with only the two loopback network scopes. No host substitute is selected. The test owns ports 5001 and 5002, launches the candidate, checks 32 concurrent successful requests, no upstream I/O for two invalid requests, upstream non-200/empty/oversize rejection, recovery, and exact 36 upstream requests. The source is a transport-only candidate and must not be used for measurement. No compiler source is checked into this repository. No cross-org token or export is authorized by this script.

## Evidence

Local host-only control: Python compiled the probe and exercised real loopback sockets against a Python control adapter (NOT Atto): 32 concurrent successes, 3 faults, 1 recovery, 36 upstream requests, PASS. Local transport_probe.py Git blob 641b228d4b9d821fdd567d9167169b250b1727af; verify against committed blob before relying on this receipt. Compiler launch and guest compilation NOT_EXECUTED: the local environment has JDK21, no Maven and no provisioned private compiler checkout. Prior benchmark Actions runs 45456522028 and 45474602731 completed without steps; NOT_EXECUTED, not test failures. A separate authorized runner is required; do not export private source without independent exact-tree authorization.

## JSON gate (canonical compiler integration)

Existing Java PRs #1118, #1124, #1125, #1126, #1133 and #1134 are the relevant ownership, parse, stringify and typed-decode stack. #1133 head 6fb8934ebd058f1d2e6891695e91c337dd637979; #1134 head a29651ec7d26d1aa0b947bc27f119852ec09e466. #1134 explicitly rejects Map decode in its checker/evaluator. #1787 validates JSON text, not full dynamic lookup. A complete solution must admit dynamic symbol keys through canonical JsonValue object lookup or checked Map<String, record{...}> and Map<String,List<int>> decoding, plus strict UTF-8 conversion from the bounded outbound body. Do not introduce a second JSON or host Map implementation. Verify exact-base integrated compiler stack with actual guest execution including malformed JSON, duplicate keys, arbitrary keys, missing keys, wrong types, quota, ownership and AOT negatives. Then implement both benchmark handlers and run check_contract.py and official upstream validation. No benchmark.yaml or Docker score adapter until these gates pass.
