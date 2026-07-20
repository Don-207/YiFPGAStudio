"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const rules = require("./diagnostic_rules.js");

const fixtureRoot = path.join(__dirname, "..", "fixtures", "ai_debug");
const inputs = JSON.parse(fs.readFileSync(path.join(fixtureRoot, "snapshots", "rule_golden_cases.json"), "utf8"));
const expectedFile = path.join(fixtureRoot, "expected", "rule_golden_cases.json");
const expected = JSON.parse(fs.readFileSync(expectedFile, "utf8"));
const argv = process.argv.slice(2);
const caseIndex = argv.indexOf("--case");
const selected = caseIndex >= 0 ? argv[caseIndex + 1] : null;
const jsonOutput = argv.includes("--json");
const preview = argv.includes("--update-golden-preview");
const failures = [];
const actualPreview = { schema: expected.schema, schema_version: 1, cases: {} };

for (const testCase of inputs.cases) {
  if (selected && testCase.id !== selected) continue;
  const want = expected.cases[testCase.id];
  if (!want) { failures.push({ case: testCase.id, error: "missing expected case" }); continue; }
  const first = rules.evaluate(testCase.snapshot);
  const second = rules.evaluate(testCase.snapshot);
  assert.deepStrictEqual(first, second, `${testCase.id}: evaluation is not deterministic`);
  const actualRules = first.findings.map((item) => item.rule_id);
  actualPreview.cases[testCase.id] = { rules: actualRules, forbidden: want.forbidden || [], threshold_sources: Object.fromEntries(first.findings.map((item) => [item.rule_id, item.threshold.source])) };
  const missing = (want.rules || []).filter((id) => !actualRules.includes(id));
  const forbidden = (want.forbidden || []).filter((id) => actualRules.includes(id));
  const extra = actualRules.filter((id) => !(want.rules || []).includes(id));
  const evidenceErrors = [];
  for (const [ruleId, ids] of Object.entries(want.evidence || {})) {
    const item = first.findings.find((finding) => finding.rule_id === ruleId);
    if (!item || JSON.stringify(item.evidence_ids) !== JSON.stringify(ids)) evidenceErrors.push({ rule_id: ruleId, expected: ids, actual: item && item.evidence_ids });
  }
  const thresholdErrors = [];
  for (const [ruleId, source] of Object.entries(want.threshold_sources || {})) {
    const item = first.findings.find((finding) => finding.rule_id === ruleId);
    if (!item || item.threshold.source !== source) thresholdErrors.push({ rule_id: ruleId, expected: source, actual: item && item.threshold.source });
  }
  const evidenceIds = new Set(testCase.snapshot.evidence.map((item) => item.evidence_id));
  const dangling = first.findings.flatMap((item) => item.evidence_ids.filter((id) => !evidenceIds.has(id)));
  if (missing.length || forbidden.length || extra.length || evidenceErrors.length || thresholdErrors.length || dangling.length) failures.push({ case: testCase.id, missing, forbidden, extra, evidence_errors: evidenceErrors, threshold_errors: thresholdErrors, dangling });
  else if (!jsonOutput && !preview) console.log(`${testCase.id}: PASS (${actualRules.length} findings)`);
}

if (selected && !inputs.cases.some((item) => item.id === selected)) failures.push({ case: selected, error: "unknown case" });
assert.throws(() => rules.evaluate(inputs.cases[0].snapshot, { typo: true }), /unknown config field/);
assert.throws(() => rules.evaluate(inputs.cases[0].snapshot, { thresholds: { "transport.error_rate.v1": -1 } }), /invalid threshold/);
assert.strictEqual(rules.evaluate(inputs.cases[1].snapshot, { disabled_groups: rules.REGISTRY.map((item) => item.group) }).findings.length, 0, "disabling all groups must leave snapshot evaluation available");
const projectThreshold = rules.evaluate(inputs.cases[1].snapshot, { thresholds: { "transport.error_rate.v1": 2 } }, { thresholds: { "transport.error_rate.v1": 99 } }).findings[0];
assert.strictEqual(projectThreshold.threshold.source, "project", "project threshold must override session baseline");

if (preview) console.log(JSON.stringify(actualPreview, null, 2));
else if (jsonOutput || failures.length) console.log(JSON.stringify({ valid: failures.length === 0, case_count: selected ? 1 : inputs.cases.length, failures }, null, 2));
else console.log(`diagnostic rules: PASS (${inputs.cases.length} golden cases, ${rules.REGISTRY.length} rules)`);
if (failures.length) process.exit(1);
