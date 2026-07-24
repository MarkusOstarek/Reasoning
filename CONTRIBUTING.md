# Contributing to Reason Check

Two kinds of contribution matter here, and they need very different things from you.

**Disputing a verdict or proposing a scenario** needs no code at all — open an
issue. This is the most valuable thing most people can do, and the editorial bar
below is the whole skill.

**Changing the app** needs the build. See "Working on the code".

---

## Disputing a verdict

If you think a scenario's sound reading is wrong, ambiguous, or arguable — say
so. That is not a nuisance, it is the point: an instrument about careful
reasoning cannot ask to be taken on faith.

Open an issue with the scenario id (every explanation carries a "Dispute it"
link that pre-fills this) and say specifically what is wrong. "The clean answer
overclaims because X" beats "this one felt off".

**How disputes are triaged.** Every dispute gets one of four outcomes, stated
publicly on the issue:

| Outcome | Meaning |
|---|---|
| **Fixed** | The objection held. Statement or explanation changed. |
| **Pinned** | The objection held, and the fix was to state the missing premise in the vignette so the reasoning question stays clean. |
| **Explained** | The scenario stands; the reasoning is set out on the issue and, if others are likely to raise it, added to the explanation. |
| **Cut** | The scenario could not be made defensible and was removed from the bank. |

A scenario that survives a dispute should end up *better documented*, not just
defended. If two people raise the same objection independently, that is a defect
in the scenario even if the verdict is technically right.

## Proposing a scenario

Use the scenario proposal issue template — it asks for every field the schema
needs. You do not need to write JSON; a maintainer converts accepted proposals.

Every scenario must clear the editorial bar in [README.md](README.md#writing-scenarios--editorial-bar).
The rules that reject most proposals:

1. **The sound reading must clear "would ~95% of scientists sign off?"** If
   reasonable experts would dispute it, the scenario is poison for credibility.
2. **Claim only what the vignette grants**, what arithmetic on it yields, or
   what a cited source supports. Anything else gets hedged — or gets pinned in
   the vignette so it becomes a given rather than a claim.
3. **The flawed reading must be genuinely tempting** — the reading a smart
   person actually makes, in its strongest form. Never a strawman.
4. **The overshoot must overreach from the same evidence the player has.** An
   overshoot resting on a fact they cannot check ("this is only one study",
   "the industry funds this research") is not an overshoot: if the fact were
   true it would be the right answer.
5. **No surface tells.** The three statements must be indistinguishable by
   length, sentence count, punctuation and vocabulary — otherwise players learn
   to spot the answer instead of reasoning to it. This is machine-checked; see
   below.
6. **Tag the valence honestly.** The bank must not skew toward correcting one
   worldview. The build fails if it does.

## Working on the code

You need either Node **or** Windows PowerShell — not both.

```
node build.js                                        # or:
powershell -ExecutionPolicy Bypass -File build.ps1
```

Both validate the bank, run the balance audit, and write `index.html` and
`preview.html`. They are maintained in parallel and must produce **byte-identical**
output; CI checks this on every pull request. **A change to one is a change to
the other.**

Before opening a PR:

```
powershell -File tools/tells.ps1 -Strict     # no surface feature predicts a role
powershell -File tools/shot.ps1 -Url index.html -Width 390 -Out shot.png
```

`index.html` and `preview.html` are build outputs but are committed, because the
site is served straight from the repo. Rebuild and commit them with your change;
CI fails if they are stale.

Editing content? Change `src/scenarios.json`, never `index.html`.

### Things that are easy to break

- **Wording changes can re-introduce surface tells.** Softening an overshoot
  tends to shorten it and strip its absolute language, which is exactly what the
  audit watches. Run `tells.ps1 -Strict` after *any* wording pass, not just
  structural ones.
- **`.ps1` files need a UTF-8 BOM.** Windows PowerShell 5.1 reads BOM-less
  scripts as ANSI and mangles the em dashes and emoji.
- **Don't round-trip the bank through `ConvertTo-Json`** in PowerShell 5.1 — it
  escapes non-ASCII and the two builders stop agreeing.

## What this project will not do

Some things are refused on principle, so nobody wastes work on them:

- **No ads.** An attention-economy revenue stream inside a tool about the
  attention economy's failure modes poisons the premise.
- **No paywall on the test.** The free test is the asset everything else rests on.
- **No personal data, ever.** Answers stay in the browser. If aggregate usage
  counts are added they must be cookieless and anonymous, and the promise on the
  landing page must stay literally true.
- **No partisan framing.** The balance audit is not decoration. Careful
  reasoning isn't a team.
