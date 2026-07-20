"use strict";

const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const rules = require("./diagnostic_rules.js");
const snapshots = require("./diagnostic_snapshot.js");

const repoRoot = path.join(__dirname, "..", "..", "..");
const boardRoot = path.join(__dirname, "..", "fixtures", "ai_debug", "board");
const manifest = JSON.parse(fs.readFileSync(path.join(boardRoot, "qualification_manifest.json"), "utf8"));

function sha256File(filename) {
  return crypto.createHash("sha256").update(fs.readFileSync(filename)).digest("hex");
}

(async () => {
  let bound = 0;
  for (const scenario of manifest.scenarios) {
    assert.strictEqual(scenario.qualification_status, "passed", `${scenario.id}: qualification is pending`);
    if (!scenario.input_snapshot) continue;
    const inputPath = path.join(boardRoot, scenario.input_snapshot);
    const baselinePath = path.join(boardRoot, scenario.baseline_snapshot);
    const input = JSON.parse(fs.readFileSync(inputPath, "utf8"));
    const baseline = JSON.parse(fs.readFileSync(baselinePath, "utf8"));
    for (const [label, snapshot] of [["input", input], ["baseline", baseline]]) {
      const verified = await snapshots.verify(snapshot);
      assert(verified.valid, `${scenario.id}: ${label} snapshot: ${verified.errors.join("; ")}`);
      const sourcePath = path.join(repoRoot, snapshot.provenance.source_path);
      assert.strictEqual(sha256File(sourcePath), snapshot.provenance.source_sha256,
        `${scenario.id}: ${label} source capture hash mismatch`);
    }
    assert.strictEqual(input.provenance.baseline_snapshot, path.basename(baselinePath),
      `${scenario.id}: baseline relationship mismatch`);
    const result = rules.evaluate(input);
    const actualKinds = new Set(input.evidence.map((item) => item.kind));
    for (const kind of scenario.required_evidence) assert(actualKinds.has(kind), `${scenario.id}: missing evidence kind ${kind}`);
    const actualRules = result.findings.map((finding) => finding.rule_id);
    for (const ruleId of scenario.expected_rules) assert(actualRules.includes(ruleId), `${scenario.id}: missing ${ruleId}`);
    for (const ruleId of scenario.forbidden_rules || []) assert(!actualRules.includes(ruleId), `${scenario.id}: forbidden ${ruleId}`);
    const evidenceIds = new Set(input.evidence.map((item) => item.evidence_id));
    for (const finding of result.findings) {
      for (const evidenceId of finding.evidence_ids) assert(evidenceIds.has(evidenceId), `${scenario.id}: dangling ${evidenceId}`);
    }
    const baselineResult = rules.evaluate(baseline);
    assert.strictEqual(baselineResult.findings.length, 0, `${scenario.id}: unmodified baseline must recover to no findings`);
    bound += 1;
  }
  console.log(`board evidence binding: PASS (${bound} bound scenarios, source records and recovery verified)`);
})().catch((error) => { console.error(`FAIL: ${error.message}`); process.exit(1); });
