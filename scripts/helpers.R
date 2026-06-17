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
# Implied pre-post correlation from a 2x2 (group x time) RM-ANOVA interaction.
# For two timepoints the Group x Time interaction F is EXACTLY t^2 from an
# independent test on the CHANGE scores, so F pins down the pooled SD of change;
# with the reported baseline/post SDs it back-solves the implied within-person
# pre-post r. RED FLAG: an implied change SD SMALLER than the cross-sectional SDs
# (=> r near 0.9, a near-uniform response) is implausible for noisy clinical
# scales -> [IMPLAUSIBLE]. Caveat: assumes a common r across groups; cannot be
# confirmed without the (usually unreported) change-score SDs.
# ---------------------------------------------------------------------------
implied_prepost_r <- function(F_int, m1b, s1b, m1p, s1p, n1,
                                      m2b, s2b, m2p, s2p, n2) {
  diff_change     <- (m1p - m1b) - (m2p - m2b)
  s_pooled_change <- abs(diff_change) / (sqrt(F_int) * sqrt(1/n1 + 1/n2))
  r <- tryCatch(stats::uniroot(function(r) {
    v1 <- s1b^2 + s1p^2 - 2*r*s1b*s1p
    v2 <- s2b^2 + s2p^2 - 2*r*s2b*s2p
    ((n1-1)*v1 + (n2-1)*v2) / (n1+n2-2) - s_pooled_change^2
  }, c(-0.99, 0.999))$root, error = function(e) NA_real_)
  tibble::tibble(pooled_change_sd = round(s_pooled_change, 3),
                 implied_r        = round(r, 3),
                 change_sd_g1     = round(sqrt(s1b^2 + s1p^2 - 2*r*s1b*s1p), 2),
                 change_sd_g2     = round(sqrt(s2b^2 + s2p^2 - 2*r*s2b*s2p), 2),
                 baseline_sd_g1   = s1b, post_sd_g1 = s1p,
                 baseline_sd_g2   = s2b, post_sd_g2 = s2p)
}

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
