#!/usr/bin/env python3
"""Reset one exactly matched USB device through USBDEVFS_RESET."""

from __future__ import annotations

import argparse
import fcntl
from pathlib import Path
import time

USBDEVFS_RESET = 0x5514


def find_device(vendor: int, product: int) -> Path:
    matches = []
    for entry in Path("/sys/bus/usb/devices").iterdir():
        try:
            if (int((entry / "idVendor").read_text(), 16) == vendor and
                    int((entry / "idProduct").read_text(), 16) == product):
                bus = int((entry / "busnum").read_text())
                device = int((entry / "devnum").read_text())
                matches.append(Path(f"/dev/bus/usb/{bus:03d}/{device:03d}"))
        except (FileNotFoundError, ValueError):
            continue
    if len(matches) != 1:
        raise RuntimeError(f"USB selector matched {len(matches)} devices: {matches}")
    return matches[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vendor", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--product", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--interval", type=float, default=3.0)
    args = parser.parse_args()
    if args.count < 1 or args.interval <= 0:
        parser.error("count and interval must be positive")
    for index in range(args.count):
        path = find_device(args.vendor, args.product)
        with path.open("rb", buffering=0) as device:
            fcntl.ioctl(device, USBDEVFS_RESET, 0)
        print(f"reset={index+1}/{args.count} device={path}", flush=True)
        if index + 1 < args.count:
            time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
