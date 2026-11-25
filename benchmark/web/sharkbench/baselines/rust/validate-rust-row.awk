# Pinned upstream writer emits unquoted comma-separated fields.
BEGIN { FS=","; bad=0; rows=0 }
function fail(msg) { print "RESULT_DENIED: " msg > "/dev/stderr"; bad=1; exit 1 }
function uint(s) { return s ~ /^[0-9]+$/ }
NR==1 {
    if ($0 != "language,mode,version,framework,framework_stdlib,framework_website,framework_flavor,framework_version,concurrency,path,rps_median,rps_p99,latency_median,latency_p99,memory_median,memory_p99,errors,build_time") fail("unexpected upstream header")
    next
}
{
    if (NF!=18 || ++rows!=1) fail("expected exactly one fresh result row")
    if ($1!="Rust" || $2!="Default" || $3!="1.98.1" || $4!="Axum" || $7!="Default" || $8!="0.8.9" || $9!="32" || $10!="rust/axum-0.8.9-rust-1.98.1") fail("wrong benchmark identity")
    for (i=11; i<=17; i++) if (!uint($i)) fail("invalid numeric measurement")
    if ($11+0<=0 || $17+0!=0) fail("zero throughput or nonzero request errors")
    if (!uint($18)) fail("invalid build duration")
}
END {
    if (bad) exit 1
    if (rows!=1) fail("missing result row")
    print "FRESH_RUST_ROW_SHAPE_OK (not independent score certification)"
}
