#!/usr/bin/env python3
"""M26 UART Logic Analyzer validator. Run --self-test before opening hardware."""

import argparse
import os
import select
import termios
import time

SOF, VERSION = 0xA5, 0x01
READ_REQ, READ_RESP, WRITE_REQ, WRITE_RESP = 0x20, 0x21, 0x22, 0x23
LA_HEADER, LA_DATA, LA_STATUS, LA_TRIGGER = 0x40, 0x41, 0x42, 0x43
LA_ID = 0x0060
LA_VERSION = 0x0064
LA_CONTROL = 0x0068
LA_STATUS_REG = 0x006C
LA_DIVISOR = 0x0070
LA_DEPTH = 0x0074
LA_PRETRIGGER = 0x0078
LA_TRIGGER_MODE = 0x007C
LA_TRIGGER_CHANNEL = 0x0080
LA_TRIGGER_VALUE = 0x0084
LA_TRIGGER_MASK = 0x0088
LA_COMMAND = 0x008C
LA_CAPTURE_ID = 0x0090
LA_CHANNEL_MASK = 0x0094
EXPECTED_LA_ID = 0x4F464C41


class PosixSerial:
    """Small pyserial-compatible adapter for the release validator."""

    def __init__(self, port, baud, timeout=0.05, write_timeout=1):
        if baud != 115200:
            raise ValueError("POSIX fallback currently supports 115200 baud")
        self.port = port
        self.timeout = timeout
        self.write_timeout = write_timeout
        self.fd = None

    def __enter__(self):
        self.fd = os.open(self.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = termios.B115200
        attrs[5] = termios.B115200
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def reset_input_buffer(self):
        termios.tcflush(self.fd, termios.TCIFLUSH)

    def read(self, size):
        readable, _, _ = select.select([self.fd], [], [], self.timeout)
        if not readable:
            return b""
        return os.read(self.fd, size)

    def write(self, data):
        view = memoryview(data)
        deadline = time.monotonic() + self.write_timeout
        while view:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("serial write timeout")
            _, writable, _ = select.select([], [self.fd], [], remaining)
            if not writable:
                continue
            view = view[os.write(self.fd, view):]
        return len(data)


def u16(value):
    return bytes((value & 0xFF, (value >> 8) & 0xFF))


def u32(value):
    return bytes((value >> shift) & 0xFF for shift in (0, 8, 16, 24))


def read_u16(data, offset=0):
    return data[offset] | (data[offset + 1] << 8)


def read_u32(data, offset=0):
    return sum(data[offset + index] << (8 * index) for index in range(4))


def frame(msg_type, payload=b""):
    body = bytes((VERSION, msg_type, len(payload))) + payload
    checksum = 0
    for byte in body:
        checksum ^= byte
    return bytes((SOF,)) + body + bytes((checksum,))


def monitor_read(seq, address):
    return frame(READ_REQ, u16(seq) + u16(address) + b"\x04")


def monitor_write(seq, address, value, mask=0xFFFFFFFF):
    return frame(WRITE_REQ, u16(seq) + u16(address) + b"\x04" + u32(value) + u32(mask))


class Decoder:
    def __init__(self):
        self.buffer = bytearray()
        self.checksum_errors = 0

    def feed(self, data):
        self.buffer.extend(data)
        result = []
        while True:
            while self.buffer and self.buffer[0] != SOF:
                del self.buffer[0]
            if len(self.buffer) < 5:
                break
            length = self.buffer[3]
            total = length + 5
            if len(self.buffer) < total:
                break
            raw = bytes(self.buffer[:total])
            del self.buffer[:total]
            checksum = 0
            for byte in raw[1:-1]:
                checksum ^= byte
            if checksum != raw[-1]:
                self.checksum_errors += 1
                continue
            result.append((raw[2], raw[4:-1]))
        return result


def self_test():
    decoder = Decoder()
    request = monitor_write(7, LA_COMMAND, 1)
    assert request[0] == SOF and request[2] == WRITE_REQ and request[3] == 13
    response = frame(READ_RESP, u32(10) + u16(3) + u16(LA_ID) + b"\x00\x04" + u32(EXPECTED_LA_ID))
    assert decoder.feed(response[:4]) == []
    decoded = decoder.feed(response[4:])
    assert decoded[0][0] == READ_RESP and read_u32(decoded[0][1], 10) == EXPECTED_LA_ID
    bad = bytearray(frame(LA_STATUS, bytes(20)))
    bad[-1] ^= 1
    assert decoder.feed(bad) == [] and decoder.checksum_errors == 1
    print("PASS: YiFPGA Logic Analyzer validator self-test passed")


class Link:
    def __init__(self, serial_port):
        self.serial = serial_port
        self.decoder = Decoder()
        self.seq = 1
        self.la_frames = []
        self.frame_counts = {}
        self.status_drop_first = None
        self.status_drop_last = None
        self.status_drop_max = 0
        self.la_overflow_frames = 0
        self.la_malformed = 0

    def observe(self, frames):
        for msg_type, payload in frames:
            self.frame_counts[msg_type] = self.frame_counts.get(msg_type, 0) + 1
            if msg_type in (LA_HEADER, LA_DATA, LA_STATUS, LA_TRIGGER):
                self.la_frames.append((msg_type, payload))
            if msg_type == 0x05 and len(payload) >= 8:
                drop_count = read_u16(payload, 6)
                if self.status_drop_first is None:
                    self.status_drop_first = drop_count
                self.status_drop_last = drop_count
                self.status_drop_max = max(self.status_drop_max, drop_count)
            elif msg_type == LA_HEADER:
                if len(payload) != 24:
                    self.la_malformed += 1
                elif read_u16(payload, 14) & 0x0008:
                    self.la_overflow_frames += 1
            elif msg_type == LA_STATUS:
                if len(payload) != 20:
                    self.la_malformed += 1
                elif read_u32(payload, 16) & 0x0008:
                    self.la_overflow_frames += 1

    def transact(self, request, expected_type, seq, timeout=2.0):
        self.serial.write(request)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            matched_payload = None
            frames = self.decoder.feed(self.serial.read(256))
            self.observe(frames)
            for msg_type, payload in frames:
                if msg_type == expected_type and len(payload) >= 6 and read_u16(payload, 4) == seq:
                    if payload[8] != 0:
                        raise RuntimeError(f"Monitor status {payload[8]} for sequence {seq}")
                    matched_payload = payload
            if matched_payload is not None:
                return matched_payload
        raise TimeoutError(f"response timeout for sequence {seq}")

    def read_reg(self, address):
        seq = self.seq
        self.seq += 1
        payload = self.transact(monitor_read(seq, address), READ_RESP, seq)
        return read_u32(payload, 10)

    def write_reg(self, address, value, mask=0xFFFFFFFF):
        seq = self.seq
        self.seq += 1
        self.transact(monitor_write(seq, address, value, mask), WRITE_RESP, seq)

    def collect_capture(self, timeout=30.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.observe(self.decoder.feed(self.serial.read(256)))
            kinds = {kind for kind, _ in self.la_frames}
            if LA_HEADER in kinds and LA_DATA in kinds and LA_STATUS in kinds and LA_TRIGGER in kinds:
                return
        counts = {kind: sum(item[0] == kind for item in self.la_frames)
                  for kind in (LA_HEADER, LA_DATA, LA_STATUS, LA_TRIGGER)}
        raise TimeoutError(
            "LA header/trigger/data/status capture frames not received; "
            f"counts={counts} checksum_errors={self.decoder.checksum_errors} "
            f"buffered_bytes={len(self.decoder.buffer)}"
        )


def validate(port, baud, soak_duration=0, soak_interval=30):
    try:
        import serial
        serial_port = serial.Serial(port, baud, timeout=0.05, write_timeout=1)
    except ImportError:
        if os.name != "posix":
            raise RuntimeError("pyserial is required on this platform")
        serial_port = PosixSerial(port, baud, timeout=0.05, write_timeout=1)

    with serial_port as uart:
        uart.reset_input_buffer()
        link = Link(uart)
        la_id = link.read_reg(LA_ID)
        version = link.read_reg(LA_VERSION)
        if la_id != EXPECTED_LA_ID:
            raise RuntimeError(f"unexpected LA_ID 0x{la_id:08X}")
        config_addresses = (LA_CONTROL, LA_DIVISOR, LA_DEPTH, LA_PRETRIGGER,
                            LA_TRIGGER_MODE, LA_TRIGGER_CHANNEL,
                            LA_TRIGGER_VALUE, LA_TRIGGER_MASK, LA_CHANNEL_MASK)
        originals = {address: link.read_reg(address) for address in config_addresses}
        profiler_addresses = (0x0048, 0x004C)
        profiler_originals = {
            address: link.read_reg(address) for address in profiler_addresses
        }
        demo_period_original = link.read_reg(0x0010)

        def capture_once():
            link.la_frames.clear()
            # Profiler remains active throughout the soak, but its snapshot
            # burst is paused for the short LA readout transaction so both
            # producers cannot pin the shared 115200-baud FIFO watermark.
            link.write_reg(0x0048, 0)
            drain_deadline = time.monotonic() + 1
            while time.monotonic() < drain_deadline:
                link.observe(link.decoder.feed(uart.read(512)))
            try:
                link.write_reg(LA_COMMAND, 0x1)   # arm
                link.write_reg(LA_COMMAND, 0x8)   # deterministic force trigger
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    if link.read_reg(LA_STATUS_REG) & 0x8:
                        break
                    time.sleep(0.05)
                else:
                    raise TimeoutError("LA capture did not reach done")
                link.write_reg(LA_COMMAND, 0x10)  # readout
                link.collect_capture()
            finally:
                link.write_reg(0x0048, 1)
            capture_id = link.read_reg(LA_CAPTURE_ID)
            counts = {kind: sum(item[0] == kind for item in link.la_frames)
                      for kind in (LA_HEADER, LA_DATA, LA_STATUS, LA_TRIGGER)}
            return capture_id, counts

        try:
            # Keep Profiler active at a UART-safe coexistence rate. The Edge
            # demo may leave it at 100,000 cycles, which overloads 115200 baud.
            link.write_reg(0x0048, 0)
            link.write_reg(0x004C, 100_000_000)
            link.write_reg(0x0048, 1)
            # Keep the board demo below UART capacity while preserving active
            # Trace/Profiler coexistence. Restore this setting in finally.
            link.write_reg(0x0010, 100_000_000)
            settle_deadline = time.monotonic() + 5
            while time.monotonic() < settle_deadline:
                link.observe(link.decoder.feed(uart.read(512)))
            for address, value in ((LA_DIVISOR, 50_000), (LA_DEPTH, 64),
                                   (LA_PRETRIGGER, 0), (LA_TRIGGER_MODE, 0),
                                   (LA_TRIGGER_CHANNEL, 2), (LA_TRIGGER_VALUE, 1),
                                   (LA_TRIGGER_MASK, 1), (LA_CHANNEL_MASK, 0xFFFFFFFF),
                                   (LA_CONTROL, 0x1)):
                link.write_reg(address, value)
                if link.read_reg(address) != value:
                    raise RuntimeError(f"register 0x{address:04X} readback mismatch")
            capture_before = link.read_reg(LA_CAPTURE_ID)
            capture_first, counts_first = capture_once()
            link.write_reg(LA_COMMAND, 0x2)   # stop
            link.write_reg(LA_COMMAND, 0x4)   # clear
            capture_second, counts_second = capture_once()
            if not (capture_before < capture_first < capture_second):
                raise RuntimeError(
                    "capture_id did not increment across clear/re-arm: "
                    f"{capture_before}->{capture_first}->{capture_second}")
            captures = 2
            last_capture = capture_second
            # Initial configuration and status polling are intentionally a
            # command burst. Drain their queued Status frames before defining
            # the steady-state drop-count baseline.
            drain_deadline = time.monotonic() + 3
            while time.monotonic() < drain_deadline:
                link.observe(link.decoder.feed(uart.read(512)))
            link.status_drop_first = None
            link.status_drop_last = None
            link.status_drop_max = 0
            baseline_deadline = time.monotonic() + 3
            while time.monotonic() < baseline_deadline:
                link.observe(link.decoder.feed(uart.read(512)))
            started = time.monotonic()
            next_capture = time.monotonic() + soak_interval
            next_progress = started + 300
            while soak_duration > 0 and time.monotonic() - started < soak_duration:
                link.observe(link.decoder.feed(uart.read(512)))
                now = time.monotonic()
                if now >= next_capture:
                    link.write_reg(LA_COMMAND, 0x2)
                    link.write_reg(LA_COMMAND, 0x4)
                    capture_id, _ = capture_once()
                    if capture_id <= last_capture:
                        raise RuntimeError(
                            f"capture_id did not increment: {last_capture}->{capture_id}")
                    last_capture = capture_id
                    captures += 1
                    next_capture += soak_interval
                if now >= next_progress:
                    print(f"la_soak_progress seconds={now-started:.1f} "
                          f"captures={captures} capture_id={last_capture} "
                          f"checksum_errors={link.decoder.checksum_errors} "
                          f"drop_first={link.status_drop_first} "
                          f"drop_last={link.status_drop_last} "
                          f"overflow_frames={link.la_overflow_frames} "
                          f"malformed={link.la_malformed}", flush=True)
                    next_progress += 300
            if link.decoder.checksum_errors:
                raise RuntimeError("checksum errors during LA validation")
            if (link.status_drop_first is not None and
                    link.status_drop_last != link.status_drop_first):
                raise RuntimeError(
                    "Debug Core drop_count grew during LA validation: "
                    f"{link.status_drop_first}->{link.status_drop_last}")
            if soak_duration > 0 and link.frame_counts.get(0x30, 0) == 0:
                raise RuntimeError("no Profiler snapshots observed during LA coexistence soak")
            if link.la_overflow_frames:
                raise RuntimeError(f"LA overflow observed in {link.la_overflow_frames} frames")
            if link.la_malformed:
                raise RuntimeError(f"malformed LA frames observed: {link.la_malformed}")
            steady_drop_first = link.status_drop_first
            steady_drop_last = link.status_drop_last
            steady_drop_max = link.status_drop_max
            steady_profiler_snapshots = link.frame_counts.get(0x30, 0)
        finally:
            link.write_reg(LA_COMMAND, 0x2)   # stop
            link.write_reg(LA_COMMAND, 0x4)   # clear
            for address in config_addresses:
                link.write_reg(address, originals[address])
            link.write_reg(0x0048, 0)
            link.write_reg(0x004C, profiler_originals[0x004C])
            link.write_reg(0x0048, profiler_originals[0x0048])
            link.write_reg(0x0010, demo_period_original)
            print("restore LA and Profiler control/configuration: PASS")
        print("PASS: YiFPGA Logic Analyzer board validation passed; "
              f"LA_VERSION=0x{version:08X} capture_ids="
              f"{capture_before}->{capture_first}->{capture_second} "
              f"first_frames={counts_first} second_frames={counts_second} "
              f"captures={captures} final_capture_id={last_capture} "
              f"checksum_errors={link.decoder.checksum_errors} "
              f"drop_first={steady_drop_first} "
              f"drop_last={steady_drop_last} drop_max={steady_drop_max} "
              f"profiler_snapshots={steady_profiler_snapshots} "
              f"overflow_frames={link.la_overflow_frames} malformed={link.la_malformed}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--port")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--soak-duration", type=float, default=0)
    parser.add_argument("--soak-interval", type=float, default=30)
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.port:
        self_test()
        validate(args.port, args.baud, args.soak_duration, args.soak_interval)
    else:
        parser.error("use --self-test or --port COMx")


if __name__ == "__main__":
    main()
