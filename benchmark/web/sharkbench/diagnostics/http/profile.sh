#!/usr/bin/env bash
# Diagnostic profiling only; never compare instrumented throughput to scores.
set -euo pipefail
[[ $# == 3 ]] || { echo 'usage: profile.sh COMPILER UPSTREAM NEW_OUTPUT_DIR' >&2; exit 2; }
compiler="$(cd "$1" && pwd)"
upstream="$(cd "$2" && pwd)"
out="$(realpath -m "$3")"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$out/" in "$compiler/"*|"$upstream/"*|"$here/"*) exit 2;; esac
mkdir "$out"
test "$(git -C "$compiler" rev-parse HEAD)" = a8deae8af3a377671d50dd24c9d24acda50f1f1f
test "$(git -C "$compiler" rev-parse 'HEAD^{tree}')" = 97a6a2dd95dec3b1bc3c814a7ddd078b9923b14a
test "$(git -C "$upstream" rev-parse HEAD)" = 3e1d4b1c0dbe820da2f1cf4a620bf00be8ba2b3f
test "$(git -C "$upstream" rev-parse 'HEAD^{tree}')" = 2884ce898ee9a0ce3d2650a9de9b26cd267b340b
for r in "$compiler" "$upstream"; do test -z "$(git -C "$r" status --porcelain --untracked-files=all)"; done
entry="$compiler/tests/fixtures/sharkbench-admission/sharkbench-web-native.atto"
test "$(git -C "$compiler" hash-object "$entry")" = 9d51478489dbfc7e3995db4e3fb2b15606b1b597
{ uname -a; lscpu; java -version; rustc -Vv; node -v; git -C "$compiler" rev-parse HEAD 'HEAD^{tree}'; git -C "$upstream" rev-parse HEAD 'HEAD^{tree}'; } > "$out/environment.txt" 2>&1
cp -a "$upstream/src/benchmark/web/data" "$out/data"
(cd "$out/data"; cargo build --release --locked) > "$out/data-build.log" 2>&1
(cd "$compiler"; bash tests/fixtures/sharkbench-admission/maven-retry.sh -B -ntp compile dependency:build-classpath -Dmdep.outputFile=target/sharkbench-classpath.txt) > "$out/java-build.log" 2>&1
cp="$compiler/target/classes:$(cat "$compiler/target/sharkbench-classpath.txt")"
server= sourcepid=
stop() { if [[ -n "$1" ]]; then kill -- "-$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; fi; }
trap 'stop "$server"; stop "$sourcepid"' EXIT
ready(){ for ((n=0;n<200;n++)); do kill -0 "$1" || return 1; if (echo >/dev/tcp/127.0.0.1/"$2") 2>/dev/null; then return 0; fi; sleep .1; done; return 1; }
for port in 5001 5002; do if (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then echo "busy port $port"; exit 1; fi; done
(cd "$out/data"; exec setsid "$out/data/target/release/app") > "$out/data.log" 2>&1 & sourcepid=$!
ready "$sourcepid" 5002
cpu="$(awk '/Cpus_allowed_list/ {split($2,a,/[,-]/);print a[1]}' /proc/self/status)"
test -n "$cpu"
printf 'APP_CPU=%s\n' "$cpu" >> "$out/environment.txt"
setsid taskset -c "$cpu" java -XX:ActiveProcessorCount=1 -cp "$cp" dev.oreslang.launcher.OresMain --no-core-log --permission-check=runtime --allow-net=127.0.0.1:5001,127.0.0.1:5002 "$entry" > "$out/native.log" 2>&1 & server=$!
ready "$server" 5001
timeout --kill-after=5s 180s node "$here/load.mjs" "$out/data/static" native 1 | tee "$out/warmup-unprofiled.json"
jcmd "$server" JFR.start name=requests settings=profile disk=true maxsize=128m | tee "$out/jfr-start.txt"
for round in 2 3 4; do
  timeout --kill-after=5s 180s node "$here/load.mjs" "$out/data/static" native "$round" | tee "$out/profile-$round.json"
done
jcmd "$server" JFR.stop name=requests filename="$out/requests.jfr" | tee "$out/jfr-stop.txt"
test -s "$out/requests.jfr"
jfr summary "$out/requests.jfr" | tee "$out/jfr-summary.txt"
java "$here/ProfileSummary.java" "$out/requests.jfr" | tee "$out/profile-summary.txt"
stop "$server"; server=
for r in "$compiler" "$upstream"; do git -C "$r" diff --exit-code HEAD -- .; test -z "$(git -C "$r" status --porcelain --untracked-files=all)"; done
echo 'PASS request-level CPU/allocation profile; sampled evidence only'
