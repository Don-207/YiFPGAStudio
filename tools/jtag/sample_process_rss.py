#!/usr/bin/env python3
"""Record a Linux process RSS time series and reject sustained growth."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
import time


def read_rss_kib(pid: int) -> int:
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        if line.startswith("VmRSS:"):
            return int(line.split()[1])
    raise RuntimeError(f"VmRSS is unavailable for pid {pid}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=60.0)
    parser.add_argument("--interval", type=float, default=5.0)
    parser.add_argument("--max-growth-kib", type=int, default=4096)
    parser.add_argument("--csv", type=Path, required=True)
    args = parser.parse_args()
    if args.pid <= 0 or args.seconds <= 0 or args.interval <= 0:
        parser.error("pid, seconds and interval must be positive")

    started = time.monotonic()
    samples: list[tuple[float, int]] = []
    while True:
        elapsed = time.monotonic() - started
        samples.append((elapsed, read_rss_kib(args.pid)))
        if elapsed >= args.seconds:
            break
        time.sleep(min(args.interval, args.seconds - elapsed))

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as output:
        writer = csv.writer(output)
        writer.writerow(("seconds", "rss_kib"))
        writer.writerows((f"{seconds:.3f}", rss) for seconds, rss in samples)
    growth = samples[-1][1] - samples[0][1]
    print(f"samples={len(samples)} rss_first_kib={samples[0][1]} "
          f"rss_last_kib={samples[-1][1]} growth_kib={growth}")
    if growth > args.max_growth_kib:
        raise RuntimeError(
            f"RSS grew by {growth} KiB (limit {args.max_growth_kib} KiB)")
    print("PASS: process RSS has no sustained growth")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
