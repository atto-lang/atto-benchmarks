"""Compile and execute the drained FIFO fixture; deliberately not a timing adapter."""
import argparse
import pathlib
import subprocess
import tempfile
import unittest

MARKER = "SOURCE_ACTOR_SPAWN_STOP_VERIFIED"
FIELDS = dict(constructor_on_worker=1, released=1, ready=1, accepted=10,
              processed=10, abandoned=0, last=2853116705, successful=10,
              failed=0, failure_code=0)
RUNTIME = ("ActorOwnedI64Heap", "NativeActorScheduler", "NativeOresVM",
           "NativeActorFuture", "SourceActorBootstrap", "NativeActorLogicalFramesV1",
           "NativeExecutionContextStore", "NativeContinuationStore",
           "NativeAwaitTraceBridge", "NativeLogicalTrace")


def require(ok, message):
    if not ok:
        raise ValueError(message)


def verify(exit_code, stderr):
    require(exit_code == 43, f"unexpected guest exit: {exit_code}")
    lines = [line for line in stderr.splitlines() if line.startswith(MARKER)]
    require(len(lines) == 1, "expected exactly one terminal receipt")
    parts = lines[0].split()
    require(parts[0] == MARKER, "invalid receipt marker")
    got = {}
    for part in parts[1:]:
        key, sep, value = part.partition("=")
        require(sep and key in FIELDS and key not in got, "invalid receipt field")
        require(value.isascii() and value.isdecimal(), "invalid receipt integer")
        got[key] = int(value)
    require(got == FIELDS, f"unexpected drain/ordering receipt: {got}")
    return got


def run(argv):
    return subprocess.run(argv, capture_output=True, text=True, timeout=90, check=False)


def execute(compiler, clang, root, sanitize):
    root = pathlib.Path(root).resolve()
    runtime = root / "src/main/cpp/oreslang/runtime"
    fixture = pathlib.Path(__file__).resolve().parent / "fixtures/llvm-drained-fifo.atto"
    with tempfile.TemporaryDirectory(prefix="atto-drained-") as tmp:
        ll = pathlib.Path(tmp) / "guest.ll"
        exe = pathlib.Path(tmp) / "guest"
        emitted = run([compiler, str(fixture)])
        require(emitted.returncode == 0, emitted.stderr)
        require(emitted.stdout.startswith("; ModuleID"), "missing LLVM module")
        for operation in ("spawn", "send", "stop", "flush"):
            require(f"@oreslang_source_actor_{operation}" in emitted.stdout,
                    f"missing actor {operation} lowering")
        ll.write_text(emitted.stdout, encoding="utf-8")
        flags = ["-O1"]
        if sanitize:
            flags += ["-g", "-fno-omit-frame-pointer", "-fsanitize=address,undefined"]
        linked = run([clang, *flags, "-x", "ir", str(ll), "-x", "c",
                      *[str(runtime / (name + ".c")) for name in RUNTIME],
                      "-std=c11", "-pthread", "-I", str(root / "src/main/cpp"),
                      "-DORESLANG_SOURCE_ACTOR_TESTING", "-o", str(exe)])
        require(linked.returncode == 0, linked.stderr)
        result = run([str(exe)])
        verify(result.returncode, result.stderr)
        print("PASS drained FIFO compiled guest: accepted=10 completed=10 abandoned=0 digest=2853116705")


class Tests(unittest.TestCase):
    def test_receipt(self):
        line = MARKER + " " + " ".join(f"{k}={v}" for k, v in FIELDS.items())
        self.assertEqual(verify(43, line), FIELDS)
        for bad in ("", line + "\n" + line, line + " last=2853116705",
                    line.replace("abandoned=0", "abandoned=1"),
                    line.replace("last=2853116705", "last=1"),
                    line.replace("successful=10", "successful=9"),
                    line.replace("ready=1", "ready=0")):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                verify(43, bad)
        with self.assertRaises(ValueError):
            verify(1, line)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--compiler")
    p.add_argument("--clang")
    p.add_argument("--root")
    p.add_argument("--sanitize", action="store_true")
    a = p.parse_args()
    if a.self_test:
        unittest.main(argv=["llvm_drained_smoke.py"])
    elif a.compiler and a.clang and a.root:
        execute(a.compiler, a.clang, a.root, a.sanitize)
    else:
        p.error("supply compiler, clang, root or --self-test")
