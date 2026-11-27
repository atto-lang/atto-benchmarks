"""Validate one completed, drained actor benchmark trial (not a performance claim)."""
import argparse
import json
import re
import unittest


def validate(trial):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    require(isinstance(trial, dict), "trial must be an object")

    def count(key):
        value = trial.get(key)
        require(type(value) is int and value >= 0, f"invalid {key}")
        return value

    for key in ("implementation", "runtime_mode", "workload", "hardware_id", "run_id"):
        require(isinstance(trial.get(key), str) and trial[key].strip(), f"missing {key}")
    for key in ("source_commit", "harness_commit"):
        require(isinstance(trial.get(key), str) and re.fullmatch(r"[0-9a-f]{40}", trial[key]), f"invalid {key}")
    require(trial.get("correctness_passed") is True, "correctness not passed")
    offered, accepted, rejected, completed, failed = map(count, (
        "offered", "accepted", "rejected", "completed", "failed"))
    elapsed, capacity, peak = map(count, ("elapsed_ns", "queue_capacity", "peak_queue_depth"))
    require(elapsed > 0 and offered > 0 and completed > 0, "empty trial")
    require(offered == accepted + rejected, "admission accounting mismatch")
    require(accepted == completed + failed, "accepted messages not settled")
    require(failed == 0, "processing failures")
    require(capacity > 0 and peak <= capacity, "queue bound violated")
    require(count("duplicate_completions") == 0, "duplicate completions")
    require(count("pending_at_end") == 0, "not drained")
    # Dense offered IDs [0, offered) are assigned by the load generator.
    # Independently record rejection and completion IDs, not just counters.
    seen = set()
    for field, expected in (("rejected_ids", rejected), ("completed_ids", completed)):
        ids = trial.get(field)
        require(isinstance(ids, list) and len(ids) == expected, f"missing {field}")
        for value in ids:
            require(type(value) is int and 0 <= value < offered, f"invalid {field} ID")
            require(value not in seen, "duplicate or conflicting settlement ID")
            seen.add(value)
    require(len(seen) == offered, "unsettled offered ID")
    samples = trial.get("completion_latency_ns")
    require(isinstance(samples, list) and len(samples) == completed, "incomplete latency evidence")
    require(all(type(x) is int and 0 <= x <= elapsed for x in samples), "invalid latency sample")
    samples = sorted(samples)
    # Nearest-rank percentiles, integer math to avoid floating rounding at rank boundaries.
    percentiles = {f"p{p / 10:g}_ns": samples[(len(samples) * p + 999) // 1000 - 1]
                   for p in (500, 950, 990, 999)}
    return {"completed_per_second": completed * 1_000_000_000 / elapsed,
            "rejected": rejected, **percentiles}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


class Tests(unittest.TestCase):
    def trial(self):
        return dict(implementation="synthetic-test-only", runtime_mode="test", workload="ping-pong",
                    hardware_id="test", run_id="1", source_commit="a" * 40, harness_commit="b" * 40,
                    correctness_passed=True, offered=4, accepted=3, rejected=1, completed=3,
                    failed=0, elapsed_ns=100, queue_capacity=2, peak_queue_depth=2,
                    duplicate_completions=0, pending_at_end=0, rejected_ids=[3],
                    completed_ids=[0, 1, 2], completion_latency_ns=[30, 10, 20])

    def test_valid(self):
        self.assertEqual(validate(self.trial()), dict(completed_per_second=30_000_000,
                              rejected=1, p50_ns=20, p95_ns=30, p99_ns=30, **{"p99.9_ns": 30}))

    def test_duplicate_json(self):
        with self.assertRaises(ValueError):
            json.loads('{"offered": 0, "offered": 1}', object_pairs_hook=unique_object)
        with self.assertRaises(ValueError):
            validate([])

    def test_invalid(self):
        for changes in (dict(offered=5), dict(accepted=4, offered=5), dict(failed=1, completed=2),
                        dict(peak_queue_depth=3), dict(queue_capacity=0), dict(pending_at_end=1),
                        dict(duplicate_completions=1), dict(correctness_passed=False),
                        dict(completion_latency_ns=[1]), dict(completion_latency_ns=[1, 2, True]),
                        dict(completion_latency_ns=[1, 2, 101]), dict(elapsed_ns=0),
                        dict(source_commit="main"), dict(rejected=True), dict(run_id=""),
                        dict(completed_ids=[0, 0, 2]), dict(completed_ids=[0, 1, 3]),
                        dict(completed_ids=[0, 1, 4]), dict(completed_ids=[0, 1, True]),
                        dict(rejected_ids=[]), dict(rejected_ids=[-1])):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(self.trial() | changes)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trial", nargs="?", help="JSON trial file")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        unittest.main(argv=["validate.py"])
    elif args.trial:
        with open(args.trial, encoding="utf-8") as file:
            print(json.dumps(validate(json.load(file, object_pairs_hook=unique_object)), sort_keys=True))
    else:
        parser.error("supply a trial file or --self-test")
