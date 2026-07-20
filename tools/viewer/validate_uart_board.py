#!/usr/bin/env python3
"""Dependency-free YiFPGA UART board validator for POSIX hosts."""
from __future__ import annotations

import argparse
from collections import Counter
import os
from pathlib import Path
import select
import termios
import time

SOF, VERSION, MAX_PAYLOAD = 0xA5, 0x01, 32
TYPE_NAMES = {
    0x01: "HEARTBEAT", 0x02: "DEBUG_PRINT", 0x03: "EVENT",
    0x04: "WATCH", 0x05: "STATUS", 0x10: "TRACE_SPAN_BEGIN",
    0x11: "TRACE_SPAN_END", 0x12: "TRACE_MARK", 0x13: "TRACE_VALUE",
    0x14: "TRACE_DROP", 0x21: "MONITOR_READ_RESP",
    0x23: "MONITOR_WRITE_RESP", 0x30: "PROFILER_SNAPSHOT",
    0x31: "PROFILER_ALERT", 0x40: "LA_CAPTURE_HEADER",
    0x41: "LA_SAMPLE_DATA", 0x42: "LA_CAPTURE_STATUS",
    0x43: "LA_TRIGGER_EVENT",
}
MONITOR_READ_REQ = 0x20
MONITOR_READ_RESP = 0x21
MONITOR_WRITE_REQ = 0x22
MONITOR_WRITE_RESP = 0x23


class Decoder:
    def __init__(self) -> None:
        self.buffer = bytearray()
        self.frames: list[tuple[int, bytes]] = []
        self.checksum_errors = 0
        self.sync_drops = 0
        self.version_errors = 0
        self.locked = False
        self.bad_frames: list[bytes] = []

    def feed(self, data: bytes) -> None:
        self.buffer.extend(data)
        while len(self.buffer) >= 5:
            if self.buffer[0] != SOF:
                del self.buffer[0]
                self.sync_drops += 1
                continue
            length = self.buffer[3]
            if (self.buffer[1] != VERSION or self.buffer[2] not in TYPE_NAMES or
                    length > MAX_PAYLOAD):
                del self.buffer[0]
                self.sync_drops += 1
                continue
            total = length + 5
            if len(self.buffer) < total:
                return
            raw = bytes(self.buffer[:total])
            checksum = 0
            for value in raw[1:-1]:
                checksum ^= value
            if checksum != raw[-1]:
                # Before the first valid frame, an 0xA5 inside the partial frame
                # present at open time is only a false sync candidate.
                if self.locked:
                    self.checksum_errors += 1
                    if len(self.bad_frames) < 4:
                        self.bad_frames.append(raw)
                else:
                    self.sync_drops += 1
                del self.buffer[0]
                continue
            del self.buffer[:total]
            if raw[1] != VERSION:
                self.version_errors += 1
                continue
            self.frames.append((raw[2], raw[4:-1]))
            self.locked = True


def configure(fd: int, baud: int) -> None:
    speeds = {115200: termios.B115200, 230400: termios.B230400,
              460800: termios.B460800, 921600: termios.B921600}
    if baud not in speeds:
        raise ValueError(f"unsupported baud: {baud}")
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = attrs[5] = speeds[baud]
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIFLUSH)


def u16(value: int) -> bytes:
    return bytes((value & 0xFF, (value >> 8) & 0xFF))


def u32(value: int) -> bytes:
    return bytes((value >> shift) & 0xFF for shift in (0, 8, 16, 24))


def read_u16(data: bytes, offset: int) -> int:
    return data[offset] | (data[offset + 1] << 8)


def read_u32(data: bytes, offset: int) -> int:
    return sum(data[offset + index] << (8 * index) for index in range(4))


def make_frame(msg_type: int, payload: bytes) -> bytes:
    body = bytes((VERSION, msg_type, len(payload))) + payload
    checksum = 0
    for value in body:
        checksum ^= value
    return bytes((SOF,)) + body + bytes((checksum,))


def monitor_read_frame(sequence: int, address: int) -> bytes:
    return make_frame(MONITOR_READ_REQ, u16(sequence) + u16(address) + b"\x04")


def monitor_write_frame(sequence: int, address: int, value: int, mask: int) -> bytes:
    payload = u16(sequence) + u16(address) + b"\x04" + u32(value) + u32(mask)
    return make_frame(MONITOR_WRITE_REQ, payload)


class MonitorLink:
    def __init__(self, fd: int) -> None:
        self.fd = fd
        self.decoder = Decoder()
        self.sequence = 0x4100
        self.checked = 0

    def next_sequence(self) -> int:
        sequence = self.sequence
        self.sequence = (self.sequence + 1) & 0xFFFF
        return sequence

    def transact(self, request: bytes, expected_type: int, sequence: int,
                 timeout: float) -> bytes:
        written = os.write(self.fd, request)
        if written != len(request):
            raise RuntimeError(f"short UART write: {written}/{len(request)} bytes")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            readable, _, _ = select.select(
                [self.fd], [], [], min(0.05, deadline-time.monotonic()))
            if not readable:
                continue
            self.decoder.feed(os.read(self.fd, 4096))
            while self.checked < len(self.decoder.frames):
                msg_type, payload = self.decoder.frames[self.checked]
                self.checked += 1
                if msg_type == expected_type and len(payload) >= 9 and read_u16(payload, 4) == sequence:
                    # A soak run may process hundreds of thousands of background
                    # frames. Once the matching response is found, older frames
                    # are no longer needed and must not grow memory unboundedly.
                    self.decoder.frames.clear()
                    self.checked = 0
                    return payload
        raise TimeoutError(
            f"Monitor response timeout: type=0x{expected_type:02X} seq=0x{sequence:04X} "
            f"timeout={timeout:.3f}s valid_frames={len(self.decoder.frames)} "
            f"checksum_errors={self.decoder.checksum_errors}"
        )

    def read(self, address: int, timeout: float) -> tuple[int, int, int]:
        sequence = self.next_sequence()
        payload = self.transact(
            monitor_read_frame(sequence, address), MONITOR_READ_RESP, sequence, timeout)
        if len(payload) < 14:
            raise RuntimeError(f"short Monitor read response: {len(payload)} bytes")
        if read_u16(payload, 6) != address:
            raise RuntimeError("Monitor response address mismatch")
        return payload[8], payload[9], read_u32(payload, 10)

    def write(self, address: int, value: int, mask: int,
              timeout: float) -> tuple[int, int, int]:
        sequence = self.next_sequence()
        payload = self.transact(
            monitor_write_frame(sequence, address, value, mask),
            MONITOR_WRITE_RESP, sequence, timeout)
        if len(payload) < 17:
            raise RuntimeError(f"short Monitor write response: {len(payload)} bytes")
        if read_u16(payload, 6) != address:
            raise RuntimeError("Monitor response address mismatch")
        return payload[8], read_u32(payload, 9), read_u32(payload, 13)


def monitor_read(port: str, baud: int, address: int, timeout: float) -> None:
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        configure(fd, baud)
        link = MonitorLink(fd)
        status, width, value = link.read(address, timeout)
        print(f"monitor_read addr=0x{address:04X} status={status} width={width} "
              f"value=0x{value:08X} checksum_errors={link.decoder.checksum_errors}")
        if status != 0 or width != 4:
            raise RuntimeError(f"unexpected Monitor read response status={status} width={width}")
        if link.decoder.checksum_errors:
            raise RuntimeError("UART checksum error while waiting for Monitor response")
        print("PASS: UART Monitor read validation")
    finally:
        os.close(fd)


def monitor_safe_suite(port: str, baud: int, timeout: float) -> None:
    led_address = 0x000C
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    original_led = None
    link = MonitorLink(fd)
    try:
        configure(fd, baud)
        status, width, monitor_id = link.read(0x0000, timeout)
        if (status, width, monitor_id) != (0, 4, 0x4F464D30):
            raise RuntimeError(f"unexpected MONITOR_ID response: {(status, width, monitor_id)}")
        status, width, original_led = link.read(led_address, timeout)
        if status != 0 or width != 4:
            raise RuntimeError("failed to read original LED_CONTROL")
        test_led = original_led ^ 0x3
        status, old_value, new_value = link.write(led_address, test_led, 0x3, timeout)
        if status != 0 or old_value != original_led or new_value != test_led:
            raise RuntimeError("LED_CONTROL masked write response mismatch")
        status, width, readback = link.read(led_address, timeout)
        if status != 0 or width != 4 or readback != test_led:
            raise RuntimeError("LED_CONTROL readback mismatch")
        status, _, _ = link.write(0x0000, 0, 0xFFFFFFFF, timeout)
        if status != 2:
            raise RuntimeError(f"RO write returned status {status}, expected DENIED(2)")
        status, _, _ = link.read(0x003C, timeout)
        if status != 1:
            raise RuntimeError(f"invalid address returned status {status}, expected BAD_ADDR(1)")
        print(f"monitor_safe_suite id=0x{monitor_id:08X} led_original=0x{original_led:08X} "
              f"led_test=0x{test_led:08X} ro_status=2 bad_addr_status=1")
    finally:
        if original_led is not None:
            try:
                status, _, restored = link.write(
                    led_address, original_led, 0xFFFFFFFF, timeout)
                if status != 0 or restored != original_led:
                    raise RuntimeError("LED_CONTROL restore response mismatch")
                status, width, readback = link.read(led_address, timeout)
                if status != 0 or width != 4 or readback != original_led:
                    raise RuntimeError("LED_CONTROL restore readback mismatch")
                print(f"restore LED_CONTROL=0x{original_led:08X}: PASS")
            finally:
                os.close(fd)
        else:
            os.close(fd)
    if link.decoder.checksum_errors:
        raise RuntimeError(f"UART checksum errors during safe suite: {link.decoder.checksum_errors}")
    print("PASS: UART Monitor safe read/write/error validation")


def monitor_control_suite(port: str, baud: int, timeout: float) -> None:
    period_address = 0x0010
    counter_address = 0x0014
    clear_address = 0x0018
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    link = MonitorLink(fd)
    original_period = None
    try:
        configure(fd, baud)
        status, width, original_period = link.read(period_address, timeout)
        if status != 0 or width != 4 or original_period == 0:
            raise RuntimeError("failed to read valid original DEMO_PERIOD")
        test_period = max(100_000, original_period // 2)
        if test_period == original_period:
            test_period = original_period + 1
        status, old_value, new_value = link.write(
            period_address, test_period, 0xFFFFFFFF, timeout)
        if status != 0 or old_value != original_period or new_value != test_period:
            raise RuntimeError("DEMO_PERIOD write response mismatch")
        status, width, readback = link.read(period_address, timeout)
        if status != 0 or width != 4 or readback != test_period:
            raise RuntimeError("DEMO_PERIOD readback mismatch")
        status, old_value, new_value = link.write(
            period_address, 0, 0xFFFFFFFF, timeout)
        if status != 5 or old_value != test_period or new_value != test_period:
            raise RuntimeError("DEMO_PERIOD zero did not return BAD_VALUE(5) without change")

        status, width, counter_before = link.read(counter_address, timeout)
        if status != 0 or width != 4:
            raise RuntimeError("failed to read COUNTER0 before clear")
        status, _, _ = link.write(clear_address, 1, 0xFFFFFFFF, timeout)
        if status != 0:
            raise RuntimeError("CLEAR_COUNTERS trigger failed")
        status, width, counter_after = link.read(counter_address, timeout)
        if status != 0 or width != 4:
            raise RuntimeError("failed to read COUNTER0 after clear")
        # The free-running 100 MHz counter advances while the response is
        # packetized, so it need not read as zero. It must return to the early
        # post-clear region rather than continue from the pre-clear value.
        if counter_before > 2_000_000 and counter_after >= counter_before:
            raise RuntimeError(
                f"COUNTER0 did not fall after clear: before={counter_before} after={counter_after}")
        print(f"monitor_control_suite period_original={original_period} "
              f"period_test={test_period} zero_status=5 "
              f"counter_before={counter_before} counter_after={counter_after}")
    finally:
        if original_period is not None:
            try:
                status, _, restored = link.write(
                    period_address, original_period, 0xFFFFFFFF, timeout)
                if status != 0 or restored != original_period:
                    raise RuntimeError("DEMO_PERIOD restore response mismatch")
                status, width, readback = link.read(period_address, timeout)
                if status != 0 or width != 4 or readback != original_period:
                    raise RuntimeError("DEMO_PERIOD restore readback mismatch")
                print(f"restore DEMO_PERIOD={original_period}: PASS")
            finally:
                os.close(fd)
        else:
            os.close(fd)
    if link.decoder.checksum_errors:
        raise RuntimeError(
            f"UART checksum errors during control suite: {link.decoder.checksum_errors}")
    print("PASS: UART Monitor period/clear control validation")


def monitor_soak(port: str, baud: int, timeout: float, duration: float,
                 interval: float) -> None:
    if duration <= 0 or interval <= 0:
        raise ValueError("Monitor soak duration and interval must be positive")
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    link = MonitorLink(fd)
    reads = 0
    started = time.monotonic()
    deadline = started + duration
    next_read = started
    next_progress = started + 60.0
    try:
        configure(fd, baud)
        while time.monotonic() < deadline:
            now = time.monotonic()
            if now < next_read:
                time.sleep(min(next_read - now, 0.05))
                continue
            status, width, value = link.read(0x0000, timeout)
            if (status, width, value) != (0, 4, 0x4F464D30):
                raise RuntimeError(
                    f"unexpected MONITOR_ID during soak: {(status, width, value)}")
            reads += 1
            next_read += interval
            if time.monotonic() >= next_progress:
                elapsed = time.monotonic() - started
                print(f"monitor_soak_progress seconds={elapsed:.1f} reads={reads} "
                      f"checksum_errors={link.decoder.checksum_errors} "
                      f"sync_drops={link.decoder.sync_drops}", flush=True)
                next_progress += 60.0
    finally:
        os.close(fd)
    elapsed = time.monotonic() - started
    print(f"monitor_soak seconds={elapsed:.3f} reads={reads} "
          f"checksum_errors={link.decoder.checksum_errors} "
          f"sync_drops={link.decoder.sync_drops}")
    if link.decoder.checksum_errors:
        raise RuntimeError("UART checksum errors detected during Monitor soak")
    expected_minimum = max(1, int(duration / interval) - 1)
    if reads < expected_minimum:
        raise RuntimeError(f"only {reads} Monitor reads, expected at least {expected_minimum}")
    print("PASS: UART Monitor bidirectional soak validation")


def profiler_soak(port: str, baud: int, timeout: float, duration: float) -> None:
    if duration <= 0:
        raise ValueError("Profiler soak duration must be positive")
    addresses = {
        "control": 0x0048, "period": 0x004C, "clear": 0x0050,
        "mask": 0x0058, "threshold": 0x005C,
    }
    expected_metrics = {0x0001, 0x0101, 0x0201, 0x0301}
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    link = MonitorLink(fd)
    originals: dict[str, int] = {}
    counts = Counter()
    overflow_first: dict[int, int] = {}
    overflow_last: dict[int, int] = {}
    overflow_max: dict[int, int] = {}
    status_drop_first = None
    status_drop_last = None
    status_drop_max = 0
    try:
        configure(fd, baud)
        for address, expected in ((0x0040, 0x4F465034), (0x0044, 0x00010000)):
            status, width, value = link.read(address, timeout)
            if (status, width, value) != (0, 4, expected):
                raise RuntimeError(
                    f"unexpected Profiler identity at 0x{address:04X}: "
                    f"{(status, width, value)}")
        for name in ("control", "period", "mask", "threshold"):
            status, width, value = link.read(addresses[name], timeout)
            if status != 0 or width != 4:
                raise RuntimeError(f"failed to read original Profiler {name}")
            originals[name] = value

        for name, value, mask in (
                # A 1,000,000-cycle window yields about 100 snapshots/s at
                # 100 MHz: below 115200-baud capacity while providing enough
                # windows to expose counter growth during a bounded soak.
                ("control", 0, 1), ("period", 1_000_000, 0xFFFFFFFF),
                ("mask", 0xFFFFFFFF, 0xFFFFFFFF),
                ("threshold", 0, 0xFFFFFFFF), ("clear", 1, 0xFFFFFFFF),
                ("control", 1, 1)):
            status, _, new_value = link.write(addresses[name], value, mask, timeout)
            if status != 0 or (name != "clear" and (new_value & mask) != (value & mask)):
                raise RuntimeError(f"failed to configure Profiler {name}: status={status}")

        link.decoder.frames.clear()
        link.checked = 0
        started = time.monotonic()
        deadline = started + duration
        next_progress = started + 60.0
        while time.monotonic() < deadline:
            readable, _, _ = select.select(
                [fd], [], [], min(0.25, deadline - time.monotonic()))
            if readable:
                link.decoder.feed(os.read(fd, 4096))
                for msg_type, payload in link.decoder.frames:
                    counts[msg_type] += 1
                    if msg_type == 0x30 and len(payload) == 32:
                        metric_id = read_u16(payload, 4)
                        overflow = read_u32(payload, 28)
                        overflow_first.setdefault(metric_id, overflow)
                        overflow_last[metric_id] = overflow
                        overflow_max[metric_id] = max(
                            overflow_max.get(metric_id, 0), overflow)
                    elif msg_type == 0x05 and len(payload) >= 8:
                        drop_count = read_u16(payload, 6)
                        if status_drop_first is None:
                            status_drop_first = drop_count
                        status_drop_last = drop_count
                        status_drop_max = max(status_drop_max, drop_count)
                link.decoder.frames.clear()
                link.checked = 0
            if time.monotonic() >= next_progress:
                seen = ",".join(f"0x{x:04X}" for x in sorted(overflow_last))
                print(f"profiler_soak_progress seconds={time.monotonic()-started:.1f} "
                      f"snapshots={counts[0x30]} alerts={counts[0x31]} "
                      f"metrics=[{seen}] checksum_errors={link.decoder.checksum_errors} "
                      f"drop_max={status_drop_max}", flush=True)
                next_progress += 60.0

        missing = expected_metrics - set(overflow_last)
        overflow_saturated = {
            metric: overflow for metric, overflow in overflow_max.items()
            if overflow == 0xFFFF
        }
        print(f"profiler_soak seconds={time.monotonic()-started:.3f} "
              f"snapshots={counts[0x30]} alerts={counts[0x31]} "
              f"status_frames={counts[0x05]} checksum_errors={link.decoder.checksum_errors} "
              f"sync_drops={link.decoder.sync_drops} drop_first={status_drop_first} "
              f"drop_last={status_drop_last} drop_max={status_drop_max} "
              f"overflow_max={overflow_max}")
        if missing:
            raise RuntimeError(f"missing Profiler metrics: {sorted(missing)}")
        if link.decoder.checksum_errors:
            raise RuntimeError("UART checksum errors during Profiler soak")
        if status_drop_first is None or status_drop_max != 0:
            raise RuntimeError(f"Debug Core drop_count is not stable at zero: {status_drop_max}")
        if overflow_saturated:
            raise RuntimeError(
                f"Profiler overflow counters saturated: {overflow_saturated}")
    finally:
        if originals:
            try:
                if "control" in originals:
                    link.write(addresses["control"], originals["control"], 0xFFFFFFFF, timeout)
                for name in ("period", "mask", "threshold"):
                    if name in originals:
                        link.write(addresses[name], originals[name], 0xFFFFFFFF, timeout)
                print("restore Profiler control/period/mask/threshold: PASS")
            finally:
                os.close(fd)
        else:
            os.close(fd)
    print("PASS: UART Profiler board soak validation")


def validate(port: str, baud: int, duration: float, minimum: int,
             capture: Path | None = None) -> None:
    fd = os.open(port, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
    decoder = Decoder()
    byte_count = 0
    started = time.monotonic()
    capture_file = capture.open("wb") if capture else None
    try:
        configure(fd, baud)
        deadline = started + duration
        while time.monotonic() < deadline:
            readable, _, _ = select.select([fd], [], [], min(0.25, deadline-time.monotonic()))
            if readable:
                data = os.read(fd, 4096)
                if capture_file:
                    capture_file.write(data)
                byte_count += len(data)
                decoder.feed(data)
    finally:
        if capture_file:
            capture_file.close()
        os.close(fd)
    elapsed = max(time.monotonic() - started, 1e-9)
    counts = Counter(TYPE_NAMES.get(kind, f"0x{kind:02x}") for kind, _ in decoder.frames)
    trace_ids = Counter()
    trace_statuses = Counter()
    status_drop_counts = []
    for kind, payload in decoder.frames:
        if kind in (0x10, 0x11) and len(payload) >= 8:
            trace_ids[read_u16(payload, 4)] += 1
        elif kind in (0x12, 0x13, 0x14) and len(payload) >= 6:
            trace_ids[read_u16(payload, 4)] += 1
        if kind == 0x11 and len(payload) >= 9:
            trace_statuses[payload[8]] += 1
        if kind == 0x05 and len(payload) >= 8:
            status_drop_counts.append(read_u16(payload, 6))
    print(f"port={port} baud={baud} seconds={elapsed:.3f} bytes={byte_count} "
          f"rate={byte_count/elapsed:.1f}B/s frames={len(decoder.frames)}")
    print("types=" + ", ".join(f"{name}:{count}" for name, count in sorted(counts.items())))
    print("trace_ids=" + ", ".join(
        f"0x{trace_id:04x}:{count}" for trace_id, count in sorted(trace_ids.items())))
    print("trace_end_statuses=" + ", ".join(
        f"{status}:{count}" for status, count in sorted(trace_statuses.items())))
    if status_drop_counts:
        print(f"status_drop_count_first={status_drop_counts[0]} "
              f"last={status_drop_counts[-1]} max={max(status_drop_counts)}")
    print(f"checksum_errors={decoder.checksum_errors} version_errors={decoder.version_errors} "
          f"initial_sync_drops={decoder.sync_drops}")
    for index, raw in enumerate(decoder.bad_frames):
        print(f"bad_frame[{index}]={raw.hex()}")
    if len(decoder.frames) < minimum:
        raise RuntimeError(f"only {len(decoder.frames)} valid frames, expected at least {minimum}")
    if decoder.checksum_errors or decoder.version_errors:
        raise RuntimeError("UART protocol errors detected")
    print("PASS: UART YiFPGA frame validation")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--minimum-frames", type=int, default=10)
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--monitor-read-address", type=lambda value: int(value, 0))
    parser.add_argument("--monitor-timeout", type=float, default=2.0)
    parser.add_argument("--monitor-safe-suite", action="store_true")
    parser.add_argument("--monitor-control-suite", action="store_true")
    parser.add_argument("--monitor-soak-duration", type=float)
    parser.add_argument("--monitor-soak-interval", type=float, default=1.0)
    parser.add_argument("--profiler-soak-duration", type=float)
    args = parser.parse_args()
    if args.profiler_soak_duration is not None:
        profiler_soak(args.port, args.baud, args.monitor_timeout,
                      args.profiler_soak_duration)
    elif args.monitor_soak_duration is not None:
        monitor_soak(args.port, args.baud, args.monitor_timeout,
                     args.monitor_soak_duration, args.monitor_soak_interval)
    elif args.monitor_control_suite:
        monitor_control_suite(args.port, args.baud, args.monitor_timeout)
    elif args.monitor_safe_suite:
        monitor_safe_suite(args.port, args.baud, args.monitor_timeout)
    elif args.monitor_read_address is None:
        validate(args.port, args.baud, args.duration, args.minimum_frames, args.capture)
    else:
        monitor_read(args.port, args.baud, args.monitor_read_address, args.monitor_timeout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
