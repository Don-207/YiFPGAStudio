/* YiFPGA Studio M29 diagnosis_result v1 validator. */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.YiFPGADiagnosisValidator = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";
  const MAX_BYTES = 256 * 1024;
  const REQUIRED = ["schema_version", "summary", "observed_facts", "hypotheses", "recommended_actions", "insufficient_evidence", "metadata"];
  const MUTATING = /\b(write|program|flash|delete|remove|reset|modify|install|execute|run command)\b/i;
  function clone(value) { return JSON.parse(JSON.stringify(value)); }
  function validate(raw, options = {}) {
    const errors = []; let value;
    const serialized = typeof raw === "string" ? raw : JSON.stringify(raw);
    if (serialized.length > (options.maxBytes || MAX_BYTES)) return { valid: false, errors: ["response_too_large"], result: null };
    try { value = typeof raw === "string" ? JSON.parse(raw) : clone(raw); } catch (_) { return { valid: false, errors: ["invalid_json"], result: null }; }
    for (const secret of options.forbiddenValues || []) if (secret && serialized.includes(secret)) errors.push("secret_echo_detected");
    if (!value || typeof value !== "object" || Array.isArray(value)) return { valid: false, errors: ["result_must_be_object"], result: null };
    REQUIRED.forEach((key) => { if (!Object.hasOwn(value, key)) errors.push(`missing_field:${key}`); });
    if (value.schema_version !== 1) errors.push("unsupported_schema_version");
    if (typeof value.summary !== "string") errors.push("invalid_summary");
    for (const key of ["observed_facts", "hypotheses", "recommended_actions", "insufficient_evidence"]) if (!Array.isArray(value[key])) errors.push(`invalid_type:${key}`);
    if (!value.metadata || typeof value.metadata !== "object" || Array.isArray(value.metadata)) errors.push("invalid_type:metadata");
    if (errors.length) return { valid: false, errors, result: null };
    const allowed = new Set(options.evidenceIds || []); const localRules = new Set(options.ruleIds || []);
    const checkEvidence = (item, path) => {
      if (!Array.isArray(item.evidence_ids)) { errors.push(`invalid_evidence_ids:${path}`); return; }
      item.evidence_ids.forEach((id) => { if (!allowed.has(id)) errors.push(`unknown_evidence:${id}`); });
    };
    value.observed_facts.forEach((item, index) => checkEvidence(item, `observed_facts[${index}]`));
    value.hypotheses.forEach((item, index) => {
      checkEvidence(item, `hypotheses[${index}]`);
      if (!Number.isFinite(item.confidence) || item.confidence < 0 || item.confidence > 1) errors.push(`invalid_confidence:hypotheses[${index}]`);
      if (!item.evidence_ids || !item.evidence_ids.length) { item.status = "unverified"; item.confidence = Math.min(Number(item.confidence) || 0, 0.25); }
      const conflicts = Array.isArray(item.contradicts_rule_ids) ? item.contradicts_rule_ids.filter((id) => localRules.has(id)) : [];
      if (conflicts.length) item.conflicts_with_local_findings = conflicts.sort();
    });
    value.recommended_actions.forEach((item, index) => {
      if (!item || typeof item !== "object" || typeof item.action !== "string") errors.push(`invalid_action:recommended_actions[${index}]`);
      else if (MUTATING.test(item.action) || item.safety === "mutating") item.safety = "requires_manual_confirmation";
      else item.safety = item.safety === "read_only" ? "read_only" : "manual";
    });
    if (errors.length) return { valid: false, errors: Array.from(new Set(errors)), result: null };
    value.metadata.validation_status = "validated";
    return { valid: true, errors: [], result: value };
  }
  return { MAX_BYTES, validate };
});
