#!/usr/bin/env bash
# Local correctness only; no source transfer or benchmark timing.
set -euo pipefail
fail() { printf 'ADMISSION_DENIED: %s\n' "$*" >&2; exit 1; }
[[ $# == 3 ]] || fail 'usage: bash run-admission.sh COMPILER_CHECKOUT EXPECTED_COMMIT EXPECTED_TREE'
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bench="$(git -C "$here" rev-parse --show-toplevel)"
compiler="$(cd "$1" && pwd -P)"
expected="$2"
tree="$3"
[[ "$expected" =~ ^[0-9a-f]{40}$ && "$tree" =~ ^[0-9a-f]{40}$ ]] || fail 'full commit and tree SHAs required'
[[ "$(git -C "$compiler" rev-parse --show-toplevel)" == "$compiler" ]] || fail 'compiler checkout must be repository root'
[[ "$bench" != "$compiler" ]] || fail 'separate checkouts required'
clean() { [[ -z "$(git -C "$1" status --porcelain --untracked-files=all)" ]] || fail "dirty checkout: $1"; }
compiler_identity() {
  [[ "$(git -C "$compiler" rev-parse HEAD)" == "$expected" ]] || fail 'compiler commit mismatch'
  [[ "$(git -C "$compiler" rev-parse 'HEAD^{tree}')" == "$tree" ]] || fail 'compiler root tree mismatch'
  clean "$compiler"
}
clean "$bench"
compiler_identity
bench_head="$(git -C "$bench" rev-parse HEAD)"
bench_tree="$(git -C "$bench" rev-parse 'HEAD^{tree}')"
fixtures="$compiler/tests/fixtures/sharkbench-admission"
[[ -f "$fixtures/run.sh" ]] || fail 'compiler admission runner missing'
for name in sharkbench-web.atto check_contract.py check_faults.py check_lifecycle.py; do
  source="$here/../../$name"
  [[ "$name" != sharkbench-web.atto ]] || source="$here/$name"
  [[ -f "$source" && -f "$fixtures/$name" ]] || fail "missing fixture: $name"
  cmp -s "$source" "$fixtures/$name" || fail "fixture mismatch: $name"
  printf 'FIXTURE_BLOB=%s %s\n' "$(git hash-object "$source")" "$name"
done
printf 'BENCHMARK_SHA=%s BENCHMARK_TREE=%s\n' "$bench_head" "$bench_tree"
printf 'COMPILER_SHA=%s COMPILER_TREE=%s\n' "$expected" "$tree"
bash "$fixtures/run.sh"
compiler_identity
clean "$bench"
[[ "$(git -C "$bench" rev-parse HEAD)" == "$bench_head" && "$(git -C "$bench" rev-parse 'HEAD^{tree}')" == "$bench_tree" ]] || fail 'benchmark identity changed'
printf '%s\n' 'PASS: local integrated correctness only; no official score'
