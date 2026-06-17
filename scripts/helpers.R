# =============================================================================
# helpers.R — reusable functions for forensic trustworthiness assessments
# Part of the `trustworthiness-assessment` Claude skill.
#
# Source this from an assessment .qmd:   source("helpers.R")
# Packages used (load in the .qmd, not here): scrutiny, recalc, metafor, tibble,
#   dplyr, purrr. `recalc` is Ian Hussey's package (github: ~/git/recalc);
#   scrutiny/statcheck/metafor are on CRAN. See references/r-cookbook.md.
# =============================================================================

# ---------------------------------------------------------------------------
# GRIM — is a reported mean achievable as (integer sum) / n for an integer total?
# `items` > 1 only if the reported value is a per-ITEM mean (total / items);
# for a raw total score leave items = 1. Robust to scrutiny API churn.
# ---------------------------------------------------------------------------
grim_consistent <- function(mean_reported, n, digits = 2, items = 1) {
  tol  <- 0.5 * 10^(-digits)
  gran <- 1 / (n * items)                       # granularity of an integer-sum mean
  k_lo <- ceiling((mean_reported - tol) / gran - 1e-9)
  k_hi <- floor(  (mean_reported + tol) / gran + 1e-9)
  k_lo <= k_hi
}

# THE forensic move when GRIM fails at the reported n: which n WOULD make a whole
# block of reported means mutually consistent? A sharp single peak at a DIFFERENT
# n than reported points to an undisclosed sample size (dropout / per-protocol
# subset / altered values). A flat profile points to non-integer data or genuinely
# anomalous values. Returns a tibble of (n, # consistent, total).
grim_n_profile <- function(means, n_range, digits = 2, items = 1) {
  tibble::tibble(n = n_range) |>
    dplyr::rowwise() |>
    dplyr::mutate(consistent = sum(grim_consistent(means, n, digits, items)),
                  total = length(means)) |>
    dplyr::ungroup()
}

# Implied integer sum at a candidate n (residual ~0 => that n is plausible).
implied_sum <- function(mean_reported, n) {
  s <- mean_reported * n
  tibble::tibble(mean = mean_reported, n = n, raw = round(s, 3),
                 nearest_int = round(s), residual = round(s - round(s), 3))
}

# ---------------------------------------------------------------------------
# partial eta-squared <-> F reconciliation for a 1-df effect.
# For df_effect = 1: eta_p^2 = F / (F + df_error). df_error = N - #groups, so a
# vector of consistent eta/F also pins down N (a participant-flow cross-check).
# ---------------------------------------------------------------------------
eta_from_F <- function(F, df_error, df_effect = 1) {
  (F * df_effect) / (F * df_effect + df_error)
}

# ---------------------------------------------------------------------------
# Implied pre-post (within-person) correlation checks.
#
# A pre/post (repeated-measures) result is driven by the CHANGE-score variance,
# which is tied to the pre and post SDs by the identity
#       Var(change) = SD_pre^2 + SD_post^2 - 2 * r * SD_pre * SD_post,
# so a reported (or F-implied) change SD pins down the within-person pre-post
# correlation r. Two entry points, both returning an `implied_r` and a `flag`:
#
#   * prepost_r_from_change_sd()  -- you have SD_pre, SD_post AND a change SD
#       (a "change" row in a table, or an independent t computed on change
#       scores). This is the most common case.
#   * prepost_r_from_F()          -- you have a 2x2 (group x time) RM-ANOVA
#       interaction F instead of a change SD. F = t^2 on the change scores, so
#       F pins the pooled change SD; r is then back-solved (assumes a common r
#       across groups). Closed-form, so it can return |r| > 1 to flag an F that
#       is incompatible with the reported SDs.
#
# Feasibility: a real change SD must lie in [ |SD_pre - SD_post| , SD_pre+SD_post ]
# (the r = +1 and r = -1 limits). `flag` values:
#   impossible_high_r       change SD < |SD_pre - SD_post|  => r > 1    [IMPOSSIBLE]
#   impossible_low_r        change SD > SD_pre + SD_post     => r < -1   [IMPOSSIBLE]
#   implausible_negative_r  r < 0: the pre and post of one scale rarely correlate
#                           negatively (a change SD above BOTH component SDs forces
#                           it)                                          [IMPLAUSIBLE]
#   implausibly_high_r      r > high_r (default .95): near-deterministic change, an
#                           unusually homogeneous response               [IMPLAUSIBLE]
#   ok / undefined          plausible / non-finite (e.g. a zero or missing SD)
# Caveats: assumes the change SD is the SD of within-person differences; for
# prepost_r_from_F, a single common r across groups.
# ---------------------------------------------------------------------------

.prepost_r_flag <- function(r, high_r = 0.95) {
  dplyr::case_when(
    !is.finite(r) ~ "undefined",
    r >  1 + 1e-9 ~ "impossible_high_r",
    r < -1 - 1e-9 ~ "impossible_low_r",
    r <  0        ~ "implausible_negative_r",
    r >  high_r   ~ "implausibly_high_r",
    TRUE          ~ "ok"
  )
}

# Reverse direction: the change SD expected for a given pre-post correlation.
expected_change_sd <- function(sd_pre, sd_post, r) {
  sqrt(pmax(sd_pre^2 + sd_post^2 - 2 * r * sd_pre * sd_post, 0))
}

prepost_r_from_change_sd <- function(sd_pre, sd_post, sd_change,
                                     high_r = 0.95, digits = 3) {
  stopifnot(length(sd_pre) == length(sd_post),
            length(sd_post) == length(sd_change))
  r <- (sd_pre^2 + sd_post^2 - sd_change^2) / (2 * sd_pre * sd_post)
  r[sd_pre <= 0 | sd_post <= 0 | sd_change < 0] <- NA_real_   # invalid inputs
  tibble::tibble(
    sd_pre, sd_post, sd_change,
    implied_r     = round(r, digits),
    change_sd_min = round(abs(sd_pre - sd_post), digits),     # change SD at r = +1
    change_sd_max = round(sd_pre + sd_post, digits),          # change SD at r = -1
    flag          = .prepost_r_flag(r, high_r)
  )
}

prepost_r_from_F <- function(F_int, m1b, s1b, m1p, s1p, n1,
                                    m2b, s2b, m2p, s2p, n2,
                             high_r = 0.95, digits = 3) {
  diff_change     <- (m1p - m1b) - (m2p - m2b)
  s_pooled_change <- abs(diff_change) / (sqrt(F_int) * sqrt(1/n1 + 1/n2))
  # pooled Var(change) = A - B*r is linear in a common r -> solve in closed form.
  Nden <- n1 + n2 - 2
  A <- ((n1 - 1) * (s1b^2 + s1p^2)   + (n2 - 1) * (s2b^2 + s2p^2))   / Nden
  B <- ((n1 - 1) * (2 * s1b * s1p)   + (n2 - 1) * (2 * s2b * s2p))   / Nden
  r <- (A - s_pooled_change^2) / B
  tibble::tibble(
    pooled_change_sd = round(s_pooled_change, digits),
    implied_r        = round(r, digits),
    change_sd_g1     = round(expected_change_sd(s1b, s1p, r), digits),
    change_sd_g2     = round(expected_change_sd(s2b, s2p, r), digits),
    baseline_sd_g1 = s1b, post_sd_g1 = s1p,
    baseline_sd_g2 = s2b, post_sd_g2 = s2p,
    flag = .prepost_r_flag(r, high_r)
  )
}

# Backwards-compatible alias (older templates/qmds call implied_prepost_r()).
implied_prepost_r <- prepost_r_from_F

# ---------------------------------------------------------------------------
# Baseline p-value recalculation (recalc). Does each reported baseline p cohere
# with the reported group m/sd/n? recalc returns a MULTIVERSE (Student/Welch x
# rounding x direction); we summarise as [min_p, max_p] and whether the reported
# p falls inside that hull. A reported p OUTSIDE the hull is the flag — it cannot
# arise from the reported summary stats under any standard test => [IMPOSSIBLE].
# Pass one row per continuous baseline variable: columns variable/m1/sd1/m2/sd2/p.
# n1/n2 are the GROUP sizes (group 1 must be the m1/sd1 group).
# ---------------------------------------------------------------------------
p_decimals <- function(p) {                       # how many dp the p was reported to
  s <- format(p, scientific = FALSE, trim = TRUE)
  if (!grepl(".", s, fixed = TRUE)) return(0L)
  nchar(strsplit(s, ".", fixed = TRUE)[[1]][2])
}

recalc_baseline_t <- function(df, n1, n2, m_digits = 2, sd_digits = 3) {
  purrr::pmap_dfr(df, function(variable, m1, sd1, m2, sd2, p) {
    r  <- recalc::recalc_independent_t_p(
      m1 = m1, m2 = m2, sd1 = sd1, sd2 = sd2, n1 = n1, n2 = n2,
      m_digits = m_digits, sd_digits = sd_digits,
      p = p, p_digits = p_decimals(p))
    rp <- dplyr::distinct(r$reproduced)
    tibble::tibble(variable, reported_p = p,
                   recomputed_min = round(rp$min_p, 3),
                   recomputed_max = round(rp$max_p, 3),
                   reproduced = rp$p_inbounds_hull)
  })
}

# Categorical baseline row (e.g. sex). Returns the one-row reproduced summary.
recalc_baseline_chisq <- function(counts, p, p_digits = p_decimals(p)) {
  rp <- dplyr::distinct(
    recalc::recalc_chisq_p(counts = counts, p = p, p_digits = p_digits)$reproduced)
  tibble::tibble(reported_p = p,
                 recomputed_min = round(rp$min_p, 3),
                 recomputed_max = round(rp$max_p, 3),
                 reproduced = rp$p_inbounds_hull)
}

# ---------------------------------------------------------------------------
# Display helper: round-half-up to fixed decimals (SPSS-style), for parity with
# how papers print numbers.
# ---------------------------------------------------------------------------
round_half_up_min_decimals <- function(x, digits = 2) {
  sprintf(paste0("%.", digits, "f"), scrutiny::reround(x, digits = digits)[[1]])
}
