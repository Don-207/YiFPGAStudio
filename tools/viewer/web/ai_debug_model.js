/* YiFPGA Studio M30 AI Debug page-session workflow model. */
(function (root, factory) {
  const api = factory(root);
  if (typeof module === "object" && module.exports) module.exports = api;
  root.YiFPGAAIDebugModel = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function (root) {
  "use strict";
  function escape(value) { return String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]); }
  function confidence(value) { return value >= 0.75 ? "high" : value >= 0.4 ? "medium" : "low"; }
  class AIDebugModel {
    constructor(options) {
      this.stateSource = options.stateSource; this.elements = options.elements; this.download = options.download; this.onLocate = options.onLocate;
      this.controller = new root.YiFPGAAIProvider.AnalysisController(); this.provider = new root.YiFPGAAIProvider.MockProvider("valid", 80);
      this.state = { status: "idle", scope: { type: "session" }, snapshot: null, ruleResult: null, providerResult: null, preview: null, history: [], feedback: { rating: "", root_cause: "", note: "" } };
      this.bind(); this.render();
    }
    bind() {
      const e = this.elements;
      e.local.addEventListener("click", () => this.runLocal()); e.ask.addEventListener("click", () => this.askAI()); e.cancel.addEventListener("click", () => { this.controller.cancel(); this.state.status = "cancelled"; this.render(); });
      e.scope.addEventListener("change", () => { this.controller.cancel(); this.state.scope = { type: e.scope.value }; this.state.snapshot = null; this.state.ruleResult = null; this.state.providerResult = null; this.state.status = "idle"; this.render(); });
      e.consent.addEventListener("change", () => this.render());
      e.exportSnapshot.addEventListener("click", () => this.exportSnapshot()); e.exportDiagnosis.addEventListener("click", () => this.exportDiagnosis()); e.exportMarkdown.addEventListener("click", () => this.exportMarkdown());
      e.feedbackRating.addEventListener("change", () => { this.state.feedback.rating = e.feedbackRating.value; });
      e.feedbackRoot.addEventListener("input", () => { this.state.feedback.root_cause = e.feedbackRoot.value; }); e.feedbackNote.addEventListener("input", () => { this.state.feedback.note = e.feedbackNote.value; });
    }
    async buildSnapshot() {
      this.state.status = "building_snapshot"; this.render();
      const options = { scope: this.state.scope, target: { build_id: this.stateSource().transport.sessionId || null } };
      if (this.state.scope.type === "la_capture") options.captureId = this.stateSource().logicAnalyzer.latestCaptureId;
      this.state.snapshot = await root.YiFPGADiagnosticSnapshot.build(this.stateSource(), options); return this.state.snapshot;
    }
    async runLocal() {
      const snapshot = await this.buildSnapshot(); this.state.status = "local_analyzing"; this.render();
      this.state.ruleResult = root.YiFPGADiagnosticRules.evaluate(snapshot); this.state.providerResult = null;
      this.state.preview = root.YiFPGAAIProvider.preview(root.YiFPGAAIProvider.buildContext(snapshot, this.state.ruleResult));
      this.state.status = "local_complete"; this.record("local"); this.render(); return this.state.ruleResult;
    }
    async askAI() {
      if (!this.elements.consent.checked) { this.state.status = "awaiting_consent"; this.render(); return null; }
      if (!this.state.ruleResult) await this.runLocal();
      const pending = this.controller.run(this.provider, this.state.snapshot, this.state.ruleResult, { timeoutMs: 5000, retries: 1 });
      this.state.status = "running"; this.render(); const result = await pending; this.state.status = result.status;
      if (result.status === "completed") { this.state.providerResult = result.result; this.record("provider"); }
      else this.state.providerResult = null;
      this.render(); return result;
    }
    record(kind) { this.state.history.unshift({ kind, snapshot_id: this.state.snapshot.snapshot_id, status: this.state.status, finding_count: this.state.ruleResult.findings.length, timestamp: new Date().toISOString() }); this.state.history = this.state.history.slice(0, 20); }
    reset() { this.controller.cancel(); this.state = { status: "idle", scope: { type: "session" }, snapshot: null, ruleResult: null, providerResult: null, preview: null, history: [], feedback: { rating: "", root_cause: "", note: "" } }; this.elements.scope.value = "session"; this.elements.consent.checked = false; this.render(); }
    locate(id) { const ref = root.YiFPGADiagnosticSnapshot.locate(this.state.snapshot, id); if (ref && this.onLocate) this.onLocate(ref, id); return ref; }
    report() { return { schema: "yifpga.ai_debug_report", schema_version: 1, snapshot_id: this.state.snapshot && this.state.snapshot.snapshot_id, rule_set_version: this.state.ruleResult && this.state.ruleResult.rule_set_version, prompt_version: root.YiFPGAAIProvider.PROMPT_VERSION, findings: this.state.ruleResult && this.state.ruleResult.findings || [], diagnosis: this.state.providerResult, feedback: this.state.feedback }; }
    exportSnapshot() { if (this.state.snapshot) this.download(`${this.state.snapshot.snapshot_id}.json`, "application/json", root.YiFPGADiagnosticSnapshot.canonicalize(this.state.snapshot)); }
    exportDiagnosis() { if (this.state.snapshot) this.download(`${this.state.snapshot.snapshot_id}-diagnosis.json`, "application/json", JSON.stringify(this.report(), null, 2)); }
    exportMarkdown() {
      if (!this.state.snapshot) return; const report = this.report(); const lines = [`# AI Debug Report`, ``, `Snapshot: ${report.snapshot_id}`, `Scope: ${this.state.scope.type}`, `Integrity: ${this.state.snapshot.integrity.complete ? "complete" : "incomplete"}`, ``, `## Local Findings`];
      report.findings.forEach((item) => { lines.push(``, `### ${item.title}`, item.observed_fact, `Evidence: ${item.evidence_ids.join(", ")}`, `Checks: ${item.recommended_checks.join("; ")}`); });
      lines.push(``, `## AI Hypotheses`); (report.diagnosis && report.diagnosis.hypotheses || []).forEach((item) => lines.push(`- ${item.statement} (${confidence(item.confidence)}, ${item.confidence}) — ${item.evidence_ids.join(", ")}`));
      lines.push(``, `## Feedback`, `Rating: ${report.feedback.rating || "not provided"}`, `Actual root cause: ${report.feedback.root_cause || "not provided"}`, `Note: ${report.feedback.note || ""}`); this.download(`${report.snapshot_id}.md`, "text/markdown", lines.join("\n"));
    }
    render() {
      const e = this.elements; const snapshot = this.state.snapshot; const findings = this.state.ruleResult && this.state.ruleResult.findings || []; const diagnosis = this.state.providerResult;
      e.status.textContent = this.state.status.replaceAll("_", " "); e.cancel.disabled = !["running", "queued", "validating"].includes(this.state.status); e.ask.disabled = !this.elements.consent.checked && this.state.status === "awaiting_consent";
      e.preview.innerHTML = snapshot ? `<b>${snapshot.evidence.length}</b> evidence · ${escape(Object.entries(snapshot.session_summary.source_counts).map(([key, count]) => `${key}:${count}`).join(" · "))}<br>Integrity: ${snapshot.integrity.complete ? "complete" : "incomplete"} · Time unit: ${escape(snapshot.timebase.unit)}${this.state.preview ? `<br>Provider preview: ${this.state.preview.evidence_count} selected, ${this.state.preview.omitted_evidence_count} omitted, ${this.state.preview.estimated_bytes} bytes, ${this.state.preview.redaction.removed_field_count} fields redacted` : ""}` : "Run local analysis to build an immutable snapshot.";
      e.findings.innerHTML = findings.length ? findings.map((item) => `<article class="ai-card severity-${escape(item.severity)}"><h4>${escape(item.title)}</h4><p>${escape(item.observed_fact)}</p><small>Actual ${escape(JSON.stringify(item.actual))} · Threshold ${escape(JSON.stringify(item.threshold))}</small><div>${item.evidence_ids.map((id) => `<button type="button" class="evidence-link" data-evidence="${escape(id)}">${escape(id)}</button>`).join(" ")}</div><ul>${item.recommended_checks.map((check) => `<li>${escape(check)}</li>`).join("")}</ul></article>`).join("") : "<p class=\"muted-copy\">No local findings.</p>";
      e.hypotheses.innerHTML = diagnosis ? diagnosis.hypotheses.map((item) => `<article class="ai-card"><h4>${escape(item.statement)}</h4><span class="confidence ${confidence(item.confidence)}">${confidence(item.confidence)} ${item.confidence}</span>${item.conflicts_with_local_findings ? `<p class="conflict">Conflicts with ${escape(item.conflicts_with_local_findings.join(", "))}</p>` : ""}<div>${item.evidence_ids.map((id) => `<button type="button" class="evidence-link" data-evidence="${escape(id)}">${escape(id)}</button>`).join(" ")}</div></article>`).join("") : "<p class=\"muted-copy\">No validated AI diagnosis.</p>";
      e.actions.innerHTML = diagnosis ? diagnosis.recommended_actions.map((item) => `<li>${escape(item.action)} <small>${escape(item.safety)}</small></li>`).join("") : "<li>No actions.</li>";
      e.history.innerHTML = this.state.history.map((item) => `<li>${escape(item.kind)} · ${escape(item.snapshot_id)} · ${item.finding_count} findings</li>`).join("") || "<li>No reports.</li>";
      [e.findings, e.hypotheses].forEach((container) => container.querySelectorAll("[data-evidence]").forEach((button) => button.addEventListener("click", () => this.locate(button.dataset.evidence))));
    }
  }
  return { AIDebugModel, confidence };
});
