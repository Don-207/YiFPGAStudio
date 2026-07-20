/* YiFPGA Studio M27 Diagnostic Snapshot v1. */
(function (root, factory) {
  const api = factory(root);
  if (typeof module === "object" && module.exports) module.exports = api;
  root.YiFPGADiagnosticSnapshot = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function (root) {
  "use strict";

  const SCHEMA = "yifpga.diagnostic_snapshot";
  const VERSION = 1;
  const KINDS = new Set([
    "debug_log", "debug_event", "debug_watch", "debug_status", "debug_heartbeat",
    "trace_span", "trace_mark", "trace_value", "trace_drop",
    "monitor_read", "monitor_write", "monitor_timeout", "monitor_register",
    "profiler_metric", "profiler_alert", "la_capture", "la_trigger", "la_edge", "la_stable_range",
    "viewer_transport", "data_gap",
  ]);
  const SEVERITIES = new Set(["debug", "info", "warning", "error", "critical", "unknown"]);
  const QUALITIES = new Set(["exact", "approximate", "unknown"]);
  const SENSITIVE_KEYS = new Set(["project", "project_name", "serial_port", "device_path", "note", "notes", "comment"]);

  function plain(value) {
    if (value instanceof Map) return Array.from(value.entries()).map(([key, item]) => [key, plain(item)]);
    if (value instanceof Set) return Array.from(value.values()).map(plain);
    if (Array.isArray(value)) return value.map(plain);
    if (value && typeof value === "object") {
      const result = {};
      for (const key of Object.keys(value)) result[key] = plain(value[key]);
      return result;
    }
    return value;
  }

  function canonicalize(value) {
    if (value === null || typeof value !== "object") {
      if (typeof value === "number" && !Number.isFinite(value)) throw new TypeError("canonical JSON rejects non-finite numbers");
      return JSON.stringify(value);
    }
    if (Array.isArray(value)) return `[${value.map(canonicalize).join(",")}]`;
    return `{${Object.keys(value).sort().filter((key) => value[key] !== undefined)
      .map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`).join(",")}}`;
  }

  function withoutHash(snapshot) {
    const copy = plain(snapshot);
    if (copy.integrity) delete copy.integrity.sha256;
    return copy;
  }

  async function sha256(text) {
    if (typeof require === "function") return require("crypto").createHash("sha256").update(text, "utf8").digest("hex");
    if (!root.crypto || !root.crypto.subtle) throw new Error("SHA-256 is unavailable");
    const bytes = new TextEncoder().encode(text);
    const digest = await root.crypto.subtle.digest("SHA-256", bytes);
    return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
  }

  async function stableId(prefix, value) {
    if (prefix === "ev") {
      const input = canonicalize(value); let first = 2166136261; let second = 2246822507;
      for (let index = 0; index < input.length; index += 1) {
        const code = input.charCodeAt(index); first = Math.imul(first ^ code, 16777619); second = Math.imul(second ^ code, 3266489909);
      }
      return `${prefix}_${(first >>> 0).toString(16).padStart(8, "0")}${(second >>> 0).toString(16).padStart(8, "0")}`;
    }
    return `${prefix}_${(await sha256(canonicalize(value))).slice(0, 20)}`;
  }

  function severity(level, fallback = "info") {
    if (typeof level === "string" && SEVERITIES.has(level)) return level;
    return ({ 0: "debug", 1: "info", 2: "warning", 3: "error", 4: "critical" })[level] || fallback;
  }

  function sourceRef(view, recordType, locator) {
    return { view, record_type: recordType, locator: plain(locator) };
  }

  function rawTimestamp(record) {
    for (const key of ["timestamp", "startTimestamp", "endTimestamp"]) {
      if (Number.isFinite(record && record[key])) return record[key];
    }
    return null;
  }

  function unwrapTimestamps(records, modulus) {
    let previous = null;
    let wraps = 0;
    return records.map((record) => {
      const raw = rawTimestamp(record);
      if (raw === null) return { raw: null, tick: null, wrap_count: wraps, quality: "unknown" };
      if (previous !== null && raw < previous && previous - raw > modulus / 2) wraps += 1;
      previous = raw;
      return { raw, tick: raw + wraps * modulus, wrap_count: wraps, quality: "exact" };
    });
  }

  function inScope(timestamp, scope) {
    if (timestamp.tick === null) return !scope || (scope.from == null && scope.to == null);
    return (!scope || scope.from == null || timestamp.tick >= scope.from) && (!scope || scope.to == null || timestamp.tick <= scope.to);
  }

  async function makeEvidence(kind, source, timestamp, level, summary, data, ref) {
    const identity = { kind, source, timestamp, source_ref: ref, data };
    return {
      evidence_id: await stableId("ev", identity), kind, source, timestamp,
      severity: severity(level), summary, data: plain(data), source_ref: ref,
    };
  }

  function mapValues(value) { return value instanceof Map ? Array.from(value.values()) : Array.isArray(value) ? value : []; }
  function mapEntries(value) { return value instanceof Map ? Array.from(value.entries()) : []; }

  function collectRecords(state, options) {
    const rows = [];
    (state.logs || []).forEach((record) => rows.push({ kind: "debug_log", source: "debug", record, ref: sourceRef("debug", "log", { timestamp: record.timestamp, type: record.type, id: record.id }) }));
    mapValues(state.events).forEach((record) => rows.push({ kind: "debug_event", source: "debug", record, level: record.level, ref: sourceRef("debug", "event", { id: record.id || record.eventId }) }));
    mapValues(state.watches).forEach((record) => rows.push({ kind: "debug_watch", source: "debug", record, ref: sourceRef("debug", "watch", { id: record.id || record.watchId, timestamp: record.timestamp }) }));
    if (state.status) rows.push({ kind: "debug_status", source: "debug", record: state.status, level: Number(state.status.dropCount) > 0 ? "warning" : "info", ref: sourceRef("debug", "status", { timestamp: state.status.lastTimestamp }) });
    const trace = state.trace || {};
    [
      [trace.spans, "trace_span", "span"], [trace.marks, "trace_mark", "mark"],
      [trace.values, "trace_value", "value"], [trace.drops, "trace_drop", "drop"],
    ].forEach(([items, kind, type]) => (items || []).forEach((record) => rows.push({ kind, source: "trace", record, level: kind === "trace_drop" || record.orphan || record.status > 0 ? "warning" : record.level, ref: sourceRef("trace", type, { trace_id: record.traceId, instance_id: record.instanceId, timestamp: rawTimestamp(record), value_id: record.valueId }) })));
    const monitor = state.monitor || {};
    (monitor.history || []).forEach((record) => rows.push({ kind: record.kind || "monitor_read", source: "monitor", record, level: record.status && record.status !== 0 ? "error" : "info", ref: sourceRef("monitor", record.kind || "record", { seq: record.seq, addr: record.addr }) }));
    mapValues(monitor.values).forEach((record) => rows.push({ kind: "monitor_register", source: "monitor", record, ref: sourceRef("monitor", "register", { addr: record.addr, timestamp: record.timestamp }) }));
    const profiler = state.profiler || {};
    mapEntries(profiler.history).forEach(([metricId, history]) => (history || []).forEach((record) => rows.push({ kind: "profiler_metric", source: "profiler", record, level: record.overflowCount > 0 ? "warning" : "info", ref: sourceRef("profiler", "metric", { metric_id: metricId, timestamp: record.timestamp }) })));
    (profiler.alerts || []).forEach((record) => rows.push({ kind: "profiler_alert", source: "profiler", record, level: record.level, ref: sourceRef("profiler", "alert", { metric_id: record.metricId, timestamp: record.timestamp, code: record.code }) }));
    const la = state.logicAnalyzer || {};
    mapEntries(la.captures).forEach(([captureId, capture]) => {
      if (options.captureId != null && String(options.captureId) !== String(captureId)) return;
      const header = capture.header || {};
      rows.push({ kind: "la_capture", source: "logic_analyzer", record: { ...header, complete: !!capture.complete, missingRanges: capture.missingRanges || [], errors: capture.errors || [], chunks: capture.chunks ? capture.chunks.size : 0 }, level: capture.complete ? "info" : "warning", ref: sourceRef("logic_analyzer", "capture", { capture_id: captureId }) });
      if (capture.triggerEvent) rows.push({ kind: "la_trigger", source: "logic_analyzer", record: capture.triggerEvent, ref: sourceRef("logic_analyzer", "trigger", { capture_id: captureId, trigger_index: capture.triggerEvent.triggerIndex }) });
      const samples = capture.samples || [];
      let start = 0;
      for (let index = 1; index <= samples.length; index += 1) {
        if (index === samples.length || samples[index] !== samples[start]) {
          if (samples[start] !== null) rows.push({ kind: index - start === 1 ? "la_edge" : "la_stable_range", source: "logic_analyzer", record: { timestamp: Number.isFinite(header.timestamp) ? header.timestamp + start * (header.samplePeriodCycles || 1) : null, captureId, start_sample: start, end_sample: index - 1, value: samples[start] }, ref: sourceRef("logic_analyzer", "sample_range", { capture_id: captureId, start_sample: start, end_sample: index - 1 }) });
          start = index;
        }
      }
    });
    const transport = state.transport || {};
    rows.push({ kind: "viewer_transport", source: "viewer", record: { ...transport, frames: state.frames || 0, checksumErrors: state.checksumErrors || 0, syncDrops: state.syncDrops || 0, unknownFrames: state.unknownFrames || 0 }, level: (state.checksumErrors || state.syncDrops || transport.viewerDroppedBytes) ? "warning" : "info", ref: sourceRef("viewer", "transport", { session_id: transport.sessionId || null }) });
    return rows;
  }

  async function build(state, options = {}) {
    const rows = collectRecords(state || {}, options);
    const timestamps = unwrapTimestamps(rows.map((row) => row.record), options.timestampModulus || 0x100000000);
    const evidence = [];
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      const timestamp = timestamps[index];
      if (!inScope(timestamp, options.scope)) continue;
      evidence.push(await makeEvidence(row.kind, row.source, timestamp, row.level, row.record.text || row.record.metricName || row.kind.replaceAll("_", " "), row.record, row.ref));
    }
    evidence.sort((a, b) => {
      if (a.timestamp.tick === null && b.timestamp.tick !== null) return 1;
      if (a.timestamp.tick !== null && b.timestamp.tick === null) return -1;
      return (a.timestamp.tick || 0) - (b.timestamp.tick || 0) || a.evidence_id.localeCompare(b.evidence_id);
    });
    const ticks = evidence.map((item) => item.timestamp.tick).filter(Number.isFinite);
    const sourceCounts = {};
    evidence.forEach((item) => { sourceCounts[item.source] = (sourceCounts[item.source] || 0) + 1; });
    const scope = options.scope || {};
    const identity = { scope, target: options.target || {}, evidence: evidence.map((item) => item.evidence_id) };
    const snapshot = {
      schema: SCHEMA, schema_version: VERSION, snapshot_id: await stableId("snapshot", identity),
      created_at: options.createdAt || "1970-01-01T00:00:00.000Z",
      time_range: { start_tick: ticks.length ? Math.min(...ticks) : null, end_tick: ticks.length ? Math.max(...ticks) : null, scope: plain(scope) },
      timebase: { unit: options.tickUnit || "cycle", frequency_hz: options.frequencyHz || null, timestamp_modulus: options.timestampModulus || 0x100000000 },
      target: plain(options.target || {}),
      session_summary: { evidence_count: evidence.length, source_counts: sourceCounts, warning_count: evidence.filter((item) => ["warning", "error", "critical"].includes(item.severity)).length },
      evidence, redaction: { profile: "none", audit: [] },
      integrity: { algorithm: "sha256", complete: evidence.every((item) => item.kind !== "la_capture" || item.data.complete), issues: [] },
    };
    evidence.filter((item) => item.kind === "la_capture" && !item.data.complete).forEach((item) => snapshot.integrity.issues.push({ code: "incomplete_la_capture", evidence_id: item.evidence_id }));
    snapshot.integrity.sha256 = await sha256(canonicalize(withoutHash(snapshot)));
    return snapshot;
  }

  function redactValue(value, path, profile, audit) {
    if (Array.isArray(value)) return value.map((item, index) => redactValue(item, `${path}/${index}`, profile, audit));
    if (!value || typeof value !== "object") return value;
    const result = {};
    for (const [key, item] of Object.entries(value)) {
      const itemPath = `${path}/${key}`;
      const absolutePath = typeof item === "string" && (/^(?:[A-Za-z]:[\\/]|\/)/.test(item));
      const serialDevice = typeof item === "string" && (/^COM\d+$/i.test(item) || /^\/dev\//.test(item));
      const sensitive = SENSITIVE_KEYS.has(key.toLowerCase()) || absolutePath || serialDevice || (profile === "provider_preview" && key.toLowerCase().includes("text"));
      if (sensitive) audit.push({ path: itemPath, action: profile === "provider_preview" ? "removed" : "masked", reason: absolutePath ? "absolute_path" : serialDevice ? "serial_device" : "sensitive_field" });
      else result[key] = redactValue(item, itemPath, profile, audit);
      if (sensitive && profile === "local_export") result[key] = "[REDACTED]";
    }
    return result;
  }

  async function redact(snapshot, profile = "provider_preview") {
    if (!["local_export", "provider_preview"].includes(profile)) throw new Error(`unknown redaction profile: ${profile}`);
    const audit = [];
    const result = redactValue(plain(snapshot), "", profile, audit);
    result.redaction = { profile, audit };
    result.integrity.sha256 = await sha256(canonicalize(withoutHash(result)));
    return result;
  }

  function validate(snapshot) {
    const errors = [];
    const required = ["schema", "schema_version", "snapshot_id", "created_at", "time_range", "timebase", "target", "session_summary", "evidence", "redaction", "integrity"];
    required.forEach((key) => { if (!Object.prototype.hasOwnProperty.call(snapshot || {}, key)) errors.push(`missing ${key}`); });
    if (!snapshot || snapshot.schema !== SCHEMA) errors.push(`schema must be ${SCHEMA}`);
    if (snapshot && snapshot.schema_version !== VERSION) errors.push(`unsupported schema major version: ${snapshot.schema_version}`);
    const ids = new Set();
    (snapshot && Array.isArray(snapshot.evidence) ? snapshot.evidence : []).forEach((item, index) => {
      ["evidence_id", "kind", "source", "timestamp", "severity", "summary", "data", "source_ref"].forEach((key) => { if (!Object.prototype.hasOwnProperty.call(item, key)) errors.push(`evidence[${index}] missing ${key}`); });
      if (!KINDS.has(item.kind)) errors.push(`evidence[${index}] unknown kind ${item.kind}`);
      if (!SEVERITIES.has(item.severity)) errors.push(`evidence[${index}] invalid severity`);
      if (!item.timestamp || !QUALITIES.has(item.timestamp.quality)) errors.push(`evidence[${index}] invalid timestamp quality`);
      if (!item.source_ref || !item.source_ref.view || !item.source_ref.record_type || !item.source_ref.locator) errors.push(`evidence[${index}] invalid source_ref`);
      if (ids.has(item.evidence_id)) errors.push(`duplicate evidence_id ${item.evidence_id}`);
      ids.add(item.evidence_id);
    });
    if (snapshot && snapshot.session_summary && snapshot.session_summary.evidence_count !== (snapshot.evidence || []).length) errors.push("session_summary evidence_count mismatch");
    return { valid: errors.length === 0, errors };
  }

  async function verify(snapshot) {
    const validation = validate(snapshot);
    const expected = snapshot && snapshot.integrity && snapshot.integrity.sha256;
    const actual = snapshot ? await sha256(canonicalize(withoutHash(snapshot))) : null;
    if (!expected || expected !== actual) validation.errors.push("integrity sha256 mismatch");
    validation.valid = validation.errors.length === 0;
    return { ...validation, expected, actual };
  }

  async function importSnapshot(json) {
    const snapshot = typeof json === "string" ? JSON.parse(json) : plain(json);
    const result = await verify(snapshot);
    if (!result.valid) throw new Error(result.errors.join("; "));
    return snapshot;
  }

  function locate(snapshot, evidenceId, callback) {
    const item = (snapshot.evidence || []).find((entry) => entry.evidence_id === evidenceId);
    if (!item) return null;
    if (callback) callback(item.source_ref, item);
    return item.source_ref;
  }

  return { SCHEMA, VERSION, canonicalize, build, redact, validate, verify, importSnapshot, locate };
});
