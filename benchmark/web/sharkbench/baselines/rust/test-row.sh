#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
header='language,mode,version,framework,framework_stdlib,framework_website,framework_flavor,framework_version,concurrency,path,rps_median,rps_p99,latency_median,latency_p99,memory_median,memory_p99,errors,build_time'
row='Rust,Default,1.98.1,Axum,false,https://github.com/tokio-rs/axum,Default,0.8.9,32,rust/axum-0.8.9-rust-1.98.1,1000,900,100,500,1000,2000,0,5250'
count=0
check() {
  local want="$1" input="$2" rc=0
  printf '%s\n' "$input" | awk -f "$here/validate-rust-row.awk" >/dev/null 2>&1 || rc=$?
  if [[ "$want" != "$rc" ]]; then echo "unexpected result status $rc" >&2; exit 1; fi
  count=$((count+1))
}
check 0 "$header"$'\n'"$row"
check 1 "$header"
check 1 "$header"$'\n'"$row"$'\n'"$row"
check 1 "bad_header"$'\n'"$row"
check 1 "$header"$'\n'"${row/Rust/Atto}"
check 1 "$header"$'\n'"${row/,32,/,64,}"
check 1 "$header"$'\n'"${row/,1000,900,/,0,900,}"
check 1 "$header"$'\n'"${row/,0,5250/,1,5250}"
check 1 "$header"$'\n'"${row/,1000,900,/,NaN,900,}"
check 1 "$header"$'\n'"${row/,5250/,Infinity}"
check 1 "$header"$'\n'"${row/,5250/}"
printf 'PASS %s synthetic CSV admission cases; no benchmarks run\n' "$count"
