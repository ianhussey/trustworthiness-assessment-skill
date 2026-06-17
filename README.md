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

## Where this skill runs (read first)

This skill's engine is **R + Quarto + your local files** (PDFs) + the local
[`recalc`](https://github.com/ianhussey/recalc) package. So it must run on a
surface that has a local toolchain and local file access — i.e. **Claude Code on
your own machine** (the terminal CLI, the Claude Code desktop app, or the VS Code
/ JetBrains extensions).

It will **not** run in the consumer **Claude Desktop app** (the claude.ai-login
app) or in **Claude Cowork**: those run code in a Python-focused sandbox with no
R, no Quarto, and no access to your local files or local packages — so the
quantitative checks (GRIM, `recalc`, `quarto render`) cannot execute there even
if the skill text loads. You can *add* and *invoke* the skill in those surfaces,
but the analysis will not run. Use Claude Code on your own machine for this skill.

## Install

### A. Local skills folder (works everywhere Claude Code runs — recommended)

A skill is just a folder with `SKILL.md` at its root. Drop this repo into a Claude
Code skills directory and it is auto-discovered:

```sh
# personal (all projects):
git clone https://github.com/ianhussey/trustworthiness-assessment-skill \
  ~/.claude/skills/trustworthiness-assessment
# or symlink an existing local clone instead of re-cloning:
ln -sfn /path/to/trustworthiness-assessment-skill \
  ~/.claude/skills/trustworthiness-assessment
# or per project:
git clone https://github.com/ianhussey/trustworthiness-assessment-skill \
  /path/to/project/.claude/skills/trustworthiness-assessment
```

Update with `git -C <that dir> pull`. The folder name need not match the `name:`
in `SKILL.md`, but a clean name is tidier. **Note:** if `~/.claude/skills/` did
not exist when your session started, **restart Claude Code** so it begins
watching the new directory (an existing skills dir picks up additions live).

### B. Plugin marketplace — **terminal CLI / IDE only**

The `/plugin` marketplace flow is supported **only in the Claude Code terminal
CLI and the IDE extensions** — it is *not* available in the Claude Code desktop
app or the consumer Claude Desktop app. Where it is available, this repo ships the
manifests (`.claude-plugin/marketplace.json` + `plugin.json`) so you can run:

```text
/plugin marketplace add ianhussey/trustworthiness-assessment-skill
/plugin install trustworthiness-assessment@ianhussey-skills
```

Update later with `/plugin marketplace update ianhussey-skills`. If `/plugin`
reports it "isn't available in this environment", use route **A** instead — it
works on every Claude Code surface. Installing by either route only *fetches* the
repo; no code runs until you invoke the skill (see [Security](#scope--security)).

## Using the skill in Claude

Once installed the skill is **auto-discovered** at session start — no enable
step. In every surface there are two ways to use it:

- **Invoke directly** from the `/` menu — type `/` and pick
  `trustworthiness-assessment` (if installed as a plugin it may be namespaced,
  e.g. `trustworthiness-assessment:trustworthiness-assessment`; run `/help` to see
  the exact name). Then point it at the paper, e.g. *"assess the PDF in `pdfs/`;
  the registration is the CSV beside it."*
- **Let Claude trigger it** by describing the task — e.g. *"do a trustworthiness
  assessment of this trial"*, *"can these reported numbers be trusted?"*,
  *"GRIM-check this baseline table"*, *"recalculate the baseline p-values"*. The
  `description` in `SKILL.md` is written to fire on these.

Give Claude the article (PDF/text) and, for a trial, the registration record; it
then works the Step 0–5 workflow and produces the classified verdict.

### Claude Code desktop app / terminal / IDE (runs fully)

This is the skill's home — local R, Quarto, your files and `recalc` are all
available.

1. Install via route **A** (`~/.claude/skills/trustworthiness-assessment`).
2. **If `~/.claude/skills/` did not exist before, restart the app once** so it
   begins watching the directory; afterwards, edits are picked up live.
3. Invoke from the `/` menu or in natural language (above).
4. *Troubleshooting:* if the skill does not appear after a restart, restart again
   and run `/help` to confirm it loaded — custom skills in `~/.claude/skills/` are
   occasionally slow to be discovered.

### Claude Cowork (can invoke, but the analysis will not run)

Cowork uses a plugin UI rather than `/plugin` commands, and runs in a
Python-focused sandbox without R/Quarto or access to your local files — so it can
load the *method text* but cannot execute the R checks.

1. Add the marketplace: **Customize → Plugins → "+" → Add marketplace**, pointing
   at `ianhussey/trustworthiness-assessment-skill` (org admins can instead
   GitHub-sync the repo into a managed marketplace), then install the plugin.
2. Invoke via `/` in the sidebar or in natural language.
3. **Expect the quantitative steps to fail** (no R/Quarto/local files). For real
   assessments use Claude Code on your machine; treat Cowork and the consumer
   Claude Desktop app as non-runners for this skill.

## Dependencies (one-time local setup)

Install **R** and **Quarto** on your machine, then the R packages — `scrutiny`,
`statcheck`, `metafor`, `tidyverse`, `kableExtra` (all CRAN) and
[`recalc`](https://github.com/ianhussey/recalc) (Ian Hussey's package):

```r
install.packages(c("tidyverse", "metafor", "scrutiny", "statcheck", "kableExtra", "remotes"))
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

## Scope & security

**Security.** Installing this skill by either route only *fetches* files — no
code runs at install time. `scripts/helpers.R` executes only when you invoke the
skill and Claude runs the analysis, the same trust boundary as any code you clone
and run. Review before use.

**Scope.** This skill produces a *starting point*, not a verdict to act on
unchecked. Its findings describe what does and does not cohere in the reported
numbers; they do not impute intent. Re-verify the arithmetic against the article
and have a statistician review impossibility claims before treating any finding as
established or contacting a journal or author.
