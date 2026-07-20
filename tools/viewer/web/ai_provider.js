/* YiFPGA Studio M29 provider-neutral context and lifecycle boundary. */
(function (root, factory) {
  const validator = typeof module === "object" && module.exports ? require("./diagnosis_validator.js") : root.YiFPGADiagnosisValidator;
  const api = factory(validator);
  if (typeof module === "object" && module.exports) module.exports = api;
  root.YiFPGAAIProvider = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function (validator) {
  "use strict";
  const PROMPT_VERSION = "yifpga-diagnosis-v1";
  const SYSTEM_PROMPT = "Use only supplied evidence and local findings. Separate observed facts, hypotheses, counter-evidence, and information gaps. Every hypothesis must cite supplied evidence IDs. Recommend read-only steps for a human; never claim to have run tools, builds, simulations, or hardware operations.";
  const SENSITIVE = /secret|token|password|api.?key|credential|serial_port|device_path|project_name|note|comment/i;
  function clone(value) { return JSON.parse(JSON.stringify(value)); }
  function redact(value, audit, path = "") {
    if (Array.isArray(value)) return value.map((item, i) => redact(item, audit, `${path}/${i}`));
    if (!value || typeof value !== "object") return value;
    const out = {};
    for (const [key, item] of Object.entries(value)) {
      if (SENSITIVE.test(key) || typeof item === "string" && (/^(?:[A-Za-z]:[\\/]|\/dev\/)/.test(item))) audit.push({ path: `${path}/${key}`, action: "removed" });
      else out[key] = redact(item, audit, `${path}/${key}`);
    }
    return out;
  }
  function bytes(value) { return new TextEncoder().encode(JSON.stringify(value)).length; }
  function summarizeEvidence(item) {
    const result = clone(item);
    const samples = result.data && result.data.samples;
    if (!Array.isArray(samples)) return result;
    const ranges = [];
    for (let start = 0; start < samples.length && ranges.length < 64;) {
      let end = start + 1; while (end < samples.length && samples[end] === samples[start]) end += 1;
      ranges.push({ start_sample: start, end_sample: end - 1, value: samples[start] }); start = end;
    }
    result.data.sample_summary = { sample_count: samples.length, ranges, truncated: ranges.length === 64 && ranges[ranges.length - 1].end_sample < samples.length - 1 };
    delete result.data.samples;
    return result;
  }
  function buildContext(snapshot, ruleResult, options = {}) {
    const budget = options.budgetBytes || 64 * 1024; const selectionBudget = Math.floor(budget * 0.85); const audit = [];
    const cleanSnapshot = redact({ snapshot_id: snapshot.snapshot_id, time_range: snapshot.time_range, timebase: snapshot.timebase, target: snapshot.target, integrity: snapshot.integrity, session_summary: snapshot.session_summary }, audit);
    const evidenceById = new Map((snapshot.evidence || []).map((item) => [item.evidence_id, redact(summarizeEvidence(item), audit)]));
    const findings = (ruleResult && ruleResult.findings || []).map((item) => redact(item, audit));
    const priority = findings.slice().sort((a, b) => Number(!a.rule_id.startsWith("data_quality.")) - Number(!b.rule_id.startsWith("data_quality.")) || a.finding_id.localeCompare(b.finding_id));
    const context = { prompt_version: PROMPT_VERSION, snapshot: cleanSnapshot, findings: [], evidence: [], selected_evidence_ids: [], omitted_evidence_count: 0, trimming_reasons: [], redaction: { removed_field_count: audit.length } };
    const selected = new Set(); let budgetOmitted = 0; let findingOmitted = 0;
    for (const finding of priority) {
      const unitEvidence = (finding.evidence_ids || []).map((id) => evidenceById.get(id)).filter(Boolean);
      const candidate = clone(context); candidate.findings.push(finding);
      unitEvidence.forEach((item) => { if (!selected.has(item.evidence_id)) candidate.evidence.push(item); });
      if (bytes(candidate) <= selectionBudget || finding.rule_id.startsWith("data_quality.")) { context.findings.push(finding); unitEvidence.forEach((item) => { if (!selected.has(item.evidence_id)) { selected.add(item.evidence_id); context.evidence.push(item); } }); }
      else { findingOmitted += 1; if (context.trimming_reasons.length < 10) context.trimming_reasons.push(`omitted_finding:${finding.finding_id}`); }
    }
    const severity = { critical: 0, error: 1, warning: 2, info: 3, debug: 4 };
    const remaining = Array.from(evidenceById.values()).filter((item) => !selected.has(item.evidence_id)).sort((a, b) => (severity[a.severity] ?? 9) - (severity[b.severity] ?? 9) || a.evidence_id.localeCompare(b.evidence_id));
    for (const item of remaining) { const candidate = clone(context); candidate.evidence.push(item); if (bytes(candidate) <= selectionBudget) { selected.add(item.evidence_id); context.evidence.push(item); } else { budgetOmitted += 1; if (context.trimming_reasons.length < 10) context.trimming_reasons.push(`budget:${item.evidence_id}`); } }
    if (findingOmitted) context.trimming_reasons.push(`omitted_findings_total:${findingOmitted}`);
    if (budgetOmitted) context.trimming_reasons.push(`budget_omitted_evidence_total:${budgetOmitted}`);
    context.selected_evidence_ids = Array.from(selected).sort(); context.omitted_evidence_count = evidenceById.size - selected.size;
    context.budget = { limit_bytes: budget, serialized_bytes: bytes(context) };
    return context;
  }
  function preview(context) { return { prompt_version: context.prompt_version, evidence_count: context.evidence.length, finding_count: context.findings.length, omitted_evidence_count: context.omitted_evidence_count, estimated_bytes: bytes(context), redaction: clone(context.redaction), field_categories: ["snapshot_summary", "local_findings", "selected_evidence"] }; }
  class DisabledProvider { constructor() { this.id = "disabled"; } async analyze() { const error = new Error("AI Provider is disabled"); error.code = "provider_disabled"; throw error; } }
  class MockProvider {
    constructor(mode = "valid", delayMs = 5) { this.id = "mock"; this.model = `mock-${mode}`; this.mode = mode; this.delayMs = delayMs; this.calls = 0; }
    async analyze(context, options = {}, signal) {
      this.calls += 1; if (this.mode === "retry-once" && this.calls === 1) { const error = new Error("temporary mock failure"); error.retryable = true; throw error; }
      await new Promise((resolve, reject) => { const timer = setTimeout(resolve, this.mode === "timeout" ? 1000 : this.delayMs); if (signal) signal.addEventListener("abort", () => { clearTimeout(timer); const error = new Error("cancelled"); error.name = "AbortError"; reject(error); }, { once: true }); });
      if (this.mode === "invalid-json") return "{";
      const id = context.selected_evidence_ids[0];
      const result = { schema_version: 1, summary: "Mock diagnosis", observed_facts: id ? [{ statement: "Input evidence was observed", evidence_ids: [id] }] : [], hypotheses: [{ statement: "Mock hypothesis", confidence: 0.7, evidence_ids: id ? [id] : [] }], recommended_actions: [{ action: "Inspect the referenced evidence", safety: "read_only" }], insufficient_evidence: [], metadata: { prompt_version: PROMPT_VERSION, provider: this.id, model: this.model } };
      if (this.mode === "missing-field") delete result.summary;
      if (this.mode === "bad-confidence") result.hypotheses[0].confidence = 4;
      if (this.mode === "unknown-evidence") result.hypotheses[0].evidence_ids = ["ev-does-not-exist"];
      if (this.mode === "unsafe-action") result.recommended_actions[0] = { action: "Write register 0x10", safety: "mutating" };
      if (this.mode === "secret-echo") result.summary = options.testSecret || "secret";
      return this.mode === "streamed" ? JSON.parse(JSON.stringify(result)) : result;
    }
  }
  class RemoteProviderAdapter {
    constructor(config, fetchImpl) { this.id = config.provider; this.model = config.model; this.endpoint = config.endpoint; this.credentialRef = config.credential_ref; this.timeoutMs = config.timeout_ms || 30000; this.fetchImpl = fetchImpl || root.fetch; }
    async analyze(context, options = {}, signal) {
      if (!this.fetchImpl) throw new Error("fetch is unavailable");
      const response = await this.fetchImpl(this.endpoint, { method: "POST", headers: { "content-type": "application/json", ...(options.authorization ? { authorization: options.authorization } : {}) }, body: JSON.stringify({ model: this.model, prompt_version: PROMPT_VERSION, context }), signal });
      if (!response.ok) { const error = new Error(`Provider HTTP ${response.status}`); error.retryable = response.status >= 500 || response.status === 429; throw error; }
      return response.json();
    }
  }
  class AnalysisController {
    constructor() { this.generation = 0; this.state = { status: "idle", generation: 0 }; this.abortController = null; }
    cancel() { if (this.abortController) this.abortController.abort(); if (["queued", "running", "validating"].includes(this.state.status)) this.state = { ...this.state, status: "cancelled" }; }
    async run(provider, snapshot, ruleResult, options = {}) {
      this.cancel(); const generation = ++this.generation; this.abortController = new AbortController(); const signal = this.abortController.signal;
      const startedAt = new Date().toISOString();
      this.state = { status: "queued", generation, local_findings: ruleResult.findings || [] };
      const context = buildContext(snapshot, ruleResult, options); this.state = { ...this.state, status: "running", preview: preview(context) };
      const timeout = setTimeout(() => this.abortController.abort(), options.timeoutMs || 30000); let attempt = 0;
      try {
        let raw;
        while (true) { try { raw = await provider.analyze(context, options, signal); break; } catch (error) { if (error.name === "AbortError" || !error.retryable || attempt >= (options.retries || 0)) throw error; attempt += 1; } }
        if (generation !== this.generation) return { status: "stale", generation };
        this.state = { ...this.state, status: "validating" };
        const checked = validator.validate(raw, { evidenceIds: context.selected_evidence_ids, ruleIds: (ruleResult.findings || []).map((item) => item.rule_id), forbiddenValues: options.secretValues || (options.testSecret ? [options.testSecret] : []) });
        if (!checked.valid) { const error = new Error(checked.errors.join(";")); error.code = "validation_failed"; throw error; }
        checked.result.metadata = { ...checked.result.metadata, request_generation: generation, request_id: `request-${generation}`, started_at: startedAt, completed_at: new Date().toISOString(), trimming: { selected: context.evidence.length, omitted: context.omitted_evidence_count } };
        this.state = { status: "completed", generation, result: checked.result, local_findings: ruleResult.findings || [] }; return this.state;
      } catch (error) {
        if (generation !== this.generation) return { status: "stale", generation };
        const cancelled = signal.aborted && this.state.status === "cancelled";
        this.state = { status: cancelled ? "cancelled" : "failed", generation, reason: cancelled ? "cancelled" : (signal.aborted ? "timeout" : error.code || "provider_error"), error: String(error.message || error).slice(0, 200), local_findings: ruleResult.findings || [] }; return this.state;
      } finally { clearTimeout(timeout); }
    }
  }
  return { PROMPT_VERSION, SYSTEM_PROMPT, buildContext, preview, DisabledProvider, MockProvider, RemoteProviderAdapter, AnalysisController };
});
