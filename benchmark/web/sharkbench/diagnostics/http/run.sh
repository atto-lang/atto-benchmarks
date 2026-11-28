#!/usr/bin/env bash
# Exact source, sequential same-runner native processes; NOT official scores.
set -euo pipefail
[[ $# == 3 ]] || { echo 'usage: run.sh COMPILER_CHECKOUT UPSTREAM_CHECKOUT NEW_OUTPUT_DIR' >&2; exit 2; }
compiler="$(cd "$1" && pwd)"
upstream="$(cd "$2" && pwd)"
out="$(realpath -m "$3")"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$out/" in "$compiler/"*|"$upstream/"*|"$here/"*) exit 2;; esac
mkdir "$out"
test "$(git -C "$compiler" rev-parse HEAD)" = ca0372a980d42ff56eb0b1d1f41f193a4648922d
test "$(git -C "$compiler" rev-parse 'HEAD^{tree}')" = 30d2c95474465a25e8682c2a40176afdba752ace
test "$(git -C "$upstream" rev-parse HEAD)" = 3e1d4b1c0dbe820da2f1cf4a620bf00be8ba2b3f
test "$(git -C "$upstream" rev-parse 'HEAD^{tree}')" = 2884ce898ee9a0ce3d2650a9de9b26cd267b340b
for r in "$compiler" "$upstream"; do test -z "$(git -C "$r" status --porcelain --untracked-files=all)"; done
{ uname -a; lscpu; java -version; cargo -V; rustc -Vv; node -v; git -C "$compiler" rev-parse HEAD 'HEAD^{tree}'; git -C "$upstream" rev-parse HEAD 'HEAD^{tree}'; } > "$out/environment.txt" 2>&1
data="$upstream/src/benchmark/web/data"
rust="$upstream/benchmark/web/rust/axum-0.8.9-rust-1.98.1"
# Build upstream adapter in disposable copy; preserve resolved lock and source identity.
cp -a "$rust" "$out/rust"
cp -a "$data" "$out/data"
(cd "$out/rust"; cargo generate-lockfile; cargo build --release --locked) > "$out/rust-build.log" 2>&1
(cd "$out/data"; cargo build --release --locked) > "$out/data-build.log" 2>&1
(cd "$out"; sha256sum rust/Cargo.lock data/Cargo.lock > dependency-locks.sha256)
(cd "$compiler"; bash tests/fixtures/sharkbench-admission/maven-retry.sh -B -ntp compile dependency:build-classpath -Dmdep.outputFile=target/sharkbench-classpath.txt) > "$out/java-build.log" 2>&1
cp="$compiler/target/classes:$(cat "$compiler/target/sharkbench-classpath.txt")"
dataexe="$(find "$out/data/target/release" -maxdepth 1 -type f -executable | head -n1)"
test -n "$dataexe"
server= sourcepid=
stop() { if [[ -n "$1" ]]; then kill -- "-$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; fi; }
trap 'stop "$server"; stop "$sourcepid"' EXIT
ready(){ for ((n=0;n<200;n++)); do kill -0 "$1" || return 1; if (echo >/dev/tcp/127.0.0.1/"$2") 2>/dev/null; then return 0; fi; sleep .1; done; return 1; }
for port in 5001 5002; do if (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then echo "busy port $port"; exit 1; fi; done
(cd "$out/data"; exec setsid "$dataexe") > "$out/data.log" 2>&1 & sourcepid=$!
ready "$sourcepid" 5002
cpu="$(awk '/Cpus_allowed_list/ {split($2,a,/[,-]/);print a[1]}' /proc/self/status)"
test -n "$cpu"
printf 'APP_CPU=%s\n' "$cpu" >> "$out/environment.txt"
for round in 1 2 3; do
  case "$round" in 1) variants="boxed native rust";; 2) variants="native rust boxed";; 3) variants="rust boxed native";; esac
  for variant in $variants; do
    if [[ "$variant" == rust ]]; then
      setsid taskset -c "$cpu" "$out/rust/target/release/app" > "$out/$variant-$round.log" 2>&1 & server=$!
    else
      entry=sharkbench-web.atto; [[ "$variant" == native ]] && entry=sharkbench-web-native.atto
      setsid taskset -c "$cpu" java -XX:ActiveProcessorCount=1 -cp "$cp" dev.oreslang.launcher.OresMain --no-core-log --permission-check=runtime --allow-net=127.0.0.1:5001,127.0.0.1:5002 "$compiler/tests/fixtures/sharkbench-admission/$entry" > "$out/$variant-$round.log" 2>&1 & server=$!
    fi
    ready "$server" 5001
    timeout --kill-after=5s 180s node "$here/load.mjs" "$out/data/static" "$variant" "$round" | tee "$out/$variant-$round.json"
    stop "$server"; server=
  done
done
for r in "$compiler" "$upstream"; do git -C "$r" diff --exit-code HEAD -- .; done
echo 'PASS all nine diagnostic trials; not official SharkBench scores'
