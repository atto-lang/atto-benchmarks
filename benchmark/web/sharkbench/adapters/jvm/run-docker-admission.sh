#!/usr/bin/env bash
# Executes real container guest; never an official benchmark score.
set -euo pipefail
[[ $# == 1 ]] || { echo "usage: $0 /path/to/exact/compiler" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
suite="$(cd "$here/../.." && pwd)"
compiler="$(cd "$1" && pwd)"
stage="$(mktemp -d)"
name="atto-sharkbench-admission-$$"
cleanup() {
  docker logs "$name" 2>&1 | tail -c 16000 || true
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker image rm "$name" >/dev/null 2>&1 || true
  rm -rf -- "$stage"
}
trap cleanup EXIT
python3 - "$here/jvm-admission.lock.json" "$compiler" "$suite" <<'PY'
import json, pathlib, subprocess, sys
lock=json.load(open(sys.argv[1]))
root=pathlib.Path(sys.argv[2])
suite=pathlib.Path(sys.argv[3])
def git(*args):
    return subprocess.check_output(["git","-C",str(root),*args],text=True).strip()
assert git("rev-parse","HEAD")==lock["compiler"]["commit"]
assert git("rev-parse","HEAD^{tree}")==lock["compiler"]["tree"]
assert git("status","--porcelain","--untracked-files=all")==""
for path, expected in lock["blobs"].items():
    actual=git("hash-object",str(suite/path))
    if actual!=expected: raise SystemExit(f"fixture mismatch: {path}")
    print(f"PACKAGING_INPUT_BLOB={actual} {path}")
print("PACKAGING_COMPILER_HEAD="+git("rev-parse","HEAD"))
print("PACKAGING_COMPILER_TREE="+git("rev-parse","HEAD^{tree}"))
PY
: "${JAVA_HOME:?Use the verified GraalVM JDK25 installation}"
java -XshowSettings:properties -version 2>&1 | grep -Eq '^[[:space:]]*java.specification.version = 25$'
test "$(readlink -f "$(command -v java)")" = "$(readlink -f "$JAVA_HOME/bin/java")"
cmp "$here/sharkbench-web.atto" "$compiler/tests/fixtures/sharkbench-admission/sharkbench-web.atto"
(cd "$compiler" && bash tests/fixtures/sharkbench-admission/maven-retry.sh -B -ntp compile dependency:build-classpath -Dmdep.outputFile=target/sharkbench-classpath.txt)
test -z "$(git -C "$compiler" status --porcelain --untracked-files=all)"
mkdir -p "$stage/deps"
cp -a "$JAVA_HOME" "$stage/jdk"
cp -a "$compiler/target/classes" "$stage/classes"
cp -a "$compiler/library" "$stage/library"
cp "$here/"{Dockerfile,launch.sh,sharkbench-web.atto} "$stage/"
python3 - "$compiler/target/sharkbench-classpath.txt" "$stage" <<'PY'
import hashlib, pathlib, shutil, sys
src=pathlib.Path(sys.argv[1])
out=pathlib.Path(sys.argv[2])
paths=["/app/classes"]
for index, name in enumerate(src.read_text().strip().split(":")):
    jar=pathlib.Path(name)
    if not jar.is_file() or jar.suffix!=".jar": raise SystemExit(f"unexpected classpath entry: {jar}")
    dest=out/"deps"/f"{index:04d}.jar"
    shutil.copyfile(jar,dest)
    print(f"DEPENDENCY_SHA256={hashlib.file_digest(dest.open('rb'),'sha256').hexdigest()} {jar.name}")
    paths.append("/app/deps/"+dest.name)
(out/"classpath.txt").write_text(":".join(paths)+"\n")
PY
docker pull ubuntu:24.04
base="$(docker image inspect ubuntu:24.04 --format '{{index .RepoDigests 0}}')"
[[ "$base" =~ @sha256:[0-9a-f]{64}$ ]]
printf 'BASE_IMAGE=%s\n' "$base"
docker build --network none --build-arg "BASE_IMAGE=$base" -t "$name" "$stage"
docker image inspect "$name" --format 'CANDIDATE_IMAGE_ID={{.Id}}'
python3 - <<'PY'
import socket
for port in (5001,5002):
    with socket.socket() as s:
        s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        s.bind(("127.0.0.1",port))
PY
docker run -d --name "$name" --network host --cpus 1 --read-only --tmpfs /tmp:rw,exec,nosuid,nodev,size=256m --cap-drop ALL --security-opt no-new-privileges "$name"
python3 - "$name" <<'PY'
import socket, subprocess, sys, time
deadline=time.monotonic()+60
while True:
    if subprocess.check_output(["docker","inspect","-f","{{.State.Running}}",sys.argv[1]],text=True).strip()!="true":
        raise SystemExit("container exited before readiness")
    try:
        with socket.create_connection(("127.0.0.1",5001),timeout=.25): break
    except OSError:
        if time.monotonic()>=deadline: raise SystemExit("container not ready")
        time.sleep(.1)
PY
for probe in check_contract.py check_faults.py check_lifecycle.py; do
    timeout 120s python3 -B "$suite/$probe"
done
test "$(docker inspect -f '{{.State.Running}}' "$name")" = true
test -z "$(git -C "$compiler" status --porcelain --untracked-files=all)"
echo 'PASS: JVM Docker synthetic admission; no timing or official score'
