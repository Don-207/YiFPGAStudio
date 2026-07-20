#!/usr/bin/env python3

SOF = 0xA5
VERSION = 0x01
MAX_PAYLOAD = 32

TYPES = {
    0x01: "HEARTBEAT",
    0x02: "DEBUG_PRINT",
    0x03: "EVENT",
    0x04: "WATCH",
    0x05: "STATUS",
    0x10: "TRACE_SPAN_BEGIN",
    0x11: "TRACE_SPAN_END",
    0x12: "TRACE_MARK",
    0x13: "TRACE_VALUE",
    0x14: "TRACE_DROP",
    0x20: "MONITOR_READ_REQ",
    0x21: "MONITOR_READ_RESP",
    0x22: "MONITOR_WRITE_REQ",
    0x23: "MONITOR_WRITE_RESP",
    0x24: "MONITOR_BURST_READ_REQ",
    0x25: "MONITOR_BURST_READ_RESP",
    0x26: "MONITOR_POLL_CFG",
    0x27: "MONITOR_EVENT",
    0x28: "MONITOR_DISCOVER_REQ",
    0x29: "MONITOR_DISCOVER_RESP",
    0x30: "PROFILER_SNAPSHOT",
    0x31: "PROFILER_ALERT",
    0x32: "PROFILER_COUNTER",
    0x33: "PROFILER_LATENCY",
    0x34: "PROFILER_DISCOVER",
    0x35: "PROFILER_CFG_REQ",
    0x36: "PROFILER_CFG_RESP",
    0x40: "LA_CAPTURE_HEADER",
    0x41: "LA_SAMPLE_DATA",
    0x42: "LA_CAPTURE_STATUS",
    0x43: "LA_TRIGGER_EVENT",
    0x44: "LA_CHANNEL_MANIFEST",
    0x45: "LA_CFG_REQ",
    0x46: "LA_CFG_RESP",
}

MONITOR_OK = 0
MONITOR_DENIED = 2
PROFILER_FLAG_VALID = 1 << 0
PROFILER_FLAG_SATURATED = 1 << 1
PROFILER_FLAG_ALERT = 1 << 4
LA_FLAG_VALID = 1 << 0
LA_FLAG_TRIGGERED = 1 << 1

PROFILER_METRICS = {
    0x0001: {
        "name": "AXIS_DEMO_THROUGHPUT",
        "type": "Throughput",
        "unit": "bytes/window",
    },
    0x0101: {
        "name": "FIFO_DEMO_LEVEL",
        "type": "FIFO",
        "unit": "level",
    },
    0x0201: {
        "name": "DEMO_LATENCY",
        "type": "Latency",
        "unit": "cycles",
    },
    0x0301: {
        "name": "FRAME_RATE",
        "type": "Frame Rate",
        "unit": "frames/window",
    },
}


class Parser:
    def __init__(self):
        self.rx = []
        self.frames = []
        self.checksum_errors = 0
        self.sync_drops = 0
        self.unknown_frames = 0
        self.trace = {
            "spans": [],
            "open_spans": {},
            "marks": [],
            "values": [],
            "drops": [],
        }
        self.monitor = {
            "registers": {},
            "pending": {},
            "next_seq": 1,
            "errors": [],
            "history": [],
        }
        self.profiler = {
            "metrics": PROFILER_METRICS.copy(),
            "latest": {},
            "history": {},
            "alerts": [],
            "counters": {
                "snapshots": 0,
                "alerts": 0,
                "overflow_snapshots": 0,
                "malformed": 0,
            },
        }
        self.logic_analyzer = {
            "captures": {},
            "latest_capture_id": None,
            "counters": {
                "headers": 0,
                "samples": 0,
                "statuses": 0,
                "trigger_events": 0,
                "malformed": 0,
                "missing_chunks": 0,
                "out_of_order_chunks": 0,
                "dropped_frames": 0,
            },
        }

    def feed(self, data):
        self.rx.extend(data)
        self._parse()

    def _parse(self):
        while len(self.rx) >= 5:
            if self.rx[0] != SOF:
                self.rx.pop(0)
                self.sync_drops += 1
                continue

            length = self.rx[3]
            if length > MAX_PAYLOAD:
                self.rx.pop(0)
                self.sync_drops += 1
                continue

            total = 5 + length
            if len(self.rx) < total:
                return

            raw = self.rx[:total]
            del self.rx[:total]

            actual = xor(raw[1:-1])
            expected = raw[-1]
            if actual != expected:
                self.checksum_errors += 1
                continue

            version = raw[1]
            msg_type = raw[2]
            payload = raw[4:-1]
            if version != VERSION or msg_type not in TYPES:
                self.unknown_frames += 1

            self.frames.append((version, msg_type, payload, raw))
            if version == VERSION:
                self._decode_trace(msg_type, payload)
                self._decode_monitor(msg_type, payload)
                self._decode_profiler(msg_type, payload)
                self._decode_logic_analyzer(msg_type, payload)

    def _decode_trace(self, msg_type, payload):
        if msg_type == 0x10 and len(payload) >= 12:
            timestamp = read_u32(payload, 0)
            trace_id = read_u16(payload, 4)
            instance_id = read_u16(payload, 6)
            arg0 = read_u32(payload, 8)
            self.trace["open_spans"][(trace_id, instance_id)] = {
                "timestamp": timestamp,
                "arg0": arg0,
            }
        elif msg_type == 0x11 and len(payload) >= 13:
            timestamp = read_u32(payload, 0)
            trace_id = read_u16(payload, 4)
            instance_id = read_u16(payload, 6)
            status = payload[8]
            arg0 = read_u32(payload, 9)
            begin = self.trace["open_spans"].pop((trace_id, instance_id), None)
            self.trace["spans"].append({
                "trace_id": trace_id,
                "instance_id": instance_id,
                "start_timestamp": begin["timestamp"] if begin else None,
                "end_timestamp": timestamp,
                "duration": ((timestamp - begin["timestamp"]) & 0xFFFFFFFF)
                if begin else None,
                "status": status,
                "start_arg0": begin["arg0"] if begin else None,
                "end_arg0": arg0,
                "orphan": begin is None,
            })
        elif msg_type == 0x12 and len(payload) >= 11:
            self.trace["marks"].append({
                "timestamp": read_u32(payload, 0),
                "trace_id": read_u16(payload, 4),
                "level": payload[6],
                "arg0": read_u32(payload, 7),
            })
        elif msg_type == 0x13 and len(payload) >= 12:
            self.trace["values"].append({
                "timestamp": read_u32(payload, 0),
                "trace_id": read_u16(payload, 4),
                "value_id": read_u16(payload, 6),
                "value": read_u32(payload, 8),
            })
        elif msg_type == 0x14 and len(payload) >= 10:
            self.trace["drops"].append({
                "timestamp": read_u32(payload, 0),
                "trace_id": read_u16(payload, 4),
                "drop_count": read_u32(payload, 6),
            })

    def _decode_monitor(self, msg_type, payload):
        if msg_type == 0x21 and len(payload) >= 14:
            timestamp = read_u32(payload, 0)
            seq = read_u16(payload, 4)
            addr = read_u16(payload, 6)
            status = payload[8]
            width = payload[9]
            value = read_u32(payload, 10)
            pending = self.monitor["pending"].pop(seq, None)
            row = {
                "kind": "read",
                "timestamp": timestamp,
                "seq": seq,
                "addr": addr,
                "status": status,
                "width": width,
                "value": value,
                "unknown_seq": pending is None,
            }
            self.monitor["history"].append(row)
            if status == MONITOR_OK:
                self.monitor["registers"][addr] = {
                    "value": value,
                    "timestamp": timestamp,
                    "status": status,
                    "width": width,
                }
            if pending is None or status != MONITOR_OK:
                self.monitor["errors"].append(row)
        elif msg_type == 0x23 and len(payload) >= 17:
            timestamp = read_u32(payload, 0)
            seq = read_u16(payload, 4)
            addr = read_u16(payload, 6)
            status = payload[8]
            old_value = read_u32(payload, 9)
            new_value = read_u32(payload, 13)
            pending = self.monitor["pending"].pop(seq, None)
            row = {
                "kind": "write",
                "timestamp": timestamp,
                "seq": seq,
                "addr": addr,
                "status": status,
                "old_value": old_value,
                "new_value": new_value,
                "unknown_seq": pending is None,
            }
            self.monitor["history"].append(row)
            if status == MONITOR_OK:
                self.monitor["registers"][addr] = {
                    "value": new_value,
                    "timestamp": timestamp,
                    "status": status,
                    "width": pending["width"] if pending else 4,
                }
            if pending is None or status != MONITOR_OK:
                self.monitor["errors"].append(row)

    def _decode_profiler(self, msg_type, payload):
        if msg_type == 0x30:
            if len(payload) != 32:
                self.profiler["counters"]["malformed"] += 1
                return
            timestamp = read_u32(payload, 0)
            metric_id = read_u16(payload, 4)
            flags = read_u16(payload, 6)
            sample_cycles = read_u32(payload, 8)
            value0 = read_u32(payload, 12)
            value1 = read_u32(payload, 16)
            value2 = read_u32(payload, 20)
            value3 = read_u32(payload, 24)
            overflow_count = read_u16(payload, 28)
            reserved = read_u16(payload, 30)
            metric = self.profiler["metrics"].get(metric_id, {
                "name": f"metric_0x{metric_id:04X}",
                "type": "Unknown",
                "unit": "raw",
            })
            row = {
                "kind": "profiler_snapshot",
                "timestamp": timestamp,
                "metric_id": metric_id,
                "metric_name": metric["name"],
                "metric_type": metric["type"],
                "unit": metric["unit"],
                "flags": flags,
                "sample_cycles": sample_cycles,
                "value0": value0,
                "value1": value1,
                "value2": value2,
                "value3": value3,
                "overflow_count": overflow_count,
                "reserved": reserved,
            }
            self.profiler["counters"]["snapshots"] += 1
            if flags & PROFILER_FLAG_SATURATED or overflow_count:
                self.profiler["counters"]["overflow_snapshots"] += 1
            self.profiler["latest"][metric_id] = row
            self.profiler["history"].setdefault(metric_id, []).append(row)
        elif msg_type == 0x31:
            if len(payload) != 16:
                self.profiler["counters"]["malformed"] += 1
                return
            metric_id = read_u16(payload, 4)
            metric = self.profiler["metrics"].get(metric_id, {
                "name": f"metric_0x{metric_id:04X}",
                "type": "Unknown",
                "unit": "raw",
            })
            row = {
                "kind": "profiler_alert",
                "timestamp": read_u32(payload, 0),
                "metric_id": metric_id,
                "metric_name": metric["name"],
                "metric_type": metric["type"],
                "level": payload[6],
                "code": payload[7],
                "arg0": read_u32(payload, 8),
                "arg1": read_u32(payload, 12),
            }
            self.profiler["counters"]["alerts"] += 1
            self.profiler["alerts"].append(row)

    def _decode_logic_analyzer(self, msg_type, payload):
        if msg_type == 0x40:
            if len(payload) != 24:
                self.logic_analyzer["counters"]["malformed"] += 1
                return
            capture_id = read_u32(payload, 0)
            header = {
                "kind": "la_capture_header",
                "capture_id": capture_id,
                "timestamp": read_u32(payload, 4),
                "sample_width_bits": read_u16(payload, 8),
                "sample_count": read_u16(payload, 10),
                "trigger_index": read_u16(payload, 12),
                "flags": read_u16(payload, 14),
                "sample_period_cycles": read_u32(payload, 16),
                "channel_count": read_u16(payload, 20),
                "reserved": read_u16(payload, 22),
            }
            capture = self._la_capture(capture_id)
            capture["header"] = header
            capture["samples"] = [None] * header["sample_count"]
            self.logic_analyzer["latest_capture_id"] = capture_id
            self.logic_analyzer["counters"]["headers"] += 1
        elif msg_type == 0x41:
            if len(payload) != 32:
                self.logic_analyzer["counters"]["malformed"] += 1
                return
            capture_id = read_u32(payload, 0)
            chunk_index = read_u16(payload, 4)
            first_sample_index = read_u16(payload, 6)
            sample_bytes = payload[8]
            sample_count = payload[9]
            flags = read_u16(payload, 10)
            if sample_bytes not in (1, 2, 4) or sample_count * sample_bytes > 20:
                self.logic_analyzer["counters"]["malformed"] += 1
                return
            capture = self._la_capture(capture_id)
            if capture["header"] is None:
                capture["errors"].append("missing_header")
            if chunk_index in capture["chunks"]:
                capture["errors"].append("overlap")
                self.logic_analyzer["counters"]["dropped_frames"] += 1
                return
            previous_indexes = sorted(capture["chunks"])
            if previous_indexes and chunk_index < previous_indexes[-1]:
                self.logic_analyzer["counters"]["out_of_order_chunks"] += 1
            if previous_indexes and chunk_index > previous_indexes[-1] + 1:
                missing = chunk_index - previous_indexes[-1] - 1
                self.logic_analyzer["counters"]["missing_chunks"] += missing
                capture["missing_ranges"].append((previous_indexes[-1] + 1, chunk_index - 1))
            if not previous_indexes and chunk_index > 0:
                self.logic_analyzer["counters"]["missing_chunks"] += chunk_index
                capture["missing_ranges"].append((0, chunk_index - 1))

            data = payload[12:32]
            values = []
            for index in range(sample_count):
                offset = index * sample_bytes
                value = 0
                for byte_index in range(sample_bytes):
                    value |= data[offset + byte_index] << (8 * byte_index)
                values.append(value)
                sample_index = first_sample_index + index
                while len(capture["samples"]) <= sample_index:
                    capture["samples"].append(None)
                if capture["samples"][sample_index] is not None:
                    capture["errors"].append("overlap")
                    self.logic_analyzer["counters"]["dropped_frames"] += 1
                else:
                    capture["samples"][sample_index] = value
            capture["chunks"][chunk_index] = {
                "kind": "la_sample",
                "capture_id": capture_id,
                "chunk_index": chunk_index,
                "first_sample_index": first_sample_index,
                "sample_bytes": sample_bytes,
                "sample_count": sample_count,
                "flags": flags,
                "values": values,
            }
            self.logic_analyzer["latest_capture_id"] = capture_id
            self.logic_analyzer["counters"]["samples"] += 1
            header = capture["header"]
            if header and all(sample is not None for sample in capture["samples"][:header["sample_count"]]):
                capture["complete"] = True
        elif msg_type == 0x42:
            if len(payload) != 20:
                self.logic_analyzer["counters"]["malformed"] += 1
                return
            capture_id = read_u32(payload, 4)
            status = {
                "kind": "la_status",
                "timestamp": read_u32(payload, 0),
                "capture_id": capture_id,
                "state": payload[8],
                "error": payload[9],
                "samples_written": read_u16(payload, 10),
                "chunks_sent": read_u16(payload, 12),
                "chunks_total": read_u16(payload, 14),
                "status_flags": read_u32(payload, 16),
            }
            capture = self._la_capture(capture_id)
            capture["status"] = status
            self.logic_analyzer["latest_capture_id"] = capture_id
            self.logic_analyzer["counters"]["statuses"] += 1
        elif msg_type == 0x43:
            if len(payload) != 20:
                self.logic_analyzer["counters"]["malformed"] += 1
                return
            capture_id = read_u32(payload, 4)
            event = {
                "kind": "la_trigger_event",
                "timestamp": read_u32(payload, 0),
                "capture_id": capture_id,
                "trigger_index": read_u16(payload, 8),
                "trigger_channel": read_u16(payload, 10),
                "sample_value": read_u32(payload, 12),
                "trigger_value": read_u32(payload, 16),
            }
            capture = self._la_capture(capture_id)
            capture["trigger_event"] = event
            self.logic_analyzer["latest_capture_id"] = capture_id
            self.logic_analyzer["counters"]["trigger_events"] += 1
        elif 0x40 <= msg_type <= 0x4F:
            self.logic_analyzer["counters"]["malformed"] += 1

    def _la_capture(self, capture_id):
        capture = self.logic_analyzer["captures"].get(capture_id)
        if capture is None:
            capture = {
                "header": None,
                "status": None,
                "trigger_event": None,
                "chunks": {},
                "samples": [],
                "missing_ranges": [],
                "complete": False,
                "errors": [],
            }
            self.logic_analyzer["captures"][capture_id] = capture
        return capture

    def monitor_read_request(self, addr, width=4):
        seq = self._next_monitor_seq()
        payload = [*u16(seq), *u16(addr), width]
        self.monitor["pending"][seq] = {
            "op": "read",
            "addr": addr,
            "width": width,
        }
        return seq, frame(0x20, payload)

    def monitor_write_request(self, addr, value, mask=0xFFFFFFFF, width=4):
        seq = self._next_monitor_seq()
        payload = [*u16(seq), *u16(addr), width, *u32(value), *u32(mask)]
        self.monitor["pending"][seq] = {
            "op": "write",
            "addr": addr,
            "width": width,
            "value": value,
            "mask": mask,
        }
        return seq, frame(0x22, payload)

    def monitor_expire(self, seq):
        pending = self.monitor["pending"].pop(seq, None)
        if pending:
            row = {"kind": "timeout", "seq": seq, **pending}
            self.monitor["errors"].append(row)
            self.monitor["history"].append(row)
        return pending is not None

    def _next_monitor_seq(self):
        seq = self.monitor["next_seq"]
        self.monitor["next_seq"] = 1 if seq == 0xFFFF else seq + 1
        return seq


def xor(values):
    result = 0
    for value in values:
        result ^= value
    return result & 0xFF


def frame(msg_type, payload):
    body = [VERSION, msg_type, len(payload), *payload]
    return [SOF, *body, xor(body)]


def u16(value):
    return [value & 0xFF, (value >> 8) & 0xFF]


def u32(value):
    return [
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
    ]


def read_u16(payload, offset):
    return payload[offset] | (payload[offset + 1] << 8)


def read_u32(payload, offset):
    return (
        payload[offset]
        | (payload[offset + 1] << 8)
        | (payload[offset + 2] << 16)
        | (payload[offset + 3] << 24)
    )


def profiler_snapshot_payload(
    timestamp,
    metric_id,
    flags,
    sample_cycles,
    value0,
    value1,
    value2,
    value3,
    overflow_count=0,
    reserved=0,
):
    return [
        *u32(timestamp),
        *u16(metric_id),
        *u16(flags),
        *u32(sample_cycles),
        *u32(value0),
        *u32(value1),
        *u32(value2),
        *u32(value3),
        *u16(overflow_count),
        *u16(reserved),
    ]


def profiler_alert_payload(timestamp, metric_id, level, code, arg0, arg1):
    return [
        *u32(timestamp),
        *u16(metric_id),
        level,
        code,
        *u32(arg0),
        *u32(arg1),
    ]


def la_capture_header_payload(
    capture_id,
    timestamp,
    sample_width_bits,
    sample_count,
    trigger_index,
    flags,
    sample_period_cycles,
    channel_count,
    reserved=0,
):
    return [
        *u32(capture_id),
        *u32(timestamp),
        *u16(sample_width_bits),
        *u16(sample_count),
        *u16(trigger_index),
        *u16(flags),
        *u32(sample_period_cycles),
        *u16(channel_count),
        *u16(reserved),
    ]


def la_sample_data_payload(capture_id, chunk_index, first_sample_index, sample_bytes, values, flags=0):
    data = []
    for value in values:
        for byte_index in range(sample_bytes):
            data.append((value >> (8 * byte_index)) & 0xFF)
    data = data[:20]
    data.extend([0] * (20 - len(data)))
    return [
        *u32(capture_id),
        *u16(chunk_index),
        *u16(first_sample_index),
        sample_bytes,
        len(values),
        *u16(flags),
        *data,
    ]


def la_capture_status_payload(timestamp, capture_id, state, error, samples_written, chunks_sent, chunks_total, status_flags):
    return [
        *u32(timestamp),
        *u32(capture_id),
        state,
        error,
        *u16(samples_written),
        *u16(chunks_sent),
        *u16(chunks_total),
        *u32(status_flags),
    ]


def la_trigger_event_payload(timestamp, capture_id, trigger_index, trigger_channel, sample_value, trigger_value):
    return [
        *u32(timestamp),
        *u32(capture_id),
        *u16(trigger_index),
        *u16(trigger_channel),
        *u32(sample_value),
        *u32(trigger_value),
    ]


def expect(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    event_payload = [
        *u32(0x0000000B),
        *u16(0x1001),
        0x01,
        *u32(0x12345678),
    ]
    event_frame = frame(0x03, event_payload)

    parser = Parser()
    parser.feed(event_frame[:4])
    expect(len(parser.frames) == 0, "partial frame should wait for more bytes")
    parser.feed(event_frame[4:])
    expect(len(parser.frames) == 1, "complete frame should decode")
    expect(parser.frames[0][1] == 0x03, "decoded type should be EVENT")
    expect(parser.frames[0][2] == event_payload, "decoded payload should match")

    bad = event_frame[:]
    bad[-1] ^= 0x55
    parser.feed(bad)
    expect(parser.checksum_errors == 1, "bad checksum should be counted")

    heartbeat = frame(0x01, u32(0x12345678))
    parser.feed([0x00, 0x11, *heartbeat])
    expect(parser.sync_drops == 2, "garbage before SOF should be dropped")
    expect(len(parser.frames) == 2, "parser should resync after garbage")

    unknown = frame(0x7F, [])
    parser.feed(unknown)
    expect(parser.unknown_frames == 1, "unknown type should be counted")

    trace_begin_payload = [
        *u32(100),
        *u16(0x0001),
        *u16(0x0042),
        *u32(0x00000010),
    ]
    trace_end_payload = [
        *u32(160),
        *u16(0x0001),
        *u16(0x0042),
        0x00,
        *u32(0x00000020),
    ]
    trace_mark_payload = [
        *u32(120),
        *u16(0x0003),
        0x02,
        *u32(0x00000080),
    ]
    trace_value_payload = [
        *u32(130),
        *u16(0x0003),
        *u16(0x0001),
        *u32(0x0000007C),
    ]
    trace_drop_payload = [
        *u32(140),
        *u16(0x0000),
        *u32(3),
    ]
    parser.feed(frame(0x10, trace_begin_payload))
    parser.feed(frame(0x12, trace_mark_payload))
    parser.feed(frame(0x13, trace_value_payload))
    parser.feed(frame(0x14, trace_drop_payload))
    parser.feed(frame(0x11, trace_end_payload))
    expect(parser.frames[-5][1] == 0x10, "trace begin should decode as known type")
    expect(parser.frames[-1][1] == 0x11, "trace end should decode as known type")
    expect(len(parser.trace["open_spans"]) == 0, "trace end should close the open span")
    expect(len(parser.trace["spans"]) == 1, "trace begin/end should produce one span")
    expect(parser.trace["spans"][0]["duration"] == 60, "trace span duration should be derived")
    expect(parser.trace["spans"][0]["status"] == 0, "trace span status should be preserved")
    expect(parser.trace["marks"][0]["level"] == 2, "trace mark level should decode")
    expect(parser.trace["values"][0]["value"] == 0x7C, "trace value should decode")
    expect(parser.trace["drops"][0]["drop_count"] == 3, "trace drop count should decode")

    wrap_begin = [*u32(0xFFFFFFF0), *u16(0x0001), *u16(0xBEEF), *u32(0)]
    wrap_end = [*u32(0x00000020), *u16(0x0001), *u16(0xBEEF), 0, *u32(0)]
    parser.feed(frame(0x10, wrap_begin))
    parser.feed(frame(0x11, wrap_end))
    expect(parser.trace["spans"][-1]["duration"] == 0x30,
           "trace duration should handle 32-bit timestamp wrap")

    orphan_end_payload = [
        *u32(200),
        *u16(0x0002),
        *u16(0x0001),
        0x03,
        *u32(0x0000DEAD),
    ]
    parser.feed(frame(0x11, orphan_end_payload))
    expect(parser.trace["spans"][-1]["orphan"], "unmatched trace end should be kept as orphan")
    expect(parser.trace["spans"][-1]["status"] == 3, "orphan trace status should be preserved")

    read_seq, read_req = parser.monitor_read_request(0x000C, 4)
    expect(read_req == frame(0x20, [*u16(read_seq), *u16(0x000C), 4]), "monitor read request frame should encode")
    write_seq, write_req = parser.monitor_write_request(0x000C, 0x00000005, 0x0000000F, 4)
    expect(write_req == frame(0x22, [*u16(write_seq), *u16(0x000C), 4, *u32(5), *u32(0x0F)]), "monitor write request frame should encode")
    expect(read_seq in parser.monitor["pending"], "monitor read should create pending entry")
    expect(write_seq in parser.monitor["pending"], "monitor write should create pending entry")

    read_resp_payload = [
        *u32(300),
        *u16(read_seq),
        *u16(0x000C),
        MONITOR_OK,
        4,
        *u32(0x00000005),
    ]
    parser.feed(frame(0x21, read_resp_payload))
    expect(read_seq not in parser.monitor["pending"], "monitor read response should clear pending entry")
    expect(parser.monitor["registers"][0x000C]["value"] == 5, "monitor read response should update register value")

    write_resp_payload = [
        *u32(310),
        *u16(write_seq),
        *u16(0x000C),
        MONITOR_OK,
        *u32(0x00000001),
        *u32(0x00000005),
    ]
    parser.feed(frame(0x23, write_resp_payload))
    expect(write_seq not in parser.monitor["pending"], "monitor write response should clear pending entry")
    expect(parser.monitor["registers"][0x000C]["value"] == 5, "monitor write response should update register value")

    parser.feed(frame(0x21, [*u32(320), *u16(0x7777), *u16(0x000C), MONITOR_OK, 4, *u32(0x99)]))
    expect(parser.monitor["errors"][-1]["unknown_seq"], "unknown monitor response seq should be recorded")

    denied_seq, _ = parser.monitor_write_request(0x0000, 0x12345678)
    parser.feed(frame(0x23, [*u32(330), *u16(denied_seq), *u16(0x0000), MONITOR_DENIED, *u32(0), *u32(0)]))
    expect(parser.monitor["errors"][-1]["status"] == MONITOR_DENIED, "monitor error status should be recorded")

    timeout_seq, _ = parser.monitor_read_request(0x0014)
    expect(parser.monitor_expire(timeout_seq), "monitor timeout should remove pending entry")
    expect(timeout_seq not in parser.monitor["pending"], "monitor timeout should clear pending entry")
    expect(parser.monitor["errors"][-1]["kind"] == "timeout", "monitor timeout should be recorded")

    parser.feed(frame(0x30, profiler_snapshot_payload(
        400,
        0x0001,
        PROFILER_FLAG_VALID,
        100000,
        8192,
        1024,
        1200,
        12,
    )))
    throughput = parser.profiler["latest"][0x0001]
    expect(throughput["metric_name"] == "AXIS_DEMO_THROUGHPUT", "profiler throughput metric name should map")
    expect(throughput["sample_cycles"] == 100000, "profiler sample cycles should decode")
    expect(throughput["value0"] == 8192, "profiler throughput value0 should decode")
    expect(throughput["value3"] == 12, "profiler throughput stall cycles should decode")

    parser.feed(frame(0x30, profiler_snapshot_payload(
        410,
        0x0101,
        PROFILER_FLAG_VALID | PROFILER_FLAG_SATURATED,
        100000,
        48,
        60,
        8,
        1,
        overflow_count=1,
    )))
    fifo = parser.profiler["latest"][0x0101]
    expect(fifo["value1"] == 60, "profiler FIFO max level should decode")
    expect(parser.profiler["counters"]["overflow_snapshots"] == 1, "profiler overflow snapshot should be counted")

    parser.feed(frame(0x30, profiler_snapshot_payload(
        420,
        0x0201,
        PROFILER_FLAG_VALID,
        100000,
        16,
        23,
        91,
        44,
    )))
    latency = parser.profiler["latest"][0x0201]
    expect(latency["value1"] == 23, "profiler latency min should decode")
    expect(latency["value2"] == 91, "profiler latency max should decode")
    expect(latency["value3"] == 44, "profiler latency avg should decode")

    parser.feed(frame(0x31, profiler_alert_payload(430, 0x0101, 2, 3, 60, 1)))
    expect(parser.profiler["alerts"][-1]["metric_id"] == 0x0101, "profiler alert metric should decode")
    expect(parser.profiler["alerts"][-1]["level"] == 2, "profiler alert level should decode")
    expect(parser.profiler["alerts"][-1]["code"] == 3, "profiler alert code should decode")
    expect(parser.profiler["alerts"][-1]["arg0"] == 60, "profiler alert arg0 should decode")

    parser.feed(frame(0x30, profiler_snapshot_payload(
        440,
        0x0F01,
        PROFILER_FLAG_VALID,
        100000,
        1,
        2,
        3,
        4,
    )))
    expect(parser.profiler["latest"][0x0F01]["metric_name"] == "metric_0x0F01", "unknown profiler metric should be retained")

    malformed_before = parser.profiler["counters"]["malformed"]
    parser.feed(frame(0x30, u32(450)))
    expect(parser.profiler["counters"]["malformed"] == malformed_before + 1, "bad profiler snapshot length should be counted")

    bad_profiler = frame(0x31, profiler_alert_payload(460, 0x0101, 2, 3, 1, 2))
    bad_profiler[-1] ^= 0x5A
    checksum_before = parser.checksum_errors
    parser.feed(bad_profiler)
    expect(parser.checksum_errors == checksum_before + 1, "bad profiler checksum should be counted")

    capture_id = 0x0000A501
    parser.feed(frame(0x40, la_capture_header_payload(
        capture_id,
        500,
        32,
        8,
        3,
        LA_FLAG_VALID | LA_FLAG_TRIGGERED,
        4,
        11,
    )))
    parser.feed(frame(0x43, la_trigger_event_payload(504, capture_id, 3, 2, 0x0000000F, 0x00000008)))
    parser.feed(frame(0x41, la_sample_data_payload(capture_id, 0, 0, 4, [1, 2, 4, 8, 16])))
    parser.feed(frame(0x41, la_sample_data_payload(capture_id, 1, 5, 4, [32, 64, 128])))
    parser.feed(frame(0x42, la_capture_status_payload(520, capture_id, 3, 0, 8, 2, 2, LA_FLAG_VALID)))
    capture = parser.logic_analyzer["captures"][capture_id]
    expect(capture["header"]["sample_width_bits"] == 32, "LA header sample width should decode")
    expect(capture["header"]["sample_count"] == 8, "LA header sample count should decode")
    expect(capture["trigger_event"]["trigger_index"] == 3, "LA trigger index should decode")
    expect(capture["trigger_event"]["trigger_channel"] == 2, "LA trigger channel should decode")
    expect(capture["samples"][:8] == [1, 2, 4, 8, 16, 32, 64, 128], "LA sample chunks should decode little-endian values")
    expect(capture["complete"], "LA capture should be marked complete after all samples arrive")
    expect(parser.logic_analyzer["counters"]["headers"] == 1, "LA header counter should increment")
    expect(parser.logic_analyzer["counters"]["samples"] == 2, "LA sample chunk counter should increment")
    expect(parser.logic_analyzer["counters"]["statuses"] == 1, "LA status counter should increment")
    expect(parser.logic_analyzer["counters"]["trigger_events"] == 1, "LA trigger counter should increment")

    missing_capture_id = 0x0000A502
    parser.feed(frame(0x40, la_capture_header_payload(missing_capture_id, 530, 8, 4, 1, LA_FLAG_VALID, 1, 4)))
    parser.feed(frame(0x41, la_sample_data_payload(missing_capture_id, 0, 0, 1, [0x11, 0x22])))
    parser.feed(frame(0x41, la_sample_data_payload(missing_capture_id, 2, 3, 1, [0x44])))
    expect(parser.logic_analyzer["counters"]["missing_chunks"] == 1, "LA missing chunk should be counted")
    expect(parser.logic_analyzer["captures"][missing_capture_id]["missing_ranges"][-1] == (1, 1), "LA missing range should be recorded")

    order_capture_id = 0x0000A503
    parser.feed(frame(0x40, la_capture_header_payload(order_capture_id, 540, 16, 4, 1, LA_FLAG_VALID, 1, 4)))
    parser.feed(frame(0x41, la_sample_data_payload(order_capture_id, 1, 2, 2, [0x3333, 0x4444])))
    parser.feed(frame(0x41, la_sample_data_payload(order_capture_id, 0, 0, 2, [0x1111, 0x2222])))
    expect(parser.logic_analyzer["counters"]["out_of_order_chunks"] == 1, "LA out-of-order chunk should be counted")
    expect(parser.logic_analyzer["captures"][order_capture_id]["samples"][:4] == [0x1111, 0x2222, 0x3333, 0x4444], "LA out-of-order chunks should still fill samples")

    malformed_la_before = parser.logic_analyzer["counters"]["malformed"]
    parser.feed(frame(0x40, u32(550)))
    expect(parser.logic_analyzer["counters"]["malformed"] == malformed_la_before + 1, "bad LA header length should be counted")
    parser.feed(frame(0x41, [*u32(0xA504), *u16(0), *u16(0), 4, 6, *u16(0), *([0] * 20)]))
    expect(parser.logic_analyzer["counters"]["malformed"] == malformed_la_before + 2, "oversized LA sample chunk should be counted")
    parser.feed(frame(0x44, []))
    expect(parser.logic_analyzer["counters"]["malformed"] == malformed_la_before + 3, "reserved LA type should be counted without crashing")

    print("PASS: YiFPGA Debug Protocol parser test vectors passed")


if __name__ == "__main__":
    main()
