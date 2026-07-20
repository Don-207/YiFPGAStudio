/* YiFPGA Studio M28 deterministic local diagnostic rules v1. */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.YiFPGADiagnosticRules = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const VERSION = 1;
  const SEVERITY_ORDER = { critical: 0, error: 1, warning: 2, info: 3, debug: 4 };
  const REGISTRY = Object.freeze([
    { id: "data_quality.incomplete.v1", version: 1, group: "data_quality", kinds: ["data_gap", "la_capture"], threshold: 1, severity: "warning" },
    { id: "transport.error_rate.v1", version: 1, group: "transport", kinds: ["viewer_transport"], threshold: 1, severity: "warning" },
    { id: "monitor.response_timeout.v1", version: 1, group: "monitor", kinds: ["monitor_timeout", "monitor_read", "monitor_write"], threshold: 1, severity: "error" },
    { id: "fifo.backpressure.v1", version: 1, group: "fifo", kinds: ["profiler_metric", "profiler_alert"], threshold: 8, severity: "warning" },
    { id: "throughput.drop.v1", version: 1, group: "throughput", kinds: ["profiler_metric"], threshold: 0.8, severity: "warning" },
    { id: "latency.spike.v1", version: 1, group: "latency", kinds: ["profiler_metric", "profiler_alert", "trace_span"], threshold: 100, severity: "warning" },
    { id: "frame.stall.v1", version: 1, group: "frame", kinds: ["profiler_metric", "profiler_alert", "debug_event"], threshold: 2, severity: "error" },
    { id: "la.trigger_missing.v1", version: 1, group: "logic_analyzer", kinds: ["la_capture", "la_trigger"], threshold: 1000, severity: "warning" },
    { id: "la.data_integrity.v1", version: 1, group: "logic_analyzer", kinds: ["la_capture", "data_gap"], threshold: 1, severity: "warning" },
    { id: "cross_source.temporal_overlap.v1", version: 1, group: "correlation", kinds: [], threshold: 50, severity: "info" },
  ]);
  const BY_ID = new Map(REGISTRY.map((rule) => [rule.id, rule]));
  const ALLOWED_CONFIG = new Set(["enabled_groups", "disabled_groups", "rules", "thresholds"]);

  function clone(value) { return JSON.parse(JSON.stringify(value)); }
  function number(data, names) {
    for (const name of names) if (Number.isFinite(Number(data && data[name]))) return Number(data[name]);
    return null;
  }
  function text(data, names) {
    for (const name of names) if (typeof (data && data[name]) === "string") return data[name].toLowerCase();
    return "";
  }
  function tick(item) { return item && item.timestamp && Number.isFinite(item.timestamp.tick) ? item.timestamp.tick : null; }
  function quality(item) { return item && item.timestamp ? item.timestamp.quality : "unknown"; }
  function unique(items) { return Array.from(new Set(items.filter(Boolean))).sort(); }
  function fingerprint(value) {
    const input = JSON.stringify(value); let hash = 2166136261;
    for (let i = 0; i < input.length; i += 1) { hash ^= input.charCodeAt(i); hash = Math.imul(hash, 16777619); }
    return (hash >>> 0).toString(16).padStart(8, "0");
  }
  function validateConfig(config = {}) {
    const errors = [];
    Object.keys(config).forEach((key) => { if (!ALLOWED_CONFIG.has(key)) errors.push(`unknown config field: ${key}`); });
    for (const key of ["enabled_groups", "disabled_groups"]) if (config[key] !== undefined && !Array.isArray(config[key])) errors.push(`${key} must be an array`);
    for (const key of Object.keys(config.rules || {})) if (!BY_ID.has(key)) errors.push(`unknown rule: ${key}`);
    for (const [key, value] of Object.entries(config.thresholds || {})) {
      if (!BY_ID.has(key)) errors.push(`unknown threshold rule: ${key}`);
      if (!Number.isFinite(value) || value < 0) errors.push(`invalid threshold for ${key}`);
    }
    if (errors.length) throw new TypeError(errors.join("; "));
    return true;
  }
  function enabled(rule, config) {
    if (config.rules && config.rules[rule.id] === false) return false;
    if (config.disabled_groups && config.disabled_groups.includes(rule.group)) return false;
    return !config.enabled_groups || config.enabled_groups.includes(rule.group);
  }
  function threshold(rule, config, baseline) {
    if (config.thresholds && Object.hasOwn(config.thresholds, rule.id)) return { value: config.thresholds[rule.id], source: "project" };
    const base = baseline && baseline.thresholds && baseline.thresholds[rule.id];
    if (Number.isFinite(base) && base >= 0) return { value: base, source: "session_baseline" };
    return { value: rule.threshold, source: "default" };
  }
  function finding(rule, evidence, thresholdValue, actual, title, observed, causes, checks, severity) {
    const ids = unique(evidence.map((item) => item.evidence_id));
    return {
      finding_id: `finding-${fingerprint([rule.id, ids, actual])}`, rule_id: rule.id, rule_version: rule.version,
      severity: severity || rule.severity, title, observed_fact: observed, evidence_ids: ids,
      threshold: thresholdValue, actual: typeof actual === "object" ? actual : { value: actual },
      possible_causes: causes, recommended_checks: checks,
      timestamp: evidence.map(tick).filter(Number.isFinite).sort((a, b) => a - b)[0] ?? null,
    };
  }
  function metricName(item) { return text(item.data, ["metricName", "metric_name", "name", "code", "type"]); }
  function metricValue(item) { return number(item.data, ["value", "value0", "current", "average", "avg", "max", "count"]); }

  function evaluate(snapshot, config = {}, baseline = {}) {
    validateConfig(config);
    if (!snapshot || !Array.isArray(snapshot.evidence)) throw new TypeError("snapshot.evidence must be an array");
    const evidence = snapshot.evidence.slice();
    const ids = new Set(evidence.map((item) => item.evidence_id));
    if (ids.size !== evidence.length) throw new TypeError("snapshot contains duplicate evidence IDs");
    const output = []; const skipped = [];
    const run = (id, callback) => {
      const rule = BY_ID.get(id); if (!enabled(rule, config)) return;
      callback(rule, threshold(rule, config, baseline));
    };
    const incompleteCaptures = evidence.filter((item) => {
      if (item.kind !== "la_capture") return false;
      const declaredSamples = number(item.data, ["sampleCount", "sample_count"]);
      const receivedSamples = number(item.data, ["receivedSampleCount", "received_sample_count", "samplesReceived"]);
      const declaredChunks = number(item.data, ["chunksTotal", "chunks_total"]);
      const receivedChunks = number(item.data, ["chunks", "chunksReceived", "chunks_received"]);
      return item.data.complete === false || (item.data.missingRanges || []).length || (item.data.errors || []).length ||
        (declaredSamples !== null && receivedSamples !== null && declaredSamples !== receivedSamples) ||
        (declaredChunks !== null && receivedChunks !== null && declaredChunks !== receivedChunks);
    });
    const gaps = evidence.filter((item) => item.kind === "data_gap");
    const integrityIssues = (snapshot.integrity && snapshot.integrity.issues) || [];
    const incomplete = incompleteCaptures.length || gaps.length || snapshot.integrity && snapshot.integrity.complete === false;
    run("data_quality.incomplete.v1", (rule, limit) => {
      if (incomplete) output.push(finding(rule, [...incompleteCaptures, ...gaps], limit, { value: incompleteCaptures.length + gaps.length, issue_count: integrityIssues.length }, "Diagnostic data is incomplete", "The snapshot reports missing or incomplete evidence; dependent conclusions are suppressed or weakened.", ["Transport loss", "Partial logic-analyzer capture", "Snapshot exported before collection completed"], ["Repeat the capture after checking transport health", "Inspect integrity issues and missing ranges before drawing conclusions"]));
    });
    run("transport.error_rate.v1", (rule, limit) => {
      const items = evidence.filter((item) => item.kind === "viewer_transport");
      const total = items.reduce((sum, item) => sum + (["checksumErrors", "checksum_errors", "malformedFrames", "malformed", "syncDrops", "sync_drops", "viewerDroppedBytes", "droppedBytes", "dropCount"].reduce((n, key) => n + Math.max(0, Number(item.data[key]) || 0), 0)), 0);
      if (total >= limit.value) output.push(finding(rule, items, limit, total, "Transport errors increased in the selected window", `Transport checksum, malformed, synchronization, or dropped-data counters total ${total}.`, ["Noisy or unstable physical link", "Host parser lost framing", "Viewer could not consume input fast enough"], ["Check checksum and framing counters independently", "Reduce link rate or host load and repeat the capture"]));
    });
    run("monitor.response_timeout.v1", (rule, limit) => {
      const items = evidence.filter((item) => item.kind === "monitor_timeout" || ((item.kind === "monitor_read" || item.kind === "monitor_write") && (number(item.data, ["status"]) || 0) !== 0) || item.data && item.data.seqMismatch === true);
      if (items.length >= limit.value) output.push(finding(rule, items, limit, items.length, "Monitor request did not receive a valid response", `${items.length} monitor request(s) timed out, returned an error, or had a sequence mismatch.`, ["Response path is stalled", "Request/response decoder state is out of sync"], ["Inspect the request sequence and address", "Verify decoder and response-ready paths"]));
    });
    run("fifo.backpressure.v1", (rule, limit) => {
      const items = evidence.filter((item) => /fifo|backpressure|ready|stall/.test(metricName(item)) && (item.data.backpressure === true || item.data.ready === false || number(item.data, ["stallCycles", "stall_cycles", "consecutive", "duration", "value", "value0"]) >= limit.value));
      if (items.length) output.push(finding(rule, items, limit, Math.max(...items.map((item) => number(item.data, ["stallCycles", "stall_cycles", "consecutive", "duration", "value", "value0"]) || 0)), "FIFO backpressure persisted", "FIFO occupancy/backpressure evidence shows valid traffic held while downstream readiness was low.", ["Downstream consumer is stalled", "FIFO sizing is insufficient for the burst"], ["Inspect valid/ready around the reported interval", "Compare upstream production and downstream service rates"]));
    });
    run("throughput.drop.v1", (rule, limit) => {
      const items = evidence.filter((item) => /throughput|bandwidth|rate/.test(metricName(item)));
      const bad = items.filter((item) => { const current = metricValue(item); const base = number(item.data, ["baseline", "expected", "reference"]) ?? (baseline.metrics && baseline.metrics.throughput); return Number.isFinite(current) && Number.isFinite(base) && base > 0 && current / base < limit.value; });
      if (bad.length) { const ratios = bad.map((item) => metricValue(item) / (number(item.data, ["baseline", "expected", "reference"]) ?? (baseline.metrics && baseline.metrics.throughput))); output.push(finding(rule, bad, limit, { value: Math.min(...ratios), unit: "baseline_ratio" }, "Throughput dropped below baseline", `Measured throughput fell to ${(Math.min(...ratios) * 100).toFixed(1)}% of its baseline.`, ["Backpressure or stalls reduced service rate", "Drops or retries consumed link capacity"], ["Compare the same workload and window", "Inspect nearby stall, FIFO, and transport evidence"])); }
    });
    run("latency.spike.v1", (rule, limit) => {
      const items = evidence.filter((item) => /latency/.test(metricName(item)) && (number(item.data, ["max", "average", "avg", "value", "value0", "duration"]) || 0) > limit.value);
      if (items.length) output.push(finding(rule, items, limit, Math.max(...items.map((item) => number(item.data, ["max", "average", "avg", "value", "value0", "duration"]) || 0)), "Latency exceeded the configured limit", "A latency metric exceeded the selected threshold.", ["Contention or downstream backpressure", "A slow response path or retry"], ["Inspect trace spans nearest the spike", "Compare average and maximum latency over the same window"]));
    });
    run("frame.stall.v1", (rule, limit) => {
      const items = evidence.filter((item) => /frame.*stall|frame.*missing|frame.*period/.test(metricName(item)) && (item.data.missing === true || (number(item.data, ["missed", "missingTicks", "periodRatio", "value", "value0"]) || 0) >= limit.value));
      if (items.length) output.push(finding(rule, items, limit, Math.max(...items.map((item) => number(item.data, ["missed", "missingTicks", "periodRatio", "value", "value0"]) || 0)), "Frame ticks stalled or became irregular", "Frame timing evidence shows missing ticks or an abnormal period.", ["Frame state machine stopped advancing", "Clock enable or upstream input is absent"], ["Locate the last normal frame tick", "Inspect frame-state registers and adjacent events"]));
    });
    run("la.trigger_missing.v1", (rule, limit) => {
      const captures = evidence.filter((item) => item.kind === "la_capture" && (item.data.armed === true || item.data.state === "armed") && item.data.triggered !== true);
      const triggeredIds = new Set(evidence.filter((item) => item.kind === "la_trigger").map((item) => String(item.data.captureId ?? item.data.capture_id)));
      const bad = captures.filter((item) => !triggeredIds.has(String(item.data.captureId ?? item.data.capture_id)) && (number(item.data, ["armedCycles", "waitCycles", "elapsed", "timeout"]) || limit.value) >= limit.value);
      if (bad.length && !incomplete) output.push(finding(rule, bad, limit, Math.max(...bad.map((item) => number(item.data, ["armedCycles", "waitCycles", "elapsed", "timeout"]) || limit.value)), "Logic analyzer did not trigger while armed", "The analyzer remained armed past the trigger wait threshold without a trigger event.", ["Trigger expression never became true", "Selected signal had no activity", "Sampling configuration does not match the signal domain"], ["Review trigger masks and values", "Confirm probe activity and sample clock"]));
      else if (bad.length) skipped.push({ rule_id: rule.id, reason: "incomplete_capture" });
    });
    run("la.data_integrity.v1", (rule, limit) => {
      if (incompleteCaptures.length || gaps.length) output.push(finding(rule, [...incompleteCaptures, ...gaps], limit, incompleteCaptures.length + gaps.length, "Logic-analyzer capture is incomplete", "One or more chunks, samples, or declared capture ranges are missing.", ["Transport loss during capture", "Capture ended before every chunk was delivered"], ["Re-capture with fewer samples or a lower sample rate", "Verify chunk count and sample count before analysis"]));
    });
    run("cross_source.temporal_overlap.v1", (rule, limit) => {
      const abnormal = evidence.filter((item) => ["warning", "error", "critical"].includes(item.severity) && tick(item) !== null && quality(item) !== "unknown");
      let pair = null; let delta = Infinity;
      for (let i = 0; i < abnormal.length; i += 1) for (let j = i + 1; j < abnormal.length; j += 1) if (abnormal[i].source !== abnormal[j].source) { const d = Math.abs(tick(abnormal[i]) - tick(abnormal[j])); if (d <= limit.value && d < delta) { pair = [abnormal[i], abnormal[j]]; delta = d; } }
      if (pair) output.push(finding(rule, pair, limit, { value: delta, unit: snapshot.timebase && snapshot.timebase.unit || "tick" }, "Anomalies from different sources occurred close together", `Two abnormal observations from different sources occurred ${delta} tick(s) apart; this is temporal correlation, not proof of causation.`, ["A shared upstream condition may affect both observations", "The overlap may be coincidental"], ["Repeat the workload and check whether the ordering recurs", "Inspect the shared time window without assuming causality"]));
      else if (evidence.filter((item) => ["warning", "error", "critical"].includes(item.severity)).some((item) => quality(item) === "unknown")) skipped.push({ rule_id: rule.id, reason: "timestamps_not_comparable" });
    });
    for (const rule of REGISTRY) {
      if (!enabled(rule, config) || !rule.kinds.length) continue;
      const hasInput = evidence.some((item) => rule.kinds.includes(item.kind));
      const hasResult = output.some((item) => item.rule_id === rule.id) || skipped.some((item) => item.rule_id === rule.id);
      if (!hasInput && !hasResult) skipped.push({ rule_id: rule.id, reason: "missing_required_evidence" });
    }
    output.forEach((item) => { if (item.evidence_ids.some((id) => !ids.has(id))) throw new Error(`finding references missing evidence: ${item.finding_id}`); });
    output.sort((a, b) => (SEVERITY_ORDER[a.severity] ?? 99) - (SEVERITY_ORDER[b.severity] ?? 99) || (a.timestamp === null) - (b.timestamp === null) || (a.timestamp ?? 0) - (b.timestamp ?? 0) || a.rule_id.localeCompare(b.rule_id) || a.finding_id.localeCompare(b.finding_id));
    skipped.sort((a, b) => a.rule_id.localeCompare(b.rule_id) || a.reason.localeCompare(b.reason));
    return { schema: "yifpga.diagnostic_findings", schema_version: VERSION, rule_set_version: VERSION, snapshot_id: snapshot.snapshot_id, findings: output, skipped };
  }

  return { VERSION, REGISTRY, validateConfig, evaluate };
});
