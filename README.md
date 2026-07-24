# Reason Check

A friendly check-up for everyday reasoning. Twelve short scenarios — a chart at a family dinner, a viral post, a pile of testimonials — each with several possible readings. You rate how much you agree with each reading, then see which conclusions the evidence actually supports and get a profile of where your reasoning is sharp and where it's catchable.

**Why it exists:** the reasoning patterns that spread harmful nonsense online — correlation read as causation, hidden denominators, testimonial floods, cherry-picked windows, manufactured expert consensus — are learnable to resist. Existing tools test whether you can spot fake headlines; Reason Check tests whether you draw sound conclusions from *true* information, which is where most real-world persuasion happens.

## Principles

1. **No gotcha framing.** Scenarios are presented neutrally ("what would you conclude?"), never announced as traps. Teaching happens after each answer, not before.
2. **Balanced by construction.** Each scenario's flawed reading is tagged by which cultural worldview it flatters (`leans-left`, `leans-right`, `neutral`). The build fails if the bank skews more than ±1 between left and right. Careful reasoning isn't a team, and the site must never feel like one team educating the other.
3. **Both failure modes count.** Rating statements independently lets us measure credulity (agreeing with flawed readings) *and* blanket cynicism (rejecting sound ones). "Trust nothing" is also a reasoning failure, and every scenario includes an overcorrecting statement to detect it.
4. **Privacy by default.** Everything runs client-side. No accounts, no tracking, nothing stored.

## Architecture

Static, no framework, no runtime dependencies.

```
src/scenarios.json   The scenario bank (content lives here)
src/template.html    App shell: styles, markup, logic, with __SCENARIOS__ placeholder
build.ps1            Validates the bank, runs the balance audit, injects, emits outputs
build.js             Same build, Node version — kept in sync, byte-identical output
index.html           Built output — a single self-contained file, deployable anywhere
preview.html         Built output without the <html> wrapper (for artifact previews)
tools/shot.ps1       Screenshots the built page at any phone viewport (see below)
```

Check a layout change on a phone width without a phone:

```
tools\shot.ps1 -Url index.html -Width 320 -Out shot.png -Script "document.getElementById('btn-start').click()"
```

It drives headless Chrome over the DevTools Protocol, so the viewport is a real
device viewport — `--window-size` alone can't go below ~485px on Windows. Warns if
the page overflows horizontally at that width.

Build: `powershell -ExecutionPolicy Bypass -File build.ps1` — runs on the Windows
PowerShell that ships with the OS, nothing to install. `node build.js` is equivalent
if you have Node. Validation + balance audit run on every build and fail hard.

Both builders must stay in sync: a change to one is a change to the other. They are
verified by byte-comparing `index.html` and `preview.html` from each.

Each session draws 2 random scenarios per family (12 of 18 currently), so retakes get fresh material.

## Scenario schema

```jsonc
{
  "id": "kebab-case-slug",
  "family": "causation | posthoc | baserates | anecdotes | numbers | echo",
  "valence": "leans-left | leans-right | neutral",  // which worldview the FLAWED reading flatters
  "status": "draft | playtested | validated",
  "context": "At a family dinner",                  // where you'd encounter this
  "body": ["paragraph", "“quoted claim”"],          // the vignette (limited HTML allowed)
  "question": "What would you conclude?",
  "statements": [                                    // exactly one of each role, shuffled at runtime
    { "role": "flawed", "t": "the intuitive reading that doesn't hold up" },
    { "role": "clean",  "t": "what the evidence actually supports" },
    { "role": "over",   "t": "the overcorrection — blanket doubt/dismissal" }
  ],
  "explain": {
    "tempting": "why the flawed reading pulls people in — respectful, never mocking",
    "clean": "the clean reasoning, concretely, with the mechanism named",
    "rule": "a one-line memorable rule of thumb"
  },
  "sources": [                                       // at least 1 required; build fails without
    { "label": "Author year — what it establishes (venue)", "url": "https://..." }
  ]
}
```

Scoring: per scenario, discernment = (clean rating − flawed rating + 4) / 8, giving 0–1. Overall score is the mean × 100. The miss-pattern diagnosis compares mean agreement with flawed statements (credulity) against mean agreement with overshoots plus rejection of clean statements (cynicism).

## Writing scenarios — editorial bar

- The vignette must be realistic: something a person actually sees in a feed, chat, or conversation. Real-world numbers should be roughly accurate.
- The flawed reading must be genuinely tempting — the reading a smart person makes in the wild, stated in its strongest form, never a strawman.
- The clean reading must be defensible to a domain expert. The bar: would ~95% of scientists sign off on it? If reasonable experts would dispute it, the scenario is poison for credibility: cut it.
- A clean reading may assert only what the vignette grants, what arithmetic on it yields, or what a listed source supports. Anything else gets hedged, or gets pinned in the vignette ("the number, it turns out, is accurate") so it becomes a given rather than a claim.
- Where the empirical result is contested but the method isn't, name the comparison rather than announcing the result. "The measure that settles this is deaths per unit of energy" is unattackable; the ranking it produces invites a fight. Spend that fight only when the conclusion is robust to it.
- The overshoot must overreach from the same evidence the player has. An overshoot resting on a fact they cannot check ("this is one study", "the industry funds this research") is not an overshoot — if the fact were true it would be the right answer.
- Prefer conditional claims — about what this evidence can and cannot support — over claims about the world. They need far less foundation and are where the site's authority actually lives.
- The explanation names the mechanism, gives the reader the tool, and never sneers. The reader who fell for it should feel smarter, not scolded.
- Every empirical claim in an explanation must be sourced: peer-reviewed studies, official statistics, or recognized methodological explainers. At least one source per scenario is enforced by the build and displayed in the UI.
- Tag valence honestly and keep the audit green.

## Licence

- **Code** — MIT ([LICENSE](LICENSE))
- **Scenario bank and prose** — CC BY 4.0 ([LICENSE-CONTENT](LICENSE-CONTENT))

Deliberately permissive so the item bank can be adopted, translated, adapted and
validated without asking. Researchers: adapt it freely; open an issue if you need
a variant or a citable version.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Disputing a verdict or proposing a
scenario needs no code — both have issue templates. CI enforces the invariants on
every pull request: both builders produce byte-identical output, the bank
validates, the balance audit holds, no surface feature predicts a statement's
role, and the committed `index.html` is up to date.

## Measurement — an open decision

The site currently collects **nothing**, so completion rate is unknown and every
traction claim is a guess. This blocks the completion metric, the research
outreach, and grant applications alike (see [docs/traction-plan.md](docs/traction-plan.md)).

**The code is in place and switched off.** `src/template.html` has an
`ANALYTICS_ENDPOINT` constant, empty by default, and nothing is sent while it is
empty. To turn it on:

1. Create a free GoatCounter site (cookieless, open source, EU-hosted).
2. Set `ANALYTICS_ENDPOINT = "https://YOURCODE.goatcounter.com"` (no trailing slash).
3. Rebuild and commit.

It counts a visit plus four events — `started`, `completed`, `copied-results`,
`daily-played`. It is a pixel, not a third-party script: no external JavaScript
runs on the page, nothing is readable back, and no cookie is set.

**The privacy promise on the landing page is generated from that constant**
(`privacyLine()`), so switching the counter on rewrites the promise in the same
commit and the two cannot drift apart.

Two rules if it is added:

- **The landing-page promise must stay literally true.** "Your answers never
  leave your browser" survives aggregate counts; it does not survive anything
  keyed to a person.
- **Item-level response data must not be collected here.** Validation needs it,
  but it should be gathered by a research partner under their ethics approval
  and real consent — cleaner, more publishable, and it leaves the privacy
  promise intact.

## Roadmap

- [x] Core check-up: 12 scenarios drawn from a bank, rating-scale mechanic, profile + miss-pattern results
- [x] Scenario pipeline: schema, validation, balance audit
- [x] "Scenario of the day" with device-local streaks
- [x] Fact-check pass; sources on every scenario, shown in the UI and enforced by the build
- [x] Deployed: https://markusostarek.github.io/Reasoning/
- [x] Tell audit: no surface feature (length, sentence count, vocabulary) predicts a statement's role
- [x] Evidence pass: sound readings claim only what the vignette grants or a source supports
- [x] Licensed (MIT code, CC BY 4.0 content) so the bank can actually be adopted
- [x] CI, contribution docs, dispute triage policy — handoff-ready
- [x] Accessibility: radiogroup rating scale with keyboard support, AA contrast
- [x] Family profile presented with the uncertainty two items per family warrants
- [x] Two-axis scoring: discernment and overcorrection reported separately, never blended
- [x] Usage counter written and switched off; one constant turns it on
- [ ] Create the GoatCounter site and set `ANALYTICS_ENDPOINT` (blocks every traction number)
- [ ] Send the research outreach — longest latency item, don't gate it on polish
- [ ] Seed playtest, [protocol here](docs/playtest-protocol.md) — the gate before promotion
- [ ] Grow bank toward 40+ for daily rotation and to retire weak items. Note this
      does *not* fix the 2-items-per-family profile: that is limited by session
      length, not bank size. If a real profile is wanted, collapse six families
      into three broader dimensions (4 items each from the same 12-item test).
- [ ] Custom domain
- [ ] Share card (spoiler-free per-family profile image/text)
- [ ] "Scenario of the day" mode with streaks — the habit-forming loop
- [ ] Anonymized aggregate score collection → real percentiles ("sharper than X% of takers")
- [ ] Teacher mode: class code, aggregate class profile, discussion guide per scenario
- [ ] Research partnership for item validation (Cambridge SDM Lab methodology-compatible)
- [ ] Localization (scenarios translate well; they're everyday situations)

## License / status

Draft, pre-release. Scenario content and code by Markus Ostarek with Claude.
