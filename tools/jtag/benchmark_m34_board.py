#!/usr/bin/env python3
"""Measure M34 USER2 burst-read throughput and transaction correctness."""
from __future__ import annotations

import argparse
import time

from ftdi_mpsse import FtdiMpsseJtag
from mailbox_model import MailboxHeader


def header(jtag: FtdiMpsseJtag) -> MailboxHeader:
    return MailboxHeader.unpack(jtag.user_command(1, 40))


def run(block_size: int, limit: int, tck_hz: int) -> tuple[int, float, int, float]:
    jtag = FtdiMpsseJtag(tck_hz=tck_hz)
    transferred = blocks = 0
    try:
        before = header(jtag)
        started = time.monotonic()
        while transferred < limit:
            current = header(jtag)
            if not current.available_bytes:
                break
            length = min(block_size, current.available_bytes, limit-transferred)
            payload = jtag.user_command(2, length)
            if len(payload) != length:
                raise RuntimeError("short payload")
            transferred += length
            blocks += 1
        elapsed = time.monotonic() - started
        after = header(jtag)
        committed = (after.read_count - before.read_count) & 0xFFFF_FFFF
        if committed != transferred:
            raise RuntimeError(
                f"commit mismatch {committed} != {transferred} "
                f"(read_count {before.read_count}->{after.read_count}, "
                f"available {before.available_bytes}->{after.available_bytes})"
            )
        return transferred, elapsed, blocks, jtag.tck_hz
    finally:
        jtag.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sizes", default="64,128,256,512,1024")
    parser.add_argument("--bytes", type=int, default=2048)
    parser.add_argument("--tck-hz", type=int, default=6_000_000)
    args = parser.parse_args()
    failed = False
    for size in (int(item) for item in args.sizes.split(",")):
        try:
            count, elapsed, blocks, actual_tck = run(size, args.bytes, args.tck_hz)
            rate = count / max(elapsed, 1e-9)
            print(f"tck={actual_tck:.0f} block={size:4d} bytes={count:4d} blocks={blocks:2d} "
                  f"seconds={elapsed:.6f} rate={rate:.1f}B/s")
        except Exception as exc:
            failed = True
            print(f"block={size:4d} FAIL {exc}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
