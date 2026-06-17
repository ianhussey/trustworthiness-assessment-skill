# R cookbook — trustworthiness assessment

API notes and copy-paste snippets for the R tooling. Load `scripts/helpers.R`
first; it wraps most of this. Read this when you are writing the analysis chunks.

## Precision: never default or infer digit counts

Every granularity (GRIM/GRIMMER) and recalc check is a function of the **exact
reported precision** of each value — the decimals it was *printed* to, **including
trailing zeros** (`13.50` = 2 dp, `0.050` = 3 dp). R drops trailing zeros from
numerics (`13.50` → `13.5`), so the keyed number cannot carry precision: you must
record a digit count per value and pass it to every `digits` / `digits_x` /
`*_digits` argument.

- `scrutiny::grim()` and all `recalc_*` functions take **mandatory** digit
  arguments (no defaults) — this is deliberate, not friction.
- The skill helpers follow suit: `grim_n_profile(means, n_range, digits)` and
  `recalc_baseline_chisq(counts, p, p_digits)` require digits; `recalc_baseline_t`
  requires per-row `m_digits` / `sd_digits` / `p_digits` columns. There is **no**
  `p_decimals`-style inference helper — inferring digits from a numeric would miss
  trailing zeros and silently flip verdicts.
- Carry precision in the extracted data as explicit `*_digits` columns; for GRIM,
  `digits_x` may be a vector (per-value precision).

## Packages & install

| Package | Source | Used for |
|---|---|---|
| `scrutiny` | CRAN | GRIM / GRIMMER |
| `recalc` (≥ 0.6) | Ian Hussey's package (`remotes::install_github("ianhussey/recalc")`) | baseline-p & chi-sq recalc; pre–post r; partial-η² ↔ F |
| `statcheck` | CRAN | recompute p from t/F/r/χ² in reported *text* |
| `metafor` | CRAN | `escalc()` for SMD / effect sizes you derive |
| `tidyverse` | CRAN | wrangling, tables, plots |
| `kableExtra` | CRAN | `kable_classic()` tables |

If `recalc` is not installed the baseline-p step is skipped — note that in the
writeup rather than failing silently.

## GRIM (scrutiny ≥ 1.0 / 0.6.x gotcha)

`scrutiny::grim_map()` changed API. In **0.6.2** (and ≥1.0), `x` must be
**numeric** and the decimal count is passed as the **function argument**
`digits_x` — string-`x` columns (the old idiom) are *defunct* and throw a
confusing "specify digits_x" error.

```r
# CORRECT (0.6.2): the scalar grim() is vectorised over x (recycles n):
scrutiny::grim(x = c(15.95, 15.19), n = 26, digits_x = 2)            # FALSE TRUE
# the data-frame form (string-x columns are defunct; pass numeric + digits_x):
scrutiny::grim_map(tibble(x = c(15.95, 15.19), n = c(26L, 26L)), digits_x = 2)
scrutiny::grimmer_map(tibble(x = 8.96, sd = 5.237, n = 52L), digits_x = 2, digits_sd = 3)
```

Call `scrutiny::grim()` directly — the skill does **not** re-export GRIM (a
wrapper with a default `digits` would silently assume precision, the footgun
`scrutiny`'s mandatory `digits_x` exists to prevent). The skill adds only the
alternative-n *sweep*, `helpers.R::grim_n_profile(means, n_range, digits)`. GRIM
only applies to **integer totals** (sum of integer items). Per-item means use
`items = #items`. Zung SDS/SAS *index* scores (raw × 1.25) are NOT integer-grained
→ exclude.

### The high-value pattern: GRIM by block + alternative-n search

Run GRIM **separately by group × timepoint**. The signal is *asymmetry*: one
block ~100% consistent at its reported n while a sibling block ~100%
inconsistent. Then find which n reconciles the failing block:

```r
prof <- grim_n_profile(failing_block$mean, n_range = 15:40)   # tibble(n, consistent, total)
# a sharp single peak at n != reported  => undisclosed sample size
map_dfr(failing_block$mean, implied_sum, n = <peak_n>)        # residual ~0 confirms
```

A sharp peak at a different n points to undisclosed dropout / a per-protocol
subset / altered values (`[IMPOSSIBLE]` for the values as reported, cross-checked
against the test df). A flat profile points to non-integer data or genuinely
anomalous values.

## Baseline p-value recalculation (`recalc`)

Each baseline row reports group m/sd/n (or counts) AND a p, so each p can be
recomputed from the summary stats. `recalc` explores a multiverse (Student/Welch
× rounding bounds × direction) and returns whether the reported p falls inside
the recomputed `[min_p, max_p]` hull.

```r
r <- recalc::recalc_independent_t_p(m1, m2, sd1, sd2, n1, n2,
       m_digits = 2, sd_digits = 3, p = .921, p_digits = 3)
dplyr::distinct(r$reproduced)   # -> min_p, max_p, p_inbounds_hull (TRUE = reproduces)

g <- recalc::recalc_chisq_p(counts = matrix(c(a,b,c,d), nrow = 2, byrow = TRUE),
       p = .082, p_digits = 3)
dplyr::distinct(g$reproduced)
```

`helpers.R` wraps these as `recalc_baseline_t(df, n1, n2)` — `df` is one row per
continuous variable with columns `variable, m1, sd1, m2, sd2, p` **plus the
reported precision per row: `m_digits, sd_digits, p_digits`** (no defaults) — and
`recalc_baseline_chisq(counts, p, p_digits)` (p_digits required).

- **A reported p OUTSIDE its hull = `[IMPOSSIBLE]`** (cannot come from the reported
  m/sd/n under any standard test).
- **All reproduce** = clean numerical-sanity result; *say so*.
- Then (Step 3) the *distribution* of the trusted p's across many baseline
  variables is a Carlisle-style check — but weak with few variables; don't
  over-read. recalc's own validation: `~/git/recalc/validation`.

## statcheck (recompute p from reported text)

For psychology-style inline stats. Feed the printed result strings:

```r
statcheck::statcheck("F(1, 76) = 117.055, p < .001", messages = FALSE)
```

Less useful for medical tables that report only a bare p (no test statistic) —
there, use the baseline-p recalculation above instead.

## Effect sizes you derive (`metafor::escalc`)

The paper usually omits the between-group effect size. Derive it to test
plausibility:

```r
metafor::escalc(measure = "SMD",
  m1i = m_group1, sd1i = sd_group1, n1i = n1,
  m2i = m_group2, sd2i = sd_group2, n2i = n2)   # yi = Hedges g, vi = variance
```

Watch the **SE-vs-SD swap** — the single commonest effect-size error. If an SD
looks impossibly small for the scale, test whether it is really an SE
(`SD = SE * sqrt(n)`).

## F ↔ partial η² and N — `recalc::recalc_partial_eta_from_f()`

`eta_p² = F·df_effect / (F·df_effect + df_error)`. recalc propagates F's reporting
precision to an interval and checks a reported η²:

```r
recalc::recalc_partial_eta_from_f(f = 117.055, df_effect = 1, df_error = 76,
                                  f_digits = 3, eta = 0.606, eta_digits = 3)
```

For a 1-df effect this also fixes `df_error = N − #groups`, i.e. the N every test
assumes — cross-check against the stated completer count and the GRIM/alternative-n
result.

## Implied pre–post correlation (change-score coherence) — `recalc`

A pre/post result is driven by the **change-score variance**, tied to the pre and
post SDs by the identity

```
Var(change) = SD_pre² + SD_post² − 2·r·SD_pre·SD_post
```

so a reported (or F-implied) change SD pins down the within-person pre–post
correlation `r`. A real change SD must lie in `[ |SD_pre − SD_post| , SD_pre+SD_post ]`
(the `r = +1` and `r = −1` limits); outside that band the three SDs cannot coexist.

These live in **`recalc` (≥ 0.6)**, computed in closed form with the package's
rounding-interval machinery (so each returns a recalculated `[lower, upper]`
interval, not a point):

```r
# (1) you have SD_pre, SD_post AND a change SD (a "change" row, or an independent
#     t on change scores):
recalc::recalc_prepost_r(sd_pre, sd_post, sd_change,
                         sd_pre_digits = 2, sd_post_digits = 2, sd_change_digits = 2)

# (2) you have a 2x2 (group x time) RM-ANOVA interaction F instead of a change SD:
recalc::recalc_prepost_r_from_f(f = 117.055,
  m1b, sd1b, m1p, sd1p, n1,        # group 1 baseline/post mean & sd, n
  m2b, sd2b, m2p, sd2p, n2,        # group 2
  f_digits = 3, m_digits = 2, sd_digits = 3)

# reverse direction — the change SD a "normal" r would produce:
recalc::recalc_change_sd_from_r(sd_pre, sd_post, r = 0.5,
                                sd_pre_digits = 2, sd_post_digits = 2, r_digits = 1)
```

The analytic closed form is consistent with DeBruine's **`within`** package/app,
which obtains the same quantity by simulation (`faux::rnorm_multi(..., empirical =
TRUE)` + optimisation over r); the closed form avoids optimiser tolerance and
exposes `|r| > 1`.

**Possibility (recalc).** Read it off the recalculated interval:

```r
res <- recalc::recalc_prepost_r(6.77, 7.45, 13.01, 2, 2, 2)
impossible <- res$recalculated_lower > 1 || res$recalculated_upper < -1   # [IMPOSSIBLE]
```

**Plausibility (skill).** For a *possible* r, label it with `helpers.R`'s
`prepost_r_plausibility(r)` — a measure-dependent judgement (not proof), with
bands from `within` (plausible ≈ .25–.90, typical ≈ .5–.75):

| label | meaning | tag |
|---|---|---|
| `impossible` | `|r| > 1` (recalc already flags this via the interval) | `[IMPOSSIBLE]` |
| `implausible_negative` | r < 0 — pre/post of one scale rarely correlate negatively; forced when the change SD exceeds **both** component SDs | `[IMPLAUSIBLE]` |
| `implausibly_high` | r > .95 — near-deterministic, unusually homogeneous response | `[IMPLAUSIBLE]` |
| `low_unusual` / `high_unusual` | outside `within`'s .25–.90 plausible band | note in-text |
| `typical` / `plausible` / `undefined` | inside .5–.75 / inside .25–.90 / non-finite | — |

Worked example (Gauhar 2016, TSC-40): the between-group test used change SD
`13.01`. With the **table** component SDs `(6.77, 7.45)` recalc gives an implied-r
interval around `−0.673` (`prepost_r_plausibility` → `implausible_negative` — the
change SD exceeds both component SDs); with the **text** SDs `(14.58, 7.79)` it
gives `≈ +0.458` (`plausible`). The check pinpointed which of two contradictory SD
sets was internally coherent. Caveats: assumes the change SD is the SD of
within-person differences; `recalc_prepost_r_from_f` assumes a single common r
across groups. Validated in recalc's `tests/testthat/test-prepost_r.R` and the
skill's `tests/test-helpers.R`.
