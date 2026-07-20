#!/usr/bin/env python3
from __future__ import annotations

import argparse

from ftdi_mpsse import FtdiMpsseJtag
from mailbox_model import MailboxHeader


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a real YiFPGA USER2 mailbox")
    parser.add_argument("--build-id", type=lambda value: int(value, 0), default=0x4D340001)
    parser.add_argument("--tck-hz", type=int, default=6_000_000)
    args = parser.parse_args()
    jtag = FtdiMpsseJtag(tck_hz=args.tck_hz)
    try:
        raw = jtag.user_command(1, 40)
        print(f"raw_header={raw.hex()}")
        header = MailboxHeader.unpack(raw)
        print(f"PASS header session={header.session_id} build=0x{header.build_id:08x} "
              f"available={header.available_bytes} drops={header.dropped_bytes}")
        if header.build_id != args.build_id:
            raise RuntimeError("unexpected board-validation build id")
        if header.available_bytes:
            length = min(header.available_bytes, 64)
            payload = jtag.user_command(2, length)
            print(f"PASS payload bytes={len(payload)} prefix={payload[:16].hex()}")
            after = MailboxHeader.unpack(jtag.user_command(1, 40))
            committed = (after.read_count - header.read_count) & 0xFFFF_FFFF
            if committed != length:
                raise RuntimeError(f"commit mismatch: expected {length}, got {committed}")
            print(f"PASS commit read_count={header.read_count}->{after.read_count}")
        return 0
    finally:
        jtag.close()


if __name__ == "__main__":
    raise SystemExit(main())
