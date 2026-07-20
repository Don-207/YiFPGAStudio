#!/usr/bin/env python3
"""Hardware-free validation entry point for AI Debug data contracts."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures" / "ai_debug" / "snapshots"
RULE_TEST = ROOT / "web" / "diagnostic_rules_test.js"
PROVIDER_TEST = ROOT / "web" / "ai_provider_test.js"
BOARD_EVIDENCE_TEST = ROOT / "web" / "ai_debug_board_evidence_test.js"
BOARD_MANIFEST = ROOT / "fixtures" / "ai_debug" / "board" / "qualification_manifest.json"
REQUIRED = {
    "schema", "schema_version", "snapshot_id", "created_at", "time_range",
    "timebase", "target", "session_summary", "evidence", "redaction", "integrity",
}
EVIDENCE_REQUIRED = {
    "evidence_id", "kind", "source", "timestamp", "severity", "summary", "data", "source_ref",
}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def validate_fixture(path):
    snapshot = json.loads(path.read_text(encoding="utf-8"))
    errors = []
    missing = REQUIRED - snapshot.keys()
    if missing:
        errors.append(f"missing fields: {sorted(missing)}")
    if snapshot.get("schema") != "yifpga.diagnostic_snapshot":
        errors.append("invalid schema")
    if snapshot.get("schema_version") != 1:
        errors.append(f"unsupported schema major version: {snapshot.get('schema_version')}")
    ids = set()
    for index, item in enumerate(snapshot.get("evidence", [])):
        item_missing = EVIDENCE_REQUIRED - item.keys()
        if item_missing:
            errors.append(f"evidence[{index}] missing: {sorted(item_missing)}")
        evidence_id = item.get("evidence_id")
        if evidence_id in ids:
            errors.append(f"duplicate evidence_id: {evidence_id}")
        ids.add(evidence_id)
        ref = item.get("source_ref", {})
        if not all(key in ref for key in ("view", "record_type", "locator")):
            errors.append(f"evidence[{index}] invalid source_ref")
        timestamp = item.get("timestamp", {})
        if timestamp.get("quality") not in ("exact", "approximate", "unknown"):
            errors.append(f"evidence[{index}] invalid timestamp quality")
    if snapshot.get("session_summary", {}).get("evidence_count") != len(snapshot.get("evidence", [])):
        errors.append("evidence count mismatch")
    unsigned = json.loads(json.dumps(snapshot))
    expected = unsigned.get("integrity", {}).pop("sha256", None)
    actual = hashlib.sha256(canonical(unsigned).encode("utf-8")).hexdigest()
    if expected != actual:
        errors.append(f"sha256 mismatch: expected {expected}, actual {actual}")
    return snapshot, errors


def validate_snapshots():
    failures = []
    fixtures = sorted(path for path in FIXTURES.glob("*.json") if path.name != "rule_golden_cases.json")
    expected_names = {"normal_session.json", "mixed_fault_session.json", "timestamp_wrap.json", "incomplete_la_capture.json"}
    if {path.name for path in fixtures} != expected_names:
        failures.append("fixture set does not match the M27 contract")
    all_kinds = set()
    for path in fixtures:
        snapshot, errors = validate_fixture(path)
        all_kinds.update(item.get("kind") for item in snapshot.get("evidence", []))
        if errors:
            failures.extend(f"{path.name}: {error}" for error in errors)
        else:
            print(f"{path.name}: PASS ({len(snapshot['evidence'])} evidence items)")
    required_sources = {"debug", "trace", "monitor", "profiler", "logic_analyzer", "viewer"}
    sources = set()
    for path in fixtures:
        snapshot = json.loads(path.read_text(encoding="utf-8"))
        sources.update(item.get("source") for item in snapshot.get("evidence", []))
    if not required_sources <= sources:
        failures.append(f"missing P0 fixture sources: {sorted(required_sources - sources)}")
    if shutil.which("node") is None:
        failures.append("node is required for the browser-module regression")
    else:
        result = subprocess.run(
            ["node", str(ROOT / "web" / "diagnostic_snapshot_test.js")],
            cwd=ROOT.parent.parent, text=True, capture_output=True, check=False,
        )
        if result.stdout:
            print(result.stdout, end="")
        if result.returncode:
            failures.append(result.stderr.strip() or "diagnostic_snapshot_test.js failed")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print(f"snapshot validation: PASS ({len(fixtures)} fixtures, {len(all_kinds)} kinds)")
    return 0


def validate_rules(case=None, json_output=False, update_golden_preview=False):
    if shutil.which("node") is None:
        print("FAIL: node is required for the diagnostic-rules regression", file=sys.stderr)
        return 1
    command = ["node", str(RULE_TEST)]
    if case:
        command.extend(("--case", case))
    if json_output:
        command.append("--json")
    if update_golden_preview:
        command.append("--update-golden-preview")
    result = subprocess.run(command, cwd=ROOT.parent.parent, text=True, capture_output=True, check=False)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode


def validate_provider():
    if shutil.which("node") is None:
        print("FAIL: node is required for the AI Provider regression", file=sys.stderr)
        return 1
    result = subprocess.run(["node", str(PROVIDER_TEST)], cwd=ROOT.parent.parent, text=True, capture_output=True, check=False)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode


def validate_board_manifest():
    failures = []
    try:
        manifest = json.loads(BOARD_MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"FAIL: board manifest: {error}", file=sys.stderr)
        return 1
    if manifest.get("schema") != "yifpga.ai_debug_board_qualification" or manifest.get("schema_version") != 1:
        failures.append("invalid board qualification schema")
    scenarios = manifest.get("scenarios", [])
    required_categories = {"transport", "fifo_backpressure", "performance", "la_trigger", "la_integrity"}
    categories = {item.get("category") for item in scenarios}
    if not required_categories <= categories:
        failures.append(f"missing board categories: {sorted(required_categories - categories)}")
    golden_inputs = json.loads((FIXTURES / "rule_golden_cases.json").read_text(encoding="utf-8"))
    golden_expected = json.loads((ROOT / "fixtures" / "ai_debug" / "expected" / "rule_golden_cases.json").read_text(encoding="utf-8"))
    input_ids = {item["id"] for item in golden_inputs["cases"]}
    for item in scenarios:
        for field in ("id", "category", "origin", "qualification_status", "input_case", "expected_rules", "required_evidence", "injection", "recovery"):
            if not item.get(field):
                failures.append(f"{item.get('id', '<unknown>')}: missing {field}")
        case_id = item.get("input_case")
        if case_id not in input_ids or case_id not in golden_expected["cases"]:
            failures.append(f"{item.get('id')}: unknown input case {case_id}")
        else:
            actual_rules = set(golden_expected["cases"][case_id].get("rules", []))
            missing_rules = set(item.get("expected_rules", [])) - actual_rules
            forbidden = set(item.get("forbidden_rules", [])) & actual_rules
            if missing_rules:
                failures.append(f"{item.get('id')}: golden case missing rules {sorted(missing_rules)}")
            if forbidden:
                failures.append(f"{item.get('id')}: golden case contains forbidden rules {sorted(forbidden)}")
    fixture_root = ROOT / "fixtures" / "ai_debug"
    sensitive_markers = ("/dev/tty", "COM3\"", "api_key\"", "authorization\"")
    for path in fixture_root.rglob("*.json"):
        content = path.read_text(encoding="utf-8")
        for marker in sensitive_markers:
            if marker.lower() in content.lower():
                failures.append(f"sensitive marker {marker!r} in {path.relative_to(ROOT)}")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    if shutil.which("node") is None:
        failures.append("node is required for board evidence binding")
    else:
        result = subprocess.run(
            ["node", str(BOARD_EVIDENCE_TEST)], cwd=ROOT.parent.parent,
            text=True, capture_output=True, check=False,
        )
        if result.stdout:
            print(result.stdout, end="")
        if result.returncode:
            failures.append(result.stderr.strip() or "ai_debug_board_evidence_test.js failed")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    pending = sum(item.get("qualification_status") != "passed" for item in scenarios)
    print(f"board qualification manifest: PASS ({len(scenarios)} scenarios, {pending} scenario sign-offs pending)")
    return 0


def validate_release_documents():
    documents = [
        ROOT.parent.parent / "README.md",
        ROOT.parent.parent / "doc" / "YiFPGA_AI_Debug_使用说明.md",
        ROOT.parent.parent / "doc" / "YiFPGA_Debug_Protocol_v1.md",
    ]
    missing = [str(path) for path in documents if not path.is_file()]
    if missing:
        for path in missing:
            print(f"FAIL: missing release document: {path}", file=sys.stderr)
        return 1
    print(f"AI Debug release documents: PASS ({len(documents)} current documents)")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("snapshot", "rules", "provider", "board", "release", "all"))
    parser.add_argument("--case", help="run one rules golden case")
    parser.add_argument("--json", action="store_true", help="emit a machine-readable rules result")
    parser.add_argument("--update-golden-preview", action="store_true", help="print proposed golden output without writing files")
    args = parser.parse_args()
    if args.command == "snapshot":
        return validate_snapshots()
    if args.command == "rules":
        return validate_rules(args.case, args.json, args.update_golden_preview)
    if args.command == "provider":
        return validate_provider()
    if args.command == "board":
        return validate_board_manifest()
    if args.command == "release":
        statuses = (validate_snapshots(), validate_rules(), validate_provider(), validate_board_manifest(), validate_release_documents())
        return next((status for status in statuses if status), 0)
    snapshot_status = validate_snapshots()
    rules_status = validate_rules(args.case, args.json, args.update_golden_preview)
    provider_status = validate_provider()
    board_status = validate_board_manifest()
    return snapshot_status or rules_status or provider_status or board_status


if __name__ == "__main__":
    raise SystemExit(main())
