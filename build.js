#!/usr/bin/env node
/**
 * Reason Check build script.
 *
 * Validates src/scenarios.json against the schema, runs the topic-balance
 * audit, injects the bank into src/template.html, and writes:
 *   - index.html   (full standalone document, deployable anywhere)
 *   - preview.html (body-only content, for claude.ai artifact previews)
 *
 * Usage: node build.js
 */
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const FAMILIES = ["causation", "posthoc", "baserates", "anecdotes", "numbers", "echo"];
const VALENCES = ["leans-left", "leans-right", "neutral"];
const STATUSES = ["draft", "playtested", "validated"];
const ROLES = ["flawed", "clean", "over"];
const MIN_PER_FAMILY = 2; // the app draws 2 per family per session

function fail(msg) {
  console.error("BUILD FAILED: " + msg);
  process.exit(1);
}

const scenarios = JSON.parse(fs.readFileSync(path.join(ROOT, "src", "scenarios.json"), "utf8"));

/* ---------- Schema validation ---------- */
const ids = new Set();
scenarios.forEach((s, i) => {
  const where = `scenario ${i} (${s.id || "no id"})`;
  if (!s.id || ids.has(s.id)) fail(`${where}: missing or duplicate id`);
  ids.add(s.id);
  if (!FAMILIES.includes(s.family)) fail(`${where}: unknown family "${s.family}"`);
  if (!VALENCES.includes(s.valence)) fail(`${where}: unknown valence "${s.valence}"`);
  if (!STATUSES.includes(s.status)) fail(`${where}: unknown status "${s.status}"`);
  if (!s.context || !s.question) fail(`${where}: missing context or question`);
  if (!Array.isArray(s.body) || s.body.length < 1) fail(`${where}: body must be a non-empty array`);
  if (!Array.isArray(s.statements) || s.statements.length !== 3) fail(`${where}: needs exactly 3 statements`);
  const roles = s.statements.map((st) => st.role).sort();
  if (roles.join(",") !== ROLES.slice().sort().join(",")) fail(`${where}: statements must be one each of ${ROLES.join("/")}`);
  s.statements.forEach((st) => { if (!st.t) fail(`${where}: statement missing text`); });
  if (!s.explain || !s.explain.tempting || !s.explain.clean || !s.explain.rule) fail(`${where}: explain needs tempting/clean/rule`);
});

/* ---------- Coverage check ---------- */
const perFamily = {};
FAMILIES.forEach((f) => (perFamily[f] = scenarios.filter((s) => s.family === f).length));
FAMILIES.forEach((f) => {
  if (perFamily[f] < MIN_PER_FAMILY) fail(`family "${f}" has ${perFamily[f]} scenarios; needs at least ${MIN_PER_FAMILY}`);
});

/* ---------- Topic-balance audit ----------
 * The flawed reading of each scenario flatters somebody's priors. The bank
 * must never skew toward correcting one worldview more than the other. */
const byValence = {};
VALENCES.forEach((v) => (byValence[v] = scenarios.filter((s) => s.valence === v).length));
const skew = Math.abs(byValence["leans-left"] - byValence["leans-right"]);
if (skew > 1) fail(`balance audit: leans-left=${byValence["leans-left"]} vs leans-right=${byValence["leans-right"]} (skew ${skew} > 1)`);

/* ---------- Inject & write ---------- */
const template = fs.readFileSync(path.join(ROOT, "src", "template.html"), "utf8");
if (!template.includes("__SCENARIOS__")) fail("template.html is missing the __SCENARIOS__ placeholder");
const body = template.replace("__SCENARIOS__", JSON.stringify(scenarios, null, 0));

const page =
  '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
  "</head>\n<body>\n" + body + "\n</body>\n</html>\n";

fs.writeFileSync(path.join(ROOT, "index.html"), page, "utf8");
fs.writeFileSync(path.join(ROOT, "preview.html"), body, "utf8");

console.log(`OK: ${scenarios.length} scenarios (${FAMILIES.map((f) => f + ":" + perFamily[f]).join(", ")})`);
console.log(`Balance: leans-left=${byValence["leans-left"]}, leans-right=${byValence["leans-right"]}, neutral=${byValence["neutral"]}`);
console.log("Wrote index.html and preview.html");
