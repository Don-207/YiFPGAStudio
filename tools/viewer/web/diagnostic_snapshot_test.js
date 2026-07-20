"use strict";

const assert = require("assert");
const snapshotApi = require("./diagnostic_snapshot.js");

async function main() {
  const capture = {
    header: { captureId: 42, timestamp: 12, sampleCount: 6, samplePeriodCycles: 2 },
    status: { chunksSent: 1, chunksTotal: 2 }, triggerEvent: { timestamp: 14, captureId: 42, triggerIndex: 1 },
    chunks: new Map([[0, { chunkIndex: 0 }]]), samples: [0, 0, 1, 1, null, null],
    missingRanges: [[1, 1]], complete: false, errors: ["missing_chunk"],
  };
  const state = {
    frames: 5, checksumErrors: 0, syncDrops: 1, unknownFrames: 0,
    logs: [
      { timestamp: 0xfffffffe, type: "Heartbeat", id: "a", text: "before" },
      { timestamp: 3, type: "Event", id: "b", text: "after", note: "secret" },
    ],
    watches: new Map(), events: new Map(), status: { lastTimestamp: 3, dropCount: 0 },
    trace: { spans: [{ startTimestamp: 4, endTimestamp: 7, traceId: 1, instanceId: 2, status: 0 }], marks: [], values: [], drops: [] },
    monitor: { history: [{ kind: "monitor_timeout", seq: 3, addr: 16, status: 6 }], values: new Map() },
    profiler: { history: new Map([[1, [{ timestamp: 8, metricId: 1, metricName: "cycles", value0: 4 }]]]), alerts: [{ timestamp: 9, metricId: 1, level: 2, code: 1 }] },
    logicAnalyzer: { captures: new Map([[42, capture]]) },
    transport: { sessionId: "fixture", viewerDroppedBytes: 4, serial_port: "/dev/ttyUSB0" },
  };
  const options = { target: { build_id: "m27", project_name: "private" }, frequencyHz: 100000000 };
  const first = await snapshotApi.build(state, options);
  const second = await snapshotApi.build(state, options);
  assert.deepStrictEqual(first, second, "same input must produce an identical snapshot");
  assert((await snapshotApi.verify(first)).valid, "built snapshot must verify");
  assert(first.evidence.some((item) => item.timestamp.wrap_count === 1), "timestamp wrap was not unfolded");
  assert(first.integrity.issues.some((item) => item.code === "incomplete_la_capture"), "incomplete LA capture was lost");
  assert(first.evidence.some((item) => item.kind === "la_stable_range"), "LA stable ranges were not extracted");
  const preview = await snapshotApi.redact(first, "provider_preview");
  const previewText = JSON.stringify(preview);
  assert(!previewText.includes("/dev/ttyUSB0") && !previewText.includes("private") && !previewText.includes("secret"), "provider preview leaked sensitive data");
  assert(preview.redaction.audit.length >= 3 && preview.redaction.audit.every((item) => !Object.hasOwn(item, "value")), "redaction audit leaked values");
  assert((await snapshotApi.verify(preview)).valid, "redacted snapshot must verify");
  const imported = await snapshotApi.importSnapshot(snapshotApi.canonicalize(first));
  assert.strictEqual(imported.evidence.length, first.evidence.length, "round trip changed evidence count");
  const tampered = JSON.parse(JSON.stringify(first));
  tampered.evidence[0].summary = "tampered";
  assert(!(await snapshotApi.verify(tampered)).valid, "tampering was not detected");
  assert(snapshotApi.validate({ ...first, schema_version: 2 }).errors.some((error) => error.includes("unsupported schema")), "unknown major version was accepted");
  console.log(`diagnostic snapshot: PASS (${first.evidence.length} evidence items)`);
}

main().catch((error) => { console.error(error.stack || error); process.exit(1); });
