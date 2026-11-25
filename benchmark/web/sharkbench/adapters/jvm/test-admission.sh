#!/usr/bin/env bash
# Source-free identity-gate tests. Never invoke a real compiler or emit a score.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
bench="$tmp/benchmark checkout"
compiler="$tmp/compiler checkout"
adapter="$bench/benchmark/web/sharkbench/adapters/jvm"
fixtures="$compiler/tests/fixtures/sharkbench-admission"
export ADMISSION_MARKER="$tmp/invoked" ADMISSION_BENCH="$bench" ADMISSION_COMPILER="$compiler"
mkdir -p "$adapter" "$fixtures"
cp "$here/run-admission.sh" "$adapter/run-admission.sh"
for name in sharkbench-web.atto sharkbench-web-native.atto check_contract.py check_faults.py check_lifecycle.py; do
  source="$adapter/../../$name"
  [[ "$name" != sharkbench-web*.atto ]] || source="$adapter/$name"
  printf 'synthetic fixture %s\n' "$name" > "$source"
  cp "$source" "$fixtures/$name"
done
cat > "$fixtures/run.sh" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" > "$ADMISSION_MARKER"
case "${ADMISSION_MODE:-ok}" in
  ok) ;;
  failure) exit 42 ;;
  dirty-compiler) touch "$ADMISSION_COMPILER/untracked" ;;
  dirty-benchmark) touch "$ADMISSION_BENCH/untracked" ;;
  move-benchmark) git -C "$ADMISSION_BENCH" commit --allow-empty -qm moved ;;
  move-compiler) git -C "$ADMISSION_COMPILER" commit --allow-empty -qm moved ;;
  *) exit 99 ;;
esac
RUNNER
for repo in "$bench" "$compiler"; do
  git -C "$repo" init -q
  git -C "$repo" add .
  git -C "$repo" commit -qm initial
done
bhead="$(git -C "$bench" rev-parse HEAD)"
chead="$(git -C "$compiler" rev-parse HEAD)"
ctree="$(git -C "$compiler" rev-parse 'HEAD^{tree}')"
zero=0000000000000000000000000000000000000000
count=0
run_case() {
  local name="$1" invoked="$2" rc="$3" message="$4" mode="$5"
  shift 5
  rm -f "$ADMISSION_MARKER"
  local actual=0
  ADMISSION_MODE="$mode" bash "$adapter/run-admission.sh" "$@" > "$tmp/log" 2>&1 || actual=$?
  if [[ "$actual" != "$rc" ]] || ! grep -Fq "$message" "$tmp/log"; then
    cat "$tmp/log" >&2
    echo "FAIL $name: expected status $rc, got $actual" >&2; exit 1
  fi
  if [[ "$invoked" == yes ]]; then test -f "$ADMISSION_MARKER"; else test ! -e "$ADMISSION_MARKER"; fi
  if [[ "$rc" != 0 ]] && grep -Fq 'PASS: local integrated correctness' "$tmp/log"; then
    echo "FAIL $name: misleading success" >&2; exit 1
  fi
  count=$((count+1))
  printf 'PASS %s\n' "$name"
}
run_case valid yes 0 'PASS: local integrated correctness' ok "$compiler" "$chead" "$ctree"
test "$(cat "$ADMISSION_MARKER")" = boxed
run_case native yes 0 'PASS: local integrated correctness' ok "$compiler" "$chead" "$ctree" native
test "$(cat "$ADMISSION_MARKER")" = native
run_case invalid-variant no 1 'unknown workload variant' ok "$compiler" "$chead" "$ctree" bogus
printf 'different\n' > "$fixtures/sharkbench-web-native.atto"
git -C "$compiler" commit -qam mismatch-native
run_case native-mismatch no 1 'fixture mismatch: sharkbench-web-native.atto' ok "$compiler" "$(git -C "$compiler" rev-parse HEAD)" "$(git -C "$compiler" rev-parse 'HEAD^{tree}')" native
git -C "$compiler" reset --hard -q "$chead"
run_case missing-arguments no 1 'usage:' ok
run_case abbreviated-sha no 1 'full commit and tree SHAs required' ok "$compiler" "${chead:0:12}" "$ctree"
run_case wrong-commit no 1 'compiler commit mismatch' ok "$compiler" "$zero" "$ctree"
run_case wrong-tree no 1 'compiler root tree mismatch' ok "$compiler" "$chead" "$zero"
run_case nested-checkout no 1 'compiler checkout must be repository root' ok "$fixtures" "$chead" "$ctree"
run_case same-checkout no 1 'separate checkouts required' ok "$bench" "$bhead" "$(git -C "$bench" rev-parse 'HEAD^{tree}')"
touch "$bench/untracked"
run_case dirty-benchmark-before no 1 'dirty checkout:' ok "$compiler" "$chead" "$ctree"
rm "$bench/untracked"
touch "$compiler/untracked"
run_case dirty-compiler-before no 1 'dirty checkout:' ok "$compiler" "$chead" "$ctree"
rm "$compiler/untracked"
printf 'different\n' > "$fixtures/check_faults.py"
git -C "$compiler" commit -qam mismatch
run_case committed-fixture-mismatch no 1 'fixture mismatch: check_faults.py' ok "$compiler" "$(git -C "$compiler" rev-parse HEAD)" "$(git -C "$compiler" rev-parse 'HEAD^{tree}')"
git -C "$compiler" reset --hard -q "$chead"
git -C "$compiler" rm -q tests/fixtures/sharkbench-admission/check_lifecycle.py
git -C "$compiler" commit -qm missing
run_case missing-fixture no 1 'missing fixture: check_lifecycle.py' ok "$compiler" "$(git -C "$compiler" rev-parse HEAD)" "$(git -C "$compiler" rev-parse 'HEAD^{tree}')"
git -C "$compiler" reset --hard -q "$chead"
run_case runner-failure yes 42 'COMPILER_SHA=' failure "$compiler" "$chead" "$ctree"
run_case dirty-compiler-after yes 1 'dirty checkout:' dirty-compiler "$compiler" "$chead" "$ctree"
rm "$compiler/untracked"
run_case dirty-benchmark-after yes 1 'dirty checkout:' dirty-benchmark "$compiler" "$chead" "$ctree"
rm "$bench/untracked"
run_case compiler-head-moved yes 1 'compiler commit mismatch' move-compiler "$compiler" "$chead" "$ctree"
git -C "$compiler" reset --hard -q "$chead"
run_case benchmark-head-moved yes 1 'benchmark identity changed' move-benchmark "$compiler" "$chead" "$ctree"
git -C "$bench" reset --hard -q "$bhead"
printf 'PASS: %s source-free admission launcher checks; no guest execution\n' "$count"
