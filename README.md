# trustworthiness-assessment-skill

A [Claude skill](https://docs.claude.com/en/docs/claude-code/skills) for
conducting **forensic trustworthiness assessments** of research articles and
clinical trials — judging whether reported results and conclusions can be
*believed* (possibility, plausibility, claim–evidence alignment), which is
narrower than general peer review.

## Layout

```
trustworthiness-assessment-skill/
├── SKILL.md                       # skill driver: trigger description, workflow, output format
├── references/
│   ├── forensic-method.md         # canonical method + stance (Step 0–5 taxonomy) — read first
│   └── r-cookbook.md              # scrutiny / recalc / statcheck / metafor API notes + snippets
├── assets/
│   └── assessment_template.qmd    # Quarto scaffold to copy per paper (sources helpers.R)
└── scripts/
    └── helpers.R                  # analysis functions (single source of truth)
```

`SKILL.md` is intentionally lean: it drives the workflow and points to the
references, which load on demand. The method itself lives in
`references/forensic-method.md`.

## Install as a skill

Copy or symlink the repo into your Claude skills directory under the skill's
name (`trustworthiness-assessment`):

```sh
ln -s "$PWD" ~/.claude/skills/trustworthiness-assessment        # personal, all projects
# or, per project:
ln -s "$PWD" /path/to/project/.claude/skills/trustworthiness-assessment
```

## R dependencies

`scrutiny`, `statcheck`, `metafor`, `tidyverse`, `kableExtra` (all CRAN) and
[`recalc`](https://github.com/) — Ian Hussey's package, installed locally:

```r
devtools::install("~/git/recalc")
```

If `recalc` is absent, skip the baseline-p step and note it. See
`references/r-cookbook.md` for the per-package API notes (including the
scrutiny ≥0.6 `digits_x` change).

## Running an assessment

1. Copy `assets/assessment_template.qmd` into the paper's repo and copy
   `scripts/helpers.R` alongside it.
2. Hand-key the reported statistics into the data objects; mark each scale
   integer vs non-integer.
3. Work the Step 0–5 workflow and `quarto render`.

A complete worked example (Pu et al. 2026, *BMC Psychiatry*) lives in the
sibling repo `trustworthinesss-assessment-pu-et-al-2026`.

## Scope & caution

This skill produces a *starting point*, not a verdict to act on unchecked. Its
findings describe what does and does not cohere in the reported numbers; they do
not impute intent. Re-verify the arithmetic against the article and have a
statistician review impossibility claims before treating any finding as
established or contacting a journal or author.
