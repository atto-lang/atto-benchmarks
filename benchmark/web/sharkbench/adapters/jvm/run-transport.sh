#!/usr/bin/env bash
# Run only on an authorized machine with a separately provisioned private compiler checkout.
set -euo pipefail
if [[ $# != 1 ]]; then
  echo "usage: bash run-transport.sh /path/to/atto-source.java" >&2
  exit 64
fi
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
compiler="$(cd "$1" && pwd -P)"
read -r expected tree < <(python3 - "$here/../../upstream.lock.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))["compiler_audit"]
print(p["commit"], p["tree"])
PY
)
test "$(git -C "$compiler" rev-parse HEAD)" = "$expected"
test "$(git -C "$compiler" rev-parse HEAD^{tree})" = "$tree"
test -z "$(git -C "$compiler" status --porcelain --untracked-files=all)"
echo "COMPILER_SHA=$expected COMPILER_TREE=$tree"
java -version
mvn -version
(
  cd "$compiler"
  mvn -B -ntp clean compile dependency:build-classpath -Dmdep.outputFile=target/sharkbench-classpath.txt
)
test -z "$(git -C "$compiler" status --porcelain --untracked-files=all)"
test -s "$compiler/target/sharkbench-classpath.txt"
classpath="$(cat "$compiler/target/sharkbench-classpath.txt")"
python3 "$here/transport_probe.py" -- java -cp "$compiler/target/classes:$classpath" \
  dev.oreslang.launcher.OresMain --no-core-log --permission-check=runtime \
  --allow-net=127.0.0.1:5001,127.0.0.1:5002 "$here/transport-smoke.atto"
