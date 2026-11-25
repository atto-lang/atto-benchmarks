#!/usr/bin/env bash
# Executes real container guest; never an official benchmark score.
set -euo pipefail
[[ $# == 1 || $# == 2 ]] || { echo "usage: $0 /path/to/exact/compiler [new-export-directory]" >&2; exit 2; }
export_dir="${2:-}"
if [[ -n "$export_dir" ]]; then
  export_dir="$(realpath -m -- "$export_dir")"
  test ! -e "$export_dir" && test ! -L "$export_dir" && test -d "$(dirname "$export_dir")"
fi
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
test "$(uname -s)" = Linux
test "$(uname -m)" = x86_64
java --version | grep -F 'Oracle GraalVM 25.3.4.1+1.1 (build 25.0.4.1+1-LTS-jvmci-25.3-b22)'
cmp "$here/sharkbench-web.atto" "$compiler/tests/fixtures/sharkbench-admission/sharkbench-web.atto"
(cd "$compiler" && bash tests/fixtures/sharkbench-admission/maven-retry.sh -B -ntp compile dependency:build-classpath -Dmdep.outputFile=target/sharkbench-classpath.txt)
test -z "$(git -C "$compiler" status --porcelain --untracked-files=all)"
mkdir -p "$stage/deps"
cp -a "$JAVA_HOME" "$stage/jdk"
cp -a "$compiler/target/classes" "$stage/classes"
cp -a "$compiler/library" "$stage/library"
cp "$here/"{Dockerfile,launch.sh,sharkbench-web.atto,benchmark.yaml,jvm-admission.lock.json} "$stage/"
python3 - "$compiler/target/sharkbench-classpath.txt" "$stage" <<'PY'
import hashlib, json, pathlib, shutil, sys
src=pathlib.Path(sys.argv[1])
out=pathlib.Path(sys.argv[2])
lock=json.loads((out/"jvm-admission.lock.json").read_text())["container_receipt"]
paths=["/app/classes"]
entries=src.read_text().strip().split(":")
if len(entries)!=len(lock["ordered_dependencies"]):
    raise SystemExit("dependency count changed")
for index, (name, expected) in enumerate(zip(entries, lock["ordered_dependencies"])):
    jar=pathlib.Path(name)
    if not jar.is_file() or jar.suffix!=".jar": raise SystemExit(f"unexpected classpath entry: {jar}")
    dest=out/"deps"/f"{index:04d}.jar"
    shutil.copyfile(jar,dest)
    with dest.open("rb") as stream:
        actual=hashlib.file_digest(stream,"sha256").hexdigest()
    if jar.name!=expected["name"] or actual!=expected["sha256"]:
        raise SystemExit(f"dependency lock mismatch at index {index}: {jar.name}")
    print(f"DEPENDENCY_SHA256={actual} {jar.name}")
    paths.append("/app/deps/"+dest.name)
(out/"classpath.txt").write_text(":".join(paths)+"\n")
PY
base="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["container_receipt"]["base_image"])' "$here/jvm-admission.lock.json")"
docker pull --platform linux/amd64 "$base"
[[ "$base" =~ @sha256:[0-9a-f]{64}$ ]]
printf 'BASE_IMAGE=%s\n' "$base"
docker build --platform linux/amd64 --network none --build-arg "BASE_IMAGE=$base" -t "$name" "$stage"
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
# Record the actual staged file hashes and symlink targets; this receipt
# enables independent comparison of JDK and compiled outputs on repeat builds.
python3 - "$stage" <<'PY'
import hashlib,json,os,pathlib,stat,sys
root=pathlib.Path(sys.argv[1])
items=[]
for p in sorted(root.rglob("*")):
    entry={"path":p.relative_to(root).as_posix(),"mode":oct(stat.S_IMODE(p.lstat().st_mode))}
    if p.is_symlink():
        entry["symlink"]=os.readlink(p)
    elif p.is_file():
        with p.open("rb") as stream:
            entry["sha256"]=hashlib.file_digest(stream,"sha256").hexdigest()
    elif p.is_dir():
        continue
    else:
        raise SystemExit(f"unsupported staged file {p}")
    items.append(entry)
encoded=(json.dumps(items,sort_keys=True,separators=(",",":"))+"\n").encode()
(root/"stage-manifest.json").write_bytes(encoded)
print("STAGE_MANIFEST_SHA256="+hashlib.sha256(encoded).hexdigest())
PY
echo 'PASS: JVM Docker synthetic admission; no timing or official score'
if [[ -n "$export_dir" ]]; then
    mv -T --no-clobber -- "$stage" "$export_dir"
    test ! -e "$stage" && test -f "$export_dir/stage-manifest.json"
    printf 'ADMITTED_CONTEXT=%s\n' "$export_dir"
fi
