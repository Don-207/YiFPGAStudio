#!/usr/bin/env python3
"""Validate a running real-board Bridge TCP stream without controlling JTAG."""

from __future__ import annotations

import argparse
import json
import socket
import time

from bridge_protocol import TYPE_DATA, TYPE_HELLO, TYPE_STATUS, decode_records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=48534)
    parser.add_argument("--seconds", type=float, default=3.0)
    args = parser.parse_args()
    counts = {TYPE_HELLO: 0, TYPE_DATA: 0, TYPE_STATUS: 0}
    payload_bytes = 0
    latest_status = {}
    pending = b""
    deadline = time.monotonic() + args.seconds
    with socket.create_connection((args.host, args.port), timeout=2) as stream:
        stream.settimeout(0.5)
        while time.monotonic() < deadline:
            try:
                chunk = stream.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                break
            records, pending = decode_records(pending + chunk)
            for kind, payload in records:
                counts[kind] = counts.get(kind, 0) + 1
                if kind == TYPE_DATA:
                    payload_bytes += len(payload)
                elif kind == TYPE_STATUS:
                    latest_status = json.loads(payload)
    if pending or counts[TYPE_HELLO] != 1 or counts[TYPE_STATUS] < 1:
        raise RuntimeError(f"incomplete bridge stream: counts={counts} pending={len(pending)}")
    print(json.dumps({"records": counts, "payload_bytes": payload_bytes,
                      "status": latest_status}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
