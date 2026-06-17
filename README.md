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
├── .claude-plugin/
│   ├── plugin.json                # plugin manifest (enables /plugin install)
│   └── marketplace.json           # marketplace catalog (enables /plugin marketplace add)
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

## Install

Two pathways. **A** is the easiest for others — installs from GitHub with
auto-updates. **B** needs no plugin system and is handy for hacking on the skill.

### A. Plugin marketplace (recommended, installs from GitHub)

This repo ships a marketplace manifest (`.claude-plugin/marketplace.json`) and a
plugin manifest (`.claude-plugin/plugin.json`), so it is installable as a plugin.
Inside any Claude Code session, run:

```text
/plugin marketplace add ianhussey/trustworthiness-assessment-skill
/plugin install trustworthiness-assessment@ianhussey-skills
```

The first command registers this repo as a marketplace named `ianhussey-skills`;
the second installs the `trustworthiness-assessment` plugin from it. Update later
with `/plugin marketplace update ianhussey-skills`. Installing only *fetches* the
repo — no code runs until you invoke the skill (see [Security](#scope--security)).

### B. Manual clone (no plugin system)

A skill is just a folder with `SKILL.md` at its root, so you can drop this repo
straight into a skills directory:

```sh
git clone https://github.com/ianhussey/trustworthiness-assessment-skill \
  ~/.claude/skills/trustworthiness-assessment            # personal, all projects
# or, per project:
git clone https://github.com/ianhussey/trustworthiness-assessment-skill \
  /path/to/project/.claude/skills/trustworthiness-assessment
```

Update with `git -C <that dir> pull`. (The folder name need not match the
`name:` in `SKILL.md`, but a clean name is tidier.)

## Using the skill in Claude

Once installed it is **auto-discovered** on the next session start — no enable
step — across the Claude Code CLI, desktop app, and project sessions. Two ways to
use it:

- **Invoke directly** from the `/` menu — type `/` and pick
  `trustworthiness-assessment` (plugin-installed skills are namespaced, so it may
  appear as `trustworthiness-assessment:trustworthiness-assessment`; run `/help`
  after install to see the exact name). Then point it at the paper, e.g.
  *"assess the PDF in `pdfs/`, the registration is the CSV beside it."*
- **Let Claude trigger it** by describing the task in plain language — e.g.
  *"do a trustworthiness assessment of this trial"*, *"can these reported numbers
  be trusted?"*, *"GRIM-check this baseline table"*, *"recalculate the baseline
  p-values"*. The `description` in `SKILL.md` is written to fire on these.

Give Claude the article (PDF/text) and, for a trial, the registration record; it
then works the Step 0–5 workflow and produces the classified verdict.

## R dependencies

`scrutiny`, `statcheck`, `metafor`, `tidyverse`, `kableExtra` (all CRAN) and
[`recalc`](https://github.com/ianhussey/recalc) — Ian Hussey's package:

```r
# install.packages("remotes")
remotes::install_github("ianhussey/recalc")
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
