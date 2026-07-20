#!/usr/bin/env python3
"""Validate UART-command/JTAG-response operation on the M36 JTAG-only image."""

from __future__ import annotations

import argparse
from collections import Counter
import os
import socket
import sys
import time

sys.path.insert(0, str(__import__("pathlib").Path(__file__).parents[1] / "viewer"))
from validate_uart_board import (Decoder, configure, make_frame, monitor_read_frame,
                                 monitor_write_frame, read_u16, read_u32)
from bridge_protocol import TYPE_DATA, decode_records

READ_RESP, WRITE_RESP = 0x21, 0x23
LA_HEADER, LA_DATA, LA_STATUS, LA_TRIGGER = 0x40, 0x41, 0x42, 0x43


class Link:
    def __init__(self, uart_fd: int, stream: socket.socket) -> None:
        self.uart_fd = uart_fd
        self.stream = stream
        self.bridge_pending = b""
        self.decoder = Decoder()
        self.sequence = 0x7100
        self.counts = Counter()

    def receive(self, deadline: float) -> list[tuple[int, bytes]]:
        while time.monotonic() < deadline:
            try:
                chunk = self.stream.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                raise RuntimeError("Bridge closed the stream")
            records, self.bridge_pending = decode_records(self.bridge_pending + chunk)
            before = len(self.decoder.frames)
            for kind, payload in records:
                if kind == TYPE_DATA:
                    self.decoder.feed(payload)
            frames = self.decoder.frames[before:]
            self.counts.update(kind for kind, _ in frames)
            if frames:
                return frames
        return []

    def transact(self, request: bytes, expected: int, sequence: int) -> bytes:
        if os.write(self.uart_fd, request) != len(request):
            raise RuntimeError("short UART command write")
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            for kind, payload in self.receive(deadline):
                if kind == expected and len(payload) >= 14 and read_u16(payload, 4) == sequence:
                    if payload[8] != 0:
                        raise RuntimeError(f"Monitor status {payload[8]} at sequence {sequence}")
                    return payload
        raise TimeoutError(f"JTAG response timeout at sequence {sequence}")

    def read(self, address: int) -> int:
        sequence = self.sequence
        self.sequence = (self.sequence + 1) & 0xffff
        return read_u32(self.transact(
            monitor_read_frame(sequence, address), READ_RESP, sequence), 10)

    def write(self, address: int, value: int, mask: int = 0xffffffff) -> int:
        sequence = self.sequence
        self.sequence = (self.sequence + 1) & 0xffff
        return read_u32(self.transact(
            monitor_write_frame(sequence, address, value, mask), WRITE_RESP, sequence), 10)

    def collect(self, wanted: set[int], seconds: float) -> None:
        seen = {kind for kind in wanted if self.counts[kind]}
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline and not wanted <= seen:
            seen.update(kind for kind, _ in self.receive(deadline))
        if not wanted <= seen:
            raise RuntimeError(f"missing JTAG frame types: {sorted(wanted-seen)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--bridge-port", type=int, default=48534)
    args = parser.parse_args()

    uart_fd = os.open(args.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    configure(uart_fd, args.baud)
    stream = socket.create_connection((args.host, args.bridge_port), timeout=3)
    stream.settimeout(0.25)
    link = Link(uart_fd, stream)
    profiler_addresses = (0x0048, 0x004c, 0x0058, 0x005c)
    la_addresses = (0x0068, 0x0070, 0x0074, 0x0078, 0x007c,
                    0x0080, 0x0084, 0x0088, 0x0094)
    originals: dict[int, int] = {}
    try:
        if link.read(0x0040) != 0x4f465034 or link.read(0x0060) != 0x4f464c41:
            raise RuntimeError("Profiler/LA identity mismatch")
        originals = {address: link.read(address)
                     for address in profiler_addresses + la_addresses}
        link.write(0x0048, 0)
        link.write(0x004c, 1_000_000)
        link.write(0x0058, 0xffffffff)
        link.write(0x005c, 0)
        link.write(0x0048, 1)
        link.collect({0x30, 0x31}, 8)

        for address, value in ((0x0070, 50_000), (0x0074, 64), (0x0078, 0),
                               (0x007c, 0), (0x0080, 2), (0x0084, 1),
                               (0x0088, 1), (0x0094, 0xffffffff), (0x0068, 1)):
            link.write(address, value)
            if link.read(address) != value:
                raise RuntimeError(f"register 0x{address:04x} write mismatch")
        link.write(0x008c, 1)
        link.write(0x008c, 8)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and not (link.read(0x006c) & 8):
            time.sleep(0.05)
        else:
            if not (link.read(0x006c) & 8):
                raise TimeoutError("LA capture did not complete")
        link.write(0x008c, 0x10)
        link.collect({LA_HEADER, LA_DATA, LA_STATUS, LA_TRIGGER}, 10)
        if link.decoder.checksum_errors or link.decoder.version_errors:
            raise RuntimeError("JTAG Debug Protocol errors detected")
        print("types=" + ",".join(f"0x{k:02x}:{v}" for k, v in sorted(link.counts.items())))
        print("PASS: UART commands and JTAG-only responses/Profiler/LA frames validated")
    finally:
        if originals:
            try:
                link.write(0x008c, 2)
                link.write(0x008c, 4)
                for address in la_addresses:
                    link.write(address, originals[address])
                link.write(0x0048, 0)
                for address in profiler_addresses[1:]:
                    link.write(address, originals[address])
                link.write(0x0048, originals[0x0048])
                print("restore Profiler/LA configuration: PASS")
            except Exception as exc:
                print(f"restore failed: {exc}", file=sys.stderr)
        stream.close()
        os.close(uart_fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
