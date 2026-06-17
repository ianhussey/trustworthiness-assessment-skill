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
# GRIM itself is scrutiny's. Call it directly — and state the precision, which
# scrutiny (rightly) requires:
#   scrutiny::grim(x = mean, n = n, digits_x = 2)          # vectorised over x
#   scrutiny::grim_map(df, digits_x = 2)                   # data-frame form
# The skill adds only the forensic *sweep* below, not a GRIM re-export (a wrapper
# with a default `digits` would silently assume precision — the exact footgun
# scrutiny's mandatory digits_x guards against).
#
# grim_n_profile: when GRIM fails at the reported n, which n WOULD make a whole
# block of reported means mutually consistent? A sharp single peak at a DIFFERENT
# n than reported points to an undisclosed sample size (dropout / per-protocol
# subset / altered values); a flat profile points to non-integer data or genuinely
# anomalous values. `digits` must match the reporting precision of `means`.
# ---------------------------------------------------------------------------
grim_n_profile <- function(means, n_range, digits, items = 1) {
  if (missing(digits)) stop("Specify `digits` = the decimal places `means` were reported to.")
  tibble::tibble(n = n_range) |>
    dplyr::rowwise() |>
    dplyr::mutate(
      consistent = sum(scrutiny::grim(x = means, n = n, digits_x = digits, items = items)),
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
# Pre-post (within-person) correlation, partial eta^2, and F<->eta reconciliation
# now live in the `recalc` package (>= 0.6), which computes them with the
# package's rounding-interval machinery. Call them directly:
#
#   recalc::recalc_prepost_r(sd_pre, sd_post, sd_change, *_digits)        # POSSIBILITY
#   recalc::recalc_prepost_r_from_f(f, m/sd per group, n1, n2, *_digits)  # from RM-ANOVA F
#   recalc::recalc_change_sd_from_r(sd_pre, sd_post, r, *_digits)         # reverse
#   recalc::recalc_partial_eta_from_f(f, df_effect, df_error, f_digits)   # eta^2 <-> F
#
# Each returns a recalc_result row with the recalculated [lower, upper] interval.
# POSSIBILITY is read off that interval: for an implied r, the SDs cannot coexist
# when the whole interval is > 1 or < -1.
#
# PLAUSIBILITY (below) is the skill's layer: a measure-dependent judgement about
# an implied r that *is* mathematically possible. Bands follow DeBruine's `within`
# (plausible ~.25-.90, typical ~.5-.75); `faux` underlies within's simulation
# approach. These are heuristics, not proof — a negative or near-1 within-person r
# is unusual for a noisy clinical scale but not impossible.
# ---------------------------------------------------------------------------
prepost_r_plausibility <- function(r, high = 0.95,
                                   plausible = c(0.25, 0.90),
                                   typical   = c(0.50, 0.75)) {
  dplyr::case_when(
    !is.finite(r)                       ~ "undefined",
    r > 1 | r < -1                      ~ "impossible",            # recalc territory
    r < 0                               ~ "implausible_negative",  # [IMPLAUSIBLE]
    r > high                            ~ "implausibly_high",      # [IMPLAUSIBLE]
    r < plausible[1]                    ~ "low_unusual",
    r > plausible[2]                    ~ "high_unusual",
    r >= typical[1] & r <= typical[2]   ~ "typical",
    TRUE                                ~ "plausible"
  )
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
