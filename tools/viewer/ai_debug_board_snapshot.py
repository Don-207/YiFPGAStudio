#!/usr/bin/env python3
"""Generate M31 board snapshots from auditable scenario run records."""
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
BOARD = ROOT / "tools/viewer/fixtures/ai_debug/board/snapshots"
TARGET = {"board": "sanitized-xilinx-board", "part": "xcku5p", "build_id": "m36_ila:3461b2cef34e2102", "protocol_version": 1}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def source(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    return data, hashlib.sha256(path.read_bytes()).hexdigest()


def evidence(evidence_id, kind, source_name, tick, severity, summary, data, record_type, locator):
    return {"evidence_id": evidence_id, "kind": kind, "source": source_name,
            "timestamp": {"raw": tick, "tick": tick, "wrap_count": 0, "quality": "exact"},
            "severity": severity, "summary": summary, "data": data,
            "source_ref": {"view": source_name, "record_type": record_type, "locator": locator}}


def snapshot(snapshot_id, created_at, evidence_items, complete, issues, provenance):
    ticks = [item["timestamp"]["tick"] for item in evidence_items]
    counts = {}
    for item in evidence_items: counts[item["source"]] = counts.get(item["source"], 0) + 1
    value = {"schema": "yifpga.diagnostic_snapshot", "schema_version": 1,
             "snapshot_id": snapshot_id, "created_at": created_at,
             "time_range": {"start_tick": min(ticks), "end_tick": max(ticks), "scope": {"type": "board_scenario"}},
             "timebase": {"unit": "cycle", "frequency_hz": 100000000, "timestamp_modulus": 4294967296},
             "target": TARGET, "session_summary": {"evidence_count": len(evidence_items), "source_counts": counts,
             "warning_count": sum(item["severity"] in ("warning", "error", "critical") for item in evidence_items)},
             "evidence": evidence_items, "redaction": {"profile": "local_export", "audit": []},
             "integrity": {"algorithm": "sha256", "complete": complete, "issues": issues}, "provenance": provenance}
    value["integrity"]["sha256"] = hashlib.sha256(canonical(value).encode()).hexdigest()
    return value


def baseline(run, run_path, run_sha, name, addrs):
    assert all(run["baseline"][addr] == run["recovery"][addr] for addr in addrs)
    item = evidence(f"ev_{name}_recovery", "monitor_register", "monitor", 0, "info",
                    "scenario configuration restored to baseline",
                    {"baseline": {addr: run["baseline"][addr] for addr in addrs},
                     "recovery": {addr: run["recovery"][addr] for addr in addrs}, "restored": True},
                    "board_run_recovery", {"scenario": run["scenario"]})
    return snapshot(f"board_{name}_baseline", run["started_at"], [item], True, [],
                    {"source_path": str(run_path.relative_to(ROOT)), "source_sha256": run_sha,
                     "derivation": "baseline and recovery register equality"})


def main():
    BOARD.mkdir(parents=True, exist_ok=True)
    profiler_path = ROOT / "artifacts/manual/ai-debug-profiler-run-20260717.json"
    profiler, profiler_sha = source(profiler_path)
    fifo_frames = [frame for frame in profiler["frames"] if frame["type"] == 0x30 and struct.unpack_from("<H", bytes.fromhex(frame["payload_hex"]), 4)[0] == 0x0101]
    raw = bytes.fromhex(fifo_frames[-1]["payload_hex"])
    timestamp, metric_id, flags, sample_cycles, value0, value1, value2, value3, overflow_count, _ = struct.unpack("<IHHIIIIIHH", raw)
    trace_frame = next(frame for frame in profiler["frames"] if frame["type"] == 0x11)
    trace_raw = bytes.fromhex(trace_frame["payload_hex"]); trace_tick = struct.unpack_from("<I", trace_raw)[0]
    fifo_items = [
        evidence("ev_board_fifo_metric", "profiler_metric", "profiler", timestamp, "warning", "actual FIFO board metric",
                 {"metricId": metric_id, "metricName": "FIFO_DEMO_LEVEL", "flags": flags, "sampleCycles": sample_cycles,
                  "value0": value0, "value1": value1, "value2": value2, "value3": value3, "overflowCount": overflow_count},
                 "profiler_snapshot", {"payload_hex": raw.hex()}),
        evidence("ev_board_fifo_trace", "trace_span", "trace", trace_tick, "info", "coexisting board trace span",
                 {"traceId": struct.unpack_from("<H", trace_raw, 4)[0], "status": trace_raw[8]},
                 "trace_span_end", {"payload_hex": trace_raw.hex()}),
    ]
    fifo = snapshot("board_fifo_backpressure", profiler["started_at"], fifo_items, True, [],
                    {"source_path": str(profiler_path.relative_to(ROOT)), "source_sha256": profiler_sha,
                     "baseline_snapshot": "board_fifo_baseline.json", "derivation": "decode actual FIFO and Trace payloads"})
    fifo_base = baseline(profiler, profiler_path, profiler_sha, "fifo", ("0x0048", "0x004c", "0x005c"))

    throughput_path = ROOT / "artifacts/manual/ai-debug-throughput-drop-run-20260717.json"
    throughput, throughput_sha = source(throughput_path)
    baseline_rate = throughput["phases"]["baseline"]["frames_per_second"]
    injected_rate = throughput["phases"]["injected"]["frames_per_second"]
    throughput_item = evidence("ev_board_throughput_drop", "profiler_metric", "profiler", 0, "warning",
                               "board throughput frame rate dropped under controlled DEMO_PERIOD injection",
                               {"metricId": 1, "metricName": "AXIS_DEMO_THROUGHPUT", "value": f"{injected_rate:.6f}",
                                "baseline": f"{baseline_rate:.6f}", "unit": "profiler_frames_per_second",
                                "baselineDemoPeriod": throughput["phases"]["baseline"]["demo_period"],
                                "injectedDemoPeriod": throughput["phases"]["injected"]["demo_period"]},
                               "board_run_window", {"phase": "injected"})
    throughput_snap = snapshot("board_throughput_drop", throughput["started_at"], [throughput_item], True, [],
                               {"source_path": str(throughput_path.relative_to(ROOT)), "source_sha256": throughput_sha,
                                "baseline_snapshot": "board_throughput_baseline.json",
                                "derivation": "equal-duration actual Profiler throughput-frame windows"})
    throughput_base = baseline(throughput, throughput_path, throughput_sha, "throughput", ("0x0010", "0x0048", "0x004c"))

    la_path = ROOT / "artifacts/manual/ai-debug-la-trigger-missing-run-20260717.json"
    la, la_sha = source(la_path)
    wait_cycles = int(la["duration_seconds"] * 100000000)
    la_item = evidence("ev_board_la_armed", "la_capture", "logic_analyzer", 0, "warning",
                       "board Logic Analyzer remained armed without a trigger",
                       {"state": "armed", "armed": True, "triggered": False, "armedCycles": wait_cycles,
                        "status": la["la_status"], "complete": True, "triggerEventCount": la["counts"].get("LA_TRIGGER_EVENT", 0)},
                       "board_run_status", {"scenario": la["scenario"]})
    la_snap = snapshot("board_la_trigger_missing", la["started_at"], [la_item], True, [],
                       {"source_path": str(la_path.relative_to(ROOT)), "source_sha256": la_sha,
                        "baseline_snapshot": "board_la_trigger_baseline.json", "derivation": "actual ARMED status and trigger-event count"})
    la_base = baseline(la, la_path, la_sha, "la_trigger", tuple(la["baseline"]))
    for name, value in (("board_fifo_backpressure.json", fifo), ("board_fifo_baseline.json", fifo_base),
                        ("board_throughput_drop.json", throughput_snap), ("board_throughput_baseline.json", throughput_base),
                        ("board_la_trigger_missing.json", la_snap), ("board_la_trigger_baseline.json", la_base)):
        (BOARD / name).write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"wrote {name} {value['integrity']['sha256']}")


if __name__ == "__main__": main()
