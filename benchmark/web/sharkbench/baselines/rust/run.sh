#!/usr/bin/env bash
# Dedicated Linux benchmark host only. Uses the unmodified upstream Rust adapter.
set -euo pipefail
die() { echo "BASELINE_DENIED: $*" >&2; exit 1; }
[[ $# == 2 ]] || die 'usage: bash run.sh CLEAN_UPSTREAM_CHECKOUT NEW_OUTPUT_DIR'
[[ "$(uname -s)" == Linux ]] || die 'Linux required'
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bench="$(git -C "$here" rev-parse --show-toplevel)"
source="$(cd "$1" && pwd -P)"
out="$(realpath -m "$2")"
case "$out/" in "$source/"*|"$bench/"*) die 'output must be outside both repositories';; esac
[[ ! -e "$out" ]] || die 'output directory already exists'
[[ "$(git -C "$source" rev-parse --show-toplevel)" == "$source" ]] || die 'upstream repository root required'
expected=3e1d4b1c0dbe820da2f1cf4a620bf00be8ba2b3f
tree=2884ce898ee9a0ce3d2650a9de9b26cd267b340b
variant=rust/axum-0.8.9-rust-1.98.1
[[ "$(git -C "$source" rev-parse HEAD)" == "$expected" ]] || die 'upstream commit mismatch'
[[ "$(git -C "$source" rev-parse 'HEAD^{tree}')" == "$tree" ]] || die 'upstream tree mismatch'
[[ -z "$(git -C "$source" status --porcelain --untracked-files=all)" ]] || die 'upstream checkout dirty'
[[ -z "$(git -C "$bench" status --porcelain --untracked-files=all)" ]] || die 'benchmark checkout dirty'
for tool in cargo rustc docker lscpu awk; do command -v "$tool" >/dev/null || die "missing $tool"; done
docker info >/dev/null
docker compose version >/dev/null
# Upstream uses fixed container names and host-network ports: dedicate this host.
[[ -z "${DOCKER_HOST:-}" ]] || die 'remote Docker host unsupported'
[[ "$(docker context show)" == default ]] || die 'default local Docker context required'
[[ -z "$(docker ps -q --filter 'name=^/benchmark$')" ]] || die 'benchmark container already running'
mkdir -- "$out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone -q --local --no-hardlinks --no-checkout -- "$source" "$work/upstream"
cd "$work/upstream"
git checkout -q --detach "$expected"
[[ "$(git rev-parse 'HEAD^{tree}')" == "$tree" ]] || die 'disposable checkout mismatch'
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || die 'disposable checkout dirty'
[[ ! -e result/web_result.csv ]] || die 'stale result present in clean upstream tree'
{
  printf 'UPSTREAM_SHA=%s\nUPSTREAM_TREE=%s\nVARIANT=%s\n' "$expected" "$tree" "$variant"
  printf 'BENCHMARK_SHA=%s\nBENCHMARK_TREE=%s\n' "$(git -C "$bench" rev-parse HEAD)" "$(git -C "$bench" rev-parse 'HEAD^{tree}')"
  printf 'CPU_QUOTA=1\nCONCURRENCY=32\nWARMUPS=1\nTIMED_ITERATIONS=5\nITERATION_SECONDS=15\n'
  date -u +%FT%TZ
  uname -a
  lscpu
  cargo -V
  rustc -Vv
  docker version
  docker compose version
} > "$out/environment.txt"
docker image ls --digests --no-trunc > "$out/images-before.txt"
count="$(cargo run --locked --release -- --web --only "$variant" --count 2>"$out/discovery.log")"
printf '%s\n' "$count" > "$out/discovery.txt"
[[ "$count" == 1 ]] || die 'expected exactly one selected upstream variant'
cargo run --locked --release -- --web --only "$variant" --validate 2>&1 | tee "$out/validate.log"
[[ ! -e result/web_result.csv ]] || die 'validation unexpectedly wrote a timed result'
cargo run --locked --release -- --web --only "$variant" 2>&1 | tee "$out/timed.log"
[[ -s result/web_result.csv ]] || die 'missing fresh upstream result'
cp result/web_result.csv "$out/web_result.csv"
awk -f "$here/validate-rust-row.awk" "$out/web_result.csv" | tee "$out/row-admission.txt"
[[ "$(git rev-parse HEAD)" == "$expected" && "$(git rev-parse 'HEAD^{tree}')" == "$tree" ]] || die 'upstream identity changed'
git diff --exit-code HEAD -- .
docker image ls --digests --no-trunc > "$out/images-after.txt"
(cd "$out" && sha256sum environment.txt discovery.log discovery.txt validate.log timed.log web_result.csv row-admission.txt images-before.txt images-after.txt > SHA256SUMS)
echo 'Rust baseline candidate captured; review image/dependency resolution and raw logs before score admission.'
