#!/usr/bin/env python3
"""M36 Bridge soak/performance recorder and release gate.

This validates the local Bridge stream. Cable/hw_server recovery and ILA trigger
must still be recorded separately because a TCP client cannot control them.
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import resource
import socket
import time
import unittest

from bridge_protocol import TYPE_DATA, TYPE_HELLO, TYPE_SESSION, TYPE_STATUS, decode_records


class RunMetrics:
    def __init__(self) -> None:
        self.started = time.monotonic()
        self.payload_bytes = 0
        self.data_records = 0
        self.status_records = 0
        self.hello_records = 0
        self.session_records = 0
        self.recv_gaps_ms: list[float] = []
        self.last_data_at: float | None = None
        self.latest_status: dict = {}
        self.first_status: dict = {}

    def observe(self, kind: int, payload: bytes, now: float) -> None:
        if kind == TYPE_DATA:
            self.payload_bytes += len(payload)
            self.data_records += 1
            if self.last_data_at is not None:
                self.recv_gaps_ms.append((now - self.last_data_at) * 1000.0)
            self.last_data_at = now
        elif kind == TYPE_STATUS:
            self.status_records += 1
            status = json.loads(payload)
            if not self.first_status:
                self.first_status = status
            self.latest_status = status
        elif kind == TYPE_HELLO:
            self.hello_records += 1
            hello = json.loads(payload)
            for key in ("bridge_version", "stable_id", "target", "session_id"):
                if key not in hello:
                    raise RuntimeError(f"HELLO missing {key}")
            if "build_id" not in hello["target"]:
                raise RuntimeError("HELLO target missing build_id")
        elif kind == TYPE_SESSION:
            self.session_records += 1

    @staticmethod
    def percentile(values: list[float], fraction: float) -> float:
        if not values:
            return 0.0
        ordered = sorted(values)
        return ordered[min(len(ordered) - 1, int((len(ordered) - 1) * fraction))]


def connect_and_receive(host: str, port: int, deadline: float, metrics: RunMetrics) -> None:
    pending = b""
    with socket.create_connection((host, port), timeout=3.0) as stream:
        stream.settimeout(0.5)
        while time.monotonic() < deadline:
            try:
                chunk = stream.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                raise RuntimeError("Bridge closed the stream")
            records, pending = decode_records(pending + chunk)
            now = time.monotonic()
            for kind, payload in records:
                metrics.observe(kind, payload, now)
    if pending:
        raise RuntimeError(f"disconnect crossed a partial record ({len(pending)} bytes)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=48534)
    parser.add_argument("--seconds", type=float, default=1800.0)
    parser.add_argument("--client-reconnects", type=int, default=3)
    parser.add_argument("--min-rate", type=float, default=100_000.0)
    parser.add_argument("--min-bridge-reconnects", type=int, default=0)
    parser.add_argument("--csv", type=Path, default=Path("m36_soak.csv"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(MetricsTest)
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    if (args.seconds <= 0 or args.client_reconnects < 0 or args.min_rate < 0 or
            args.min_bridge_reconnects < 0):
        parser.error("seconds/min-rate must be positive and reconnects non-negative")

    metrics = RunMetrics()
    cpu_before = time.process_time()
    slices = args.client_reconnects + 1
    for index in range(slices):
        deadline = metrics.started + args.seconds * (index + 1) / slices
        connect_and_receive(args.host, args.port, deadline, metrics)
    elapsed = time.monotonic() - metrics.started
    cpu_percent = 100.0 * (time.process_time() - cpu_before) / max(elapsed, 1e-9)
    rate = metrics.payload_bytes / max(elapsed, 1e-9)
    status = metrics.latest_status
    first_status = metrics.first_status
    row = {
        "seconds": f"{elapsed:.3f}", "payload_bytes": metrics.payload_bytes,
        "bytes_per_second": f"{rate:.3f}",
        "p50_data_gap_ms": f"{metrics.percentile(metrics.recv_gaps_ms, .50):.3f}",
        "p99_data_gap_ms": f"{metrics.percentile(metrics.recv_gaps_ms, .99):.3f}",
        "host_cpu_percent": f"{cpu_percent:.3f}",
        "max_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "client_reconnects": args.client_reconnects,
        "hello_records": metrics.hello_records, "session_records": metrics.session_records,
        "overflow_count": status.get("overflow_count", ""),
        "overflow_first": first_status.get("overflow_count", ""),
        "dropped_bytes": status.get("dropped_bytes", ""),
        "dropped_first": first_status.get("dropped_bytes", ""),
        "buffer_used": status.get("buffer_used", ""),
        "bridge_reconnects": status.get("reconnects", ""),
        "slow_clients": status.get("slow_clients", ""),
    }
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(output, fieldnames=row.keys())
        writer.writeheader()
        writer.writerow(row)
    print(json.dumps(row, sort_keys=True))
    failures = []
    if metrics.hello_records != slices:
        failures.append(f"expected {slices} HELLO records, got {metrics.hello_records}")
    if metrics.status_records == 0:
        failures.append("no STATUS record")
    if rate < args.min_rate:
        failures.append(f"throughput {rate:.1f} B/s is below {args.min_rate:.1f} B/s")
    if status.get("last_error"):
        failures.append(f"Bridge last_error={status['last_error']}")
    if (first_status and
            (status.get("overflow_count") != first_status.get("overflow_count") or
             status.get("dropped_bytes") != first_status.get("dropped_bytes"))):
        failures.append("drop/overflow counters grew during validation window")
    if status.get("reconnects", 0) < args.min_bridge_reconnects:
        failures.append(
            f"Bridge reconnects {status.get('reconnects', 0)} is below "
            f"{args.min_bridge_reconnects}")
    if failures:
        raise RuntimeError("; ".join(failures))
    return 0


class MetricsTest(unittest.TestCase):
    def test_counts_and_percentiles(self) -> None:
        value = RunMetrics()
        value.observe(TYPE_DATA, b"abc", 1.0)
        value.observe(TYPE_DATA, b"de", 1.010)
        value.observe(TYPE_STATUS, b'{"overflow_count":0}', 1.011)
        self.assertEqual(value.payload_bytes, 5)
        self.assertAlmostEqual(value.percentile(value.recv_gaps_ms, .99), 10.0)
        self.assertEqual(value.latest_status["overflow_count"], 0)

    def test_hello_requires_identity(self) -> None:
        with self.assertRaises(RuntimeError):
            RunMetrics().observe(TYPE_HELLO, b'{}', 1.0)

    def test_hello_accepts_nested_build_identity(self) -> None:
        payload = (b'{"bridge_version":1,"stable_id":"c/t/d/user2",'
                   b'"session_id":1,"target":{"build_id":1295335425}}')
        value = RunMetrics()
        value.observe(TYPE_HELLO, payload, 1.0)
        self.assertEqual(value.hello_records, 1)


if __name__ == "__main__":
    raise SystemExit(main())
