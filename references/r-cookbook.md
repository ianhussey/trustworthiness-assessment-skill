# R cookbook — trustworthiness assessment

API notes and copy-paste snippets for the R tooling. Load `scripts/helpers.R`
first; it wraps most of this. Read this when you are writing the analysis chunks.

## Packages & install

| Package | Source | Used for |
|---|---|---|
| `scrutiny` | CRAN | GRIM / GRIMMER |
| `recalc` | Ian Hussey's package (`~/git/recalc`; `devtools::install("~/git/recalc")`) | baseline p recalculation, chi-sq recalc |
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
# CORRECT (0.6.2):
scrutiny::grim_map(tibble(x = c(15.95, 15.19), n = c(26L, 26L)), digits_x = 2)
scrutiny::grimmer_map(tibble(x = 8.96, sd = 5.237, n = 52L), digits_x = 2, digits_sd = 3)
```

Because this API has churned across versions, `helpers.R` ships a base-R
`grim_consistent(mean, n, digits, items)` that is version-proof and is what the
template uses. GRIM only applies to **integer totals** (sum of integer items).
Per-item means use `items = #items`. Zung SDS/SAS *index* scores (raw × 1.25) are
NOT integer-grained → exclude.

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

`helpers.R` wraps these as `recalc_baseline_t(df, n1, n2)` (one row per continuous
variable: `variable/m1/sd1/m2/sd2/p`) and `recalc_baseline_chisq(counts, p)`.

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

## F ↔ partial η² and N

For a 1-df effect, `eta_p^2 = F / (F + df_error)`; `helpers.R::eta_from_F()`. A
column of internally consistent F/η² also fixes `df_error = N − #groups`, i.e. the
N every test assumes — cross-check against the stated completer count and the
GRIM/alternative-n result.

## Implied pre–post correlation (change-score coherence)

A pre/post result is driven by the **change-score variance**, tied to the pre and
post SDs by the identity

```
Var(change) = SD_pre² + SD_post² − 2·r·SD_pre·SD_post
```

so a reported (or F-implied) change SD pins down the within-person pre–post
correlation `r`. A real change SD must lie in `[ |SD_pre − SD_post| , SD_pre+SD_post ]`
(the `r = +1` and `r = −1` limits); outside that band the three SDs cannot
coexist. Two entry points, both returning `implied_r` + a `flag`:

```r
# (1) You have SD_pre, SD_post AND a change SD (a "change" row, or an independent
#     t computed on change scores). Vectorised.
prepost_r_from_change_sd(sd_pre, sd_post, sd_change)   # -> implied_r, change_sd_min/max, flag

# (2) You have a 2x2 (group x time) RM-ANOVA interaction F instead of a change SD.
#     F = t² on the change scores pins the pooled change SD; r is back-solved
#     (closed form, so it can return |r| > 1 to flag an F incompatible with the SDs).
prepost_r_from_F(F_int = 117.055,
  m1b, s1b, m1p, s1p, n1,     # group 1 baseline/post mean & sd, n
  m2b, s2b, m2p, s2p, n2)     # group 2
# implied_prepost_r() is a back-compatible alias for prepost_r_from_F().

# reverse direction — the change SD a "normal" r would produce:
expected_change_sd(sd_pre, sd_post, r = 0.5)
```

`flag` values and how to tag them:

| flag | meaning | tag |
|---|---|---|
| `impossible_high_r` | change SD `< |SD_pre − SD_post|` ⇒ r > 1 | `[IMPOSSIBLE]` |
| `impossible_low_r` | change SD `> SD_pre + SD_post` ⇒ r < −1 | `[IMPOSSIBLE]` |
| `implausible_negative_r` | r < 0 — pre/post of one scale rarely correlate negatively; forced when the change SD exceeds **both** component SDs | `[IMPLAUSIBLE]` |
| `implausibly_high_r` | r > 0.95 — near-deterministic, unusually homogeneous response | `[IMPLAUSIBLE]` |
| `ok` / `undefined` | plausible / non-finite (e.g. a zero or missing SD) | — |

Worked example (Gauhar 2016, TSC-40): the between-group test used change SD
`13.01`. With the **table** component SDs `(6.77, 7.45)` that implies `r ≈ −0.673`
(`implausible_negative_r` — the change SD exceeds both); with the **text** SDs
`(14.58, 7.79)` it implies `r ≈ +0.458` (`ok`). The check pinpointed which of two
contradictory SD sets was internally coherent. Caveats to state in-text: assumes
the change SD is the SD of within-person differences; `prepost_r_from_F` assumes a
single common r across groups. Validated in `tests/test-helpers.R`.
