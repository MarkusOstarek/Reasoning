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
  if (!Array.isArray(s.sources) || s.sources.length < 1) fail(`${where}: needs at least 1 source`);
  s.sources.forEach((src) => {
    if (!src.label || !src.url || !/^https?:\/\//.test(src.url)) fail(`${where}: each source needs a label and an http(s) url`);
  });
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

// Webfonts only in the deployed page; preview.html (artifact) has a strict CSP
// and falls back to the designed system stacks.
const fonts =
  '<link rel="preconnect" href="https://fonts.googleapis.com">\n' +
  '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n' +
  '<link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,500..800;1,9..144,500..800&family=Libre+Franklin:wght@400;600;700;800&display=swap" rel="stylesheet">\n';

const SITE_URL = "https://markusostarek.github.io/Reasoning/";

// Hoist the template's <title> into <head> for the deployed page.
const titleMatch = body.match(/^<title>.*?<\/title>\s*/);
const title = titleMatch ? titleMatch[0].trim() : "<title>Reason Check</title>";
const pageBody = titleMatch ? body.slice(titleMatch[0].length) : body;

const meta =
  title + "\n" +
  '<meta name="description" content="Twelve everyday scenarios — a chart at a family dinner, a viral post, a pile of reviews. Rate what the evidence supports and get a profile of your reasoning blind spots. Free, private, ten minutes.">\n' +
  '<link rel="canonical" href="' + SITE_URL + '">\n' +
  '<meta property="og:title" content="Reason Check — what would you conclude?">\n' +
  '<meta property="og:description" content="Twelve everyday scenarios. Rate what the evidence supports, find your reasoning blind spots. Plus a scenario of the day.">\n' +
  '<meta property="og:url" content="' + SITE_URL + '">\n' +
  '<meta property="og:type" content="website">\n' +
  '<meta property="og:image" content="' + SITE_URL + 'og.png">\n' +
  '<meta property="og:image:width" content="1200">\n' +
  '<meta property="og:image:height" content="630">\n' +
  '<meta name="twitter:card" content="summary_large_image">\n' +
  '<meta name="theme-color" content="#1b2440">\n' +
  '<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🧭</text></svg>">\n';

const page =
  '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
  meta + fonts +
  "</head>\n<body>\n" + pageBody + "\n</body>\n</html>\n";

fs.writeFileSync(path.join(ROOT, "index.html"), page, "utf8");
fs.writeFileSync(path.join(ROOT, "preview.html"), body, "utf8");

console.log(`OK: ${scenarios.length} scenarios (${FAMILIES.map((f) => f + ":" + perFamily[f]).join(", ")})`);
console.log(`Balance: leans-left=${byValence["leans-left"]}, leans-right=${byValence["leans-right"]}, neutral=${byValence["neutral"]}`);
console.log("Wrote index.html and preview.html");
