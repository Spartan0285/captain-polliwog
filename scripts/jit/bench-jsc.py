#!/usr/bin/env python3
"""Compare two jsc kits on a PowerPC Mac, interleaved.

Runs A, B, B, A, A, B ... rather than all of A then all of B. These are
laptops: they warm up, they throttle, and a block of A followed by a block
of B measures that as much as it measures the code. Alternating and taking
the median per test cancels most of it.

Also checks that both kits produce the same checksum. An optimisation that
changes the answer is not an optimisation, and profile-guided builds are
exactly the kind that can reorder floating-point work.

Usage:
  bench-jsc.py <host> <kitA> <kitB> [--reps N] [--script PATH]
    e.g. bench-jsc.py pbg4 jsckit-baseline jsckit-pgo --reps 5
"""
import argparse
import re
import statistics
import subprocess
import sys

LINE = re.compile(r"^(.*?): (\d+) ms")
CHECKSUM = re.compile(r"^checksum: (-?\d+)")


def run_once(host, kit, script):
    """One run of the benchmark under one kit. Returns (timings, checksum)."""
    remote = (
        f"cd /tmp/{kit} && "
        f"DYLD_FRAMEWORK_PATH=/tmp/{kit} DYLD_LIBRARY_PATH=/tmp/{kit} "
        f"./jsc {script}"
    )
    out = subprocess.run(
        ["ssh", "-n", "-o", "ConnectTimeout=30", host, remote],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        sys.exit(f"{kit} failed on {host}:\n{out.stderr.strip()}")
    timings, checksum = {}, None
    for line in out.stdout.splitlines():
        m = LINE.match(line)
        if m and not line.startswith("checksum"):
            timings[m.group(1)] = int(m.group(2))
        m = CHECKSUM.match(line)
        if m:
            checksum = m.group(1)
    if not timings:
        sys.exit(f"{kit} produced no timings:\n{out.stdout}")
    return timings, checksum


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("host")
    ap.add_argument("kit_a")
    ap.add_argument("kit_b")
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--script", default="/tmp/llint-bench.js")
    args = ap.parse_args()

    runs = {args.kit_a: [], args.kit_b: []}
    sums = {args.kit_a: set(), args.kit_b: set()}

    for i in range(args.reps):
        # Swap the order every other repetition so neither kit is always
        # the one that runs on a cold machine.
        order = [args.kit_a, args.kit_b] if i % 2 == 0 else [args.kit_b, args.kit_a]
        for kit in order:
            t, c = run_once(args.host, kit, args.script)
            runs[kit].append(t)
            if c is not None:
                sums[kit].add(c)
        print(f"  rep {i + 1}/{args.reps} done", file=sys.stderr)

    # Correctness before speed.
    all_sums = sums[args.kit_a] | sums[args.kit_b]
    if len(all_sums) > 1:
        print(f"\nCHECKSUMS DIFFER: {sums[args.kit_a]} vs {sums[args.kit_b]}")
        print("The two builds do not compute the same answer. Stop here.")
        return 1
    print(f"\nchecksum agrees across both kits: {all_sums.pop() if all_sums else 'n/a'}")

    tests = sorted(runs[args.kit_a][0])
    width = max(len(t) for t in tests)
    print(f"\n{'test'.ljust(width)}  {'A ms':>8} {'B ms':>8} {'change':>9}")
    print("-" * (width + 30))

    tot_a = tot_b = 0
    for t in tests:
        a = statistics.median(r[t] for r in runs[args.kit_a] if t in r)
        b = statistics.median(r[t] for r in runs[args.kit_b] if t in r)
        tot_a += a
        tot_b += b
        pct = (b - a) / a * 100 if a else 0
        print(f"{t.ljust(width)}  {a:8.0f} {b:8.0f} {pct:+8.1f}%")

    print("-" * (width + 30))
    pct = (tot_b - tot_a) / tot_a * 100 if tot_a else 0
    print(f"{'total'.ljust(width)}  {tot_a:8.0f} {tot_b:8.0f} {pct:+8.1f}%")
    print(f"\nA = {args.kit_a}, B = {args.kit_b}; negative means B is faster.")
    print(f"medians of {args.reps} interleaved repetitions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
