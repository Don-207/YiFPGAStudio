#!/usr/bin/env python3
"""Run bounded M31 UART scenarios and always restore Monitor configuration."""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import select
import struct
import time
from validate_uart_board import Decoder, TYPE_NAMES, configure

SOF, VERSION = 0xA5, 1
SAFE_WRITES = {0x0010, 0x0048, 0x004C, 0x0050, 0x005C, 0x0068, 0x006C, 0x0070, 0x0074, 0x0078, 0x007C, 0x0080, 0x0084, 0x0088, 0x008C, 0x0094}

def frame(kind: int, payload: bytes) -> bytes:
    body = bytes((VERSION, kind, len(payload))) + payload
    checksum = 0
    for value in body: checksum ^= value
    return bytes((SOF,)) + body + bytes((checksum,))

class Link:
    def __init__(self, port: str, baud: int):
        self.fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK); configure(self.fd, baud)
        self.decoder = Decoder(); self.seq = 0x3100
    def close(self): os.close(self.fd)
    def pump(self, seconds: float):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.fd], [], [], min(.1, deadline - time.monotonic()))
            if ready: self.decoder.feed(os.read(self.fd, 4096))
    def request(self, kind: int, addr: int, value: int = 0, mask: int = 0xffffffff) -> tuple[int, ...]:
        self.seq = (self.seq + 1) & 0xffff
        payload = struct.pack("<HHB", self.seq, addr, 4)
        if kind == 0x22: payload += struct.pack("<II", value, mask)
        start = len(self.decoder.frames); os.write(self.fd, frame(kind, payload)); deadline = time.monotonic() + 2
        response_kind = 0x21 if kind == 0x20 else 0x23
        while time.monotonic() < deadline:
            self.pump(.05)
            for response, data in self.decoder.frames[start:]:
                if response == response_kind and len(data) >= (14 if kind == 0x20 else 17) and struct.unpack_from("<H", data, 4)[0] == self.seq:
                    status = data[8]
                    if status: raise RuntimeError(f"Monitor status {status} for 0x{addr:04x}")
                    return (struct.unpack_from("<I", data, 10)[0],) if kind == 0x20 else struct.unpack_from("<II", data, 9)
        raise TimeoutError(f"Monitor response timeout for 0x{addr:04x}")
    def read(self, addr: int) -> int: return self.request(0x20, addr)[0]
    def write(self, addr: int, value: int, mask: int = 0xffffffff):
        if addr not in SAFE_WRITES: raise ValueError(f"unsafe write address 0x{addr:04x}")
        return self.request(0x22, addr, value, mask)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="/dev/ttyUSB1"); parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=15); parser.add_argument("--confirm-safe-writes", action="store_true")
    parser.add_argument("--scenario", choices=("profiler", "throughput-drop", "la-trigger-missing"), default="profiler")
    parser.add_argument("--record", help="write an auditable JSON record with captured payloads and recovery reads")
    args = parser.parse_args()
    if not args.confirm_safe_writes: parser.error("--confirm-safe-writes is required")
    link = Link(args.port, args.baud); original = {}
    record = {"schema": "yifpga.ai_debug_board_run", "schema_version": 1,
              "scenario": args.scenario, "started_at": datetime.now(timezone.utc).isoformat(),
              "duration_seconds": args.seconds, "baseline": {}, "recovery": {}, "frames": []}
    if args.scenario == "throughput-drop":
        def throughput_values(frames):
            values = []
            for kind, data in frames:
                if kind == 0x30 and len(data) == 32 and struct.unpack_from("<H", data, 4)[0] == 0x0001:
                    values.append(struct.unpack_from("<I", data, 12)[0])
            return values
        try:
            for addr in (0x0010, 0x0048, 0x004C): original[addr] = link.read(addr)
            record["baseline"] = {f"0x{addr:04x}": value for addr, value in original.items()}
            link.write(0x004C, 100000); link.write(0x0048, 1, 1)
            link.write(0x0010, 1000000)
            start = len(link.decoder.frames); link.pump(args.seconds); baseline_frames = link.decoder.frames[start:]
            link.write(0x0010, 100000000)
            start = len(link.decoder.frames); link.pump(args.seconds); injected_frames = link.decoder.frames[start:]
            baseline_values = throughput_values(baseline_frames); injected_values = throughput_values(injected_frames)
            if not baseline_values or not injected_values: raise RuntimeError("throughput windows were not observed")
            baseline_rate = len(baseline_values) / args.seconds; injected_rate = len(injected_values) / args.seconds
            if baseline_rate <= 0 or injected_rate / baseline_rate >= 0.8:
                raise RuntimeError(f"throughput frame rate did not drop enough: {baseline_rate}->{injected_rate}")
            record["phases"] = {
                "baseline": {"demo_period": 1000000, "values": baseline_values, "frames_per_second": baseline_rate},
                "injected": {"demo_period": 100000000, "values": injected_values, "frames_per_second": injected_rate},
            }
            captured = baseline_frames + injected_frames
            record["frames"] = [{"type": kind, "payload_hex": data.hex()} for kind, data in captured]
            record["counts"] = dict(sorted(Counter(TYPE_NAMES.get(kind, f"0x{kind:02x}") for kind, _ in captured).items()))
            print(f"throughput baseline_fps={baseline_rate:.3f} injected_fps={injected_rate:.3f} ratio={injected_rate / baseline_rate:.3f}")
        finally:
            try:
                for addr in (0x0010, 0x004C, 0x0048):
                    if addr in original: link.write(addr, original[addr])
                recovered = {addr: link.read(addr) for addr in original}
                record["recovery"] = {f"0x{addr:04x}": value for addr, value in recovered.items()}
                print("recovery=" + ",".join(f"0x{addr:04x}=0x{value:08x}" for addr, value in recovered.items()))
            finally: link.close()
        record["result"] = "pass"
        if args.record: Path(args.record).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print("PASS: bounded throughput-drop scenario captured and configuration restored")
        return 0
    if args.scenario == "la-trigger-missing":
        config_addrs = (0x0068, 0x0070, 0x0074, 0x0078, 0x007C, 0x0080, 0x0084, 0x0088, 0x0094)
        try:
            for addr in config_addrs: original[addr] = link.read(addr)
            record["baseline"] = {f"0x{addr:04x}": value for addr, value in original.items()}
            print("baseline=" + ",".join(f"0x{addr:04x}=0x{value:08x}" for addr, value in original.items()))
            link.write(0x0068, 5); link.write(0x0070, 4); link.write(0x0074, 128); link.write(0x0078, 32)
            # Probe bits 27..31 are hard-wired zero in the board demo; level-high
            # on channel 31 is therefore a deterministic non-matching trigger.
            link.write(0x007C, 1); link.write(0x0080, 31); link.write(0x0084, 1); link.write(0x0088, 0x80000000); link.write(0x0094, 0xFFFFFFFF)
            link.write(0x006C, 0xFFFFFFFF)
            start = len(link.decoder.frames); link.write(0x008C, 1); link.pump(args.seconds); captured = link.decoder.frames[start:]
            armed_status = link.read(0x006C)
            counts = Counter(TYPE_NAMES.get(kind, f"0x{kind:02x}") for kind, _ in captured)
            record["frames"] = [{"type": kind, "payload_hex": data.hex()} for kind, data in captured]
            record["counts"] = dict(sorted(counts.items()))
            record["la_status"] = armed_status
            print("scenario_types=" + ",".join(f"{key}:{value}" for key, value in sorted(counts.items())) + f",la_status=0x{armed_status:08x}")
            if counts["LA_TRIGGER_EVENT"]:
                raise RuntimeError("supposedly impossible LA trigger unexpectedly fired")
            if armed_status & 0x7 != 1:
                raise RuntimeError(f"LA did not remain ARMED (status=0x{armed_status:08x})")
        finally:
            try:
                link.write(0x008C, 2)
                for addr in reversed(config_addrs):
                    if addr in original: link.write(addr, original[addr])
                recovered = {addr: link.read(addr) for addr in original}
                record["recovery"] = {f"0x{addr:04x}": value for addr, value in recovered.items()}
                print("recovery=" + ",".join(f"0x{addr:04x}=0x{value:08x}" for addr, value in recovered.items()))
            finally: link.close()
        record["result"] = "pass"
        if args.record: Path(args.record).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print("PASS: LA trigger-missing scenario captured and configuration restored")
        return 0
    try:
        for addr in (0x0048, 0x004C, 0x005C): original[addr] = link.read(addr)
        record["baseline"] = {f"0x{addr:04x}": value for addr, value in original.items()}
        print("baseline=" + ",".join(f"0x{addr:04x}=0x{value:08x}" for addr, value in original.items()))
        link.write(0x004C, 100000); link.write(0x005C, 1); link.write(0x0050, 1); link.write(0x0048, 1, 1)
        start = len(link.decoder.frames); link.pump(args.seconds); captured = link.decoder.frames[start:]
        counts = Counter(TYPE_NAMES.get(kind, f"0x{kind:02x}") for kind, _ in captured)
        record["frames"] = [{"type": kind, "payload_hex": data.hex()} for kind, data in captured]
        record["counts"] = dict(sorted(counts.items()))
        print("scenario_types=" + ",".join(f"{key}:{value}" for key, value in sorted(counts.items())))
        if counts["PROFILER_SNAPSHOT"] < 4 or counts["PROFILER_ALERT"] < 1:
            raise RuntimeError("profiler scenario did not produce required snapshot/alert evidence")
    finally:
        try:
            for addr in (0x005C, 0x004C, 0x0048):
                if addr in original: link.write(addr, original[addr])
            recovered = {addr: link.read(addr) for addr in original}
            record["recovery"] = {f"0x{addr:04x}": value for addr, value in recovered.items()}
            print("recovery=" + ",".join(f"0x{addr:04x}=0x{value:08x}" for addr, value in recovered.items()))
        finally: link.close()
    record["result"] = "pass"
    if args.record: Path(args.record).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("PASS: bounded profiler fault scenario captured and configuration restored")
    return 0
if __name__ == "__main__": raise SystemExit(main())
