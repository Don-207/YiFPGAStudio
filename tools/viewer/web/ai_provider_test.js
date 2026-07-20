"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const api = require("./ai_provider.js");
const validator = require("./diagnosis_validator.js");
const cases = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "fixtures", "ai_debug", "provider", "mock_cases.json"), "utf8")).cases;
const expected = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "fixtures", "ai_debug", "expected", "provider_mock_cases.json"), "utf8")).cases;
const secret = "M29_TEST_SECRET_7f9c";
const snapshot = { snapshot_id: "m29", timebase: { unit: "cycle" }, target: { project_name: "private", apiKey: secret }, integrity: { complete: true, issues: [] }, session_summary: { evidence_count: 2 }, evidence: [
  { evidence_id: "ev-a", kind: "monitor_timeout", source: "monitor", timestamp: { tick: 10, quality: "exact" }, severity: "error", summary: "timeout", data: { status: 6, note: secret } },
  { evidence_id: "ev-b", kind: "debug_log", source: "debug", timestamp: { tick: 11, quality: "exact" }, severity: "info", summary: "ok", data: {} }
] };
const local = { findings: [{ finding_id: "finding-a", rule_id: "monitor.response_timeout.v1", severity: "error", evidence_ids: ["ev-a"], title: "timeout" }] };

async function main() {
  const context = api.buildContext(snapshot, local, { budgetBytes: 4096 });
  assert(context.selected_evidence_ids.includes("ev-a"), "finding evidence was not retained atomically");
  assert(!JSON.stringify(context).includes(secret) && context.redaction.removed_field_count >= 2, "context leaked a secret");
  assert(!JSON.stringify(api.preview(context)).includes(secret), "preview leaked a secret");
  assert(api.preview(context).estimated_bytes <= 4096 * 1.1, "trimming metadata exceeded the context budget");
  const waveform = api.buildContext({ ...snapshot, evidence: [{ ...snapshot.evidence[0], data: { samples: [0, 0, 1, 1, 0] } }] }, { findings: [] }, { budgetBytes: 4096 });
  assert(!Object.hasOwn(waveform.evidence[0].data, "samples") && waveform.evidence[0].data.sample_summary.ranges.length === 3, "waveform was not summarized");
  for (const item of cases) {
    const want = expected[item.mode]; assert(want, `${item.mode}: missing expected result`);
    const controller = new api.AnalysisController(); const provider = new api.MockProvider(item.mode, 1);
    const result = await controller.run(provider, snapshot, local, { retries: want.retries || 0, timeoutMs: 100, testSecret: secret });
    assert.strictEqual(result.status, want.status, `${item.mode}: status`);
    if (want.reason) assert.strictEqual(result.reason, want.reason, `${item.mode}: reason`);
    if (want.action_safety) assert.strictEqual(result.result.recommended_actions[0].safety, want.action_safety, `${item.mode}: safety`);
    assert(!JSON.stringify(result).includes(secret), `${item.mode}: result leaked secret`);
  }
  const timeout = await new api.AnalysisController().run(new api.MockProvider("timeout"), snapshot, local, { timeoutMs: 5 });
  assert.strictEqual(timeout.reason, "timeout");
  const controller = new api.AnalysisController(); const pending = controller.run(new api.MockProvider("valid", 50), snapshot, local); setTimeout(() => controller.cancel(), 1);
  assert.strictEqual((await pending).status, "cancelled");
  const generations = new api.AnalysisController(); const oldRequest = generations.run(new api.MockProvider("valid", 50), snapshot, local); const newRequest = generations.run(new api.MockProvider("valid", 1), snapshot, local);
  assert.strictEqual((await oldRequest).status, "stale"); assert.strictEqual((await newRequest).status, "completed");
  const disabled = await new api.AnalysisController().run(new api.DisabledProvider(), snapshot, local);
  assert.strictEqual(disabled.reason, "provider_disabled");
  assert.strictEqual(validator.validate("{", { evidenceIds: [] }).valid, false);
  console.log(`AI provider: PASS (${cases.length + 3} lifecycle/validation cases)`);
}
main().catch((error) => { console.error(error.stack || error); process.exit(1); });
