---
name: trustworthiness-assessment
description: >-
  Forensic trustworthiness assessment of a research article or clinical trial —
  judging whether its reported results and conclusions can be believed
  (possibility, plausibility, claim–evidence alignment), which is narrower than
  general peer review. Use when asked to assess, audit, forensically check, or
  sanity-check a paper's numbers or claims; to run GRIM/GRIMMER, statcheck,
  baseline p-value recalculation, effect-size sanity, implied pre–post
  correlation, participant-flow, or trial-registration consistency checks; or to
  produce a classified verdict (trustworthy as reported / concerns pending
  clarification / not trustworthy as reported). Triggers include "trustworthiness
  assessment", "forensic check", "can these numbers be trusted", "audit this
  paper/trial", "GRIM check", "recalculate the baseline p-values".
---

# Trustworthiness assessment

A **forensic** assessment of a research article: can its reported results and
conclusions be *believed*? This is not peer review — you are not judging novelty,
importance, or power. You are judging three things, hardest first:

1. **Possibility** — could the reported numbers exist at all?
2. **Plausibility** — are they believable given the design and the field?
3. **Misalignment** — even if real, do the methods/analyses support the claims?

This is a **falsification** task: find what is wrong, establish how wrong, say so
plainly. A clean result ("I found nothing impossible") is a valid, valuable
outcome — do not manufacture problems.

## Before you start (hard requirements)

- **Work only from the actual article.** If you cannot retrieve the full text,
  say so and ask for it. Never reconstruct a paper from its abstract or memory.
- **Get the registration and any supplements.** For a trial, pull the
  ClinicalTrials.gov (or other) record and compare it field-by-field to the
  paper — registries drift less than manuscripts.
- **Extract every estimate at full reported precision — including trailing
  zeros — and record its decimal count explicitly.** GRIM/GRIMMER and every
  recalc interval depend on the exact number of decimals a value was *printed*
  to ("13.50" is 2 dp, "0.050" is 3 dp). R silently drops trailing zeros
  (`13.50` → `13.5`), so the keyed number cannot carry the precision — capture a
  `*_digits` count for each value as you extract, straight from the paper. Pass
  it to every `digits` / `digits_x` / `*_digits` argument. **Never default or
  infer a digit count** — the helpers and `recalc` deliberately refuse to, and
  the wrong count flips verdicts.
- **Read `references/forensic-method.md` first.** It is the canonical method
  (full Step 0–5 taxonomy + the stance you must adopt). This SKILL.md is only the
  driver. Re-read its **Stance** section before judging anything: burden of proof
  is on the authors; never adjudicate intent or accuse; think stupider (check the
  boring arithmetic first); don't reward incoherence; **no false positives**.

## Workflow

Run these in order. The detail for each lives in `references/forensic-method.md`;
the R for each lives in `scripts/helpers.R` (API notes in
`references/r-cookbook.md`).

0. **Load-bearing claim** — state in one sentence the result the contribution
   rests on. Note whether it is the pre-registered primary outcome or a secondary
   /post-hoc result promoted to the headline.
0.5 **Public record** (cheap, do before arithmetic) — retraction/expression-of-
   concern on this paper; the team's track record; registration consistency.
   Tag `[GOVERNANCE]`.
1. **Numerical sanity** — recompute central statistics and show the arithmetic:
   F ↔ partial η² (`recalc::recalc_partial_eta_from_f`); r → t → p;
   **participant-flow forensics** (do all the n's add up across CONSORT/text/
   tables? does df imply one N?); and, for a trial baseline table, **baseline
   p-value recalculation** (`recalc_baseline_t`, `recalc_baseline_chisq`). If the
   headline numbers cohere, say so explicitly.
2. **Possibility** — GRIM/GRIMMER on integer-scored means
   (`scrutiny::grim(x, n, digits_x = …)` / `grimmer_map`), run *separately by
   group × timepoint*. When a block fails at its reported n, search alternative n
   (`grim_n_profile`, `implied_sum`). Also bounds (Popoviciu, Bhatia–Davis,
   |r|≤1, estimate-in-CI, PSD correlation matrix) and coherence. Tag genuine
   failures `[IMPOSSIBLE]` with arithmetic.
3. **Plausibility** — derive the effect sizes the paper omits (`metafor::escalc`)
   and test them against the design ceiling and the field. For pre/post data,
   check **change-score coherence** with `recalc`: `recalc::recalc_prepost_r()`
   when a change SD is reported (or an independent t on change scores), or
   `recalc::recalc_prepost_r_from_f()` from a 2×2 RM-ANOVA interaction F. recalc
   returns the implied-r **interval** — *possibility* is read off it (the SDs
   can't coexist when the interval lies wholly outside [−1, 1] → `[IMPOSSIBLE]`);
   *plausibility* of a possible r is then judged with `prepost_r_plausibility()`
   in `helpers.R` (r < 0 or r > .95 → `[IMPLAUSIBLE]`; bands follow DeBruine's
   `within`). Watch the SE-vs-SD swap. Carlisle-style baseline distribution (weak
   with few variables).
4. **Misalignment** — measure↔construct, test↔inference, claim↔evidence. Tag
   `[MISALIGNMENT]`.
5. **Conduct/governance/transparency** — ethics/registration timing, feasibility,
   data availability, duplicate text/figures, consistency across the team's
   companion papers. Tag `[GOVERNANCE]`.

## Running the analysis

1. Copy `assets/assessment_template.qmd` into the target paper's repo (e.g. as
   `code/<firstauthor>_<year>_trustworthiness_assessment.qmd`) **and copy
   `scripts/helpers.R` alongside it** (the template does `source("helpers.R")`).
2. Hand-key every reported statistic into the `dat` / `anova_tab` / baseline
   objects **at full reported precision (incl. trailing zeros), with an explicit
   `*_digits` column for each value** (see the precision rule above). Mark each
   scale integer vs non-integer (GRIM only applies to integer totals; e.g. Zung
   SDS/SAS index scores are *not* integer-grained).
3. Work the steps; render with `quarto render`. Every quantitative claim in the
   writeup must be reproducible from a chunk.

## Output format (the deliverable)

Write the assessment in this order:

1. **Overall classification** — exactly one, justified in a sentence:
   *trustworthy as reported* / *concerns pending clarification* (specify what
   would resolve them) / *not trustworthy as reported*.
2. **Bottom line** — 1–2 sentences: can the headline result be trusted, and why.
3. **Numerical sanity check** — what you recomputed and whether it held.
4. **Findings, ordered by severity** — each tagged `[IMPOSSIBLE]` /
   `[IMPLAUSIBLE]` / `[MISALIGNMENT]` / `[GOVERNANCE]`, with arithmetic shown,
   leading with whatever undermines the load-bearing claim.
5. **What I could not check** — things needing data, supplements, or expertise.

Always close with the reader caution: this is a starting point, not a verdict to
act on unchecked — re-verify the arithmetic against the article and have a
statistician review impossibility claims before treating any finding as
established or contacting anyone. Describe issues; do not accuse.

## Files

- `references/forensic-method.md` — canonical method + stance (read first).
- `references/r-cookbook.md` — scrutiny / recalc / statcheck / metafor API notes
  and snippets (incl. the scrutiny 0.6.x `digits_x` gotcha).
- `assets/assessment_template.qmd` — the scaffold to copy per paper.
- `scripts/helpers.R` — the analysis functions (single source of truth).
