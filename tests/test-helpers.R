#!/usr/bin/env Rscript
# Lightweight tests for scripts/helpers.R.
# Run from the repo root:  Rscript tests/test-helpers.R
# (No testthat dependency — uses base assertions so it runs anywhere R + dplyr do.)

suppressMessages({ library(tibble); library(dplyr); library(purrr) })

helpers <- if (file.exists("scripts/helpers.R")) "scripts/helpers.R" else "../scripts/helpers.R"
source(helpers)

# --- tiny harness ----------------------------------------------------------
.fails <- 0L
ok <- function(cond, msg) {
  pass <- isTRUE(cond)
  if (!pass) .fails <<- .fails + 1L
  cat(if (pass) "  ok   " else "  FAIL ", msg, "\n", sep = "")
}
approx <- function(a, b, tol = 1e-3) all(is.finite(a) & is.finite(b) & abs(a - b) <= tol)

cat("== prepost_r_from_change_sd ==\n")

# round-trip: build a change SD from a known r, recover r
for (r in seq(-0.9, 0.9, by = 0.3)) {
  sdc <- expected_change_sd(5, 8, r)
  got <- prepost_r_from_change_sd(5, 8, sdc)$implied_r
  ok(approx(got, r), sprintf("round-trip r = %+.1f  (recovered %.3f)", r, got))
}

# Gauhar TSC-40 table SDs (6.77, 7.45) with change SD 13.01 -> negative r
g_tab <- prepost_r_from_change_sd(6.77, 7.45, 13.01)
ok(approx(g_tab$implied_r, -0.673, 0.002), "Gauhar TABLE SDs -> r ~ -0.673")
ok(g_tab$flag == "implausible_negative_r", "Gauhar TABLE SDs flagged implausible_negative_r")

# Gauhar TSC-40 text SDs (14.58, 7.79) with same change SD -> normal r
g_txt <- prepost_r_from_change_sd(14.58, 7.79, 13.01)
ok(approx(g_txt$implied_r, 0.458, 0.002), "Gauhar TEXT SDs -> r ~ +0.458")
ok(g_txt$flag == "ok", "Gauhar TEXT SDs flagged ok")

# feasibility limits
ok(prepost_r_from_change_sd(8, 5, 3.0)$flag == "implausible_negative_r" ||
   approx(prepost_r_from_change_sd(8, 5, 3.0)$implied_r, 1),
   "change SD = |pre-post| -> r = +1 (boundary)")
ok(prepost_r_from_change_sd(8, 5, 2.0)$flag == "impossible_high_r",
   "change SD < |pre-post| -> impossible_high_r (r > 1)")
ok(prepost_r_from_change_sd(8, 5, 13.0001)$flag == "impossible_low_r",
   "change SD > pre+post -> impossible_low_r (r < -1)")
ok(prepost_r_from_change_sd(5, 5, 1.0)$flag == "implausibly_high_r",
   "tiny change SD vs equal component SDs -> implausibly_high_r")
ok(is.na(prepost_r_from_change_sd(5, 0, 4)$implied_r) &&
   prepost_r_from_change_sd(5, 0, 4)$flag == "undefined",
   "zero component SD -> undefined")

# vectorised
v <- prepost_r_from_change_sd(c(6.77, 14.58), c(7.45, 7.79), c(13.01, 13.01))
ok(nrow(v) == 2 && approx(v$implied_r[1], -0.673, 0.002) && approx(v$implied_r[2], 0.458, 0.002),
   "vectorised input returns one row per comparison")

cat("== prepost_r_from_F (and implied_prepost_r alias) ==\n")

# Pu et al.: F(1,76) = 117.055 -> r ~ 0.885 (matches the old uniroot solver)
pu <- prepost_r_from_F(117.055, 24.71, 4.137, 8.96, 5.237, 52,
                                24.81, 3.774, 15.95, 5.714, 26)
ok(approx(pu$implied_r, 0.885, 0.002), sprintf("Pu F=117.055 -> r ~ 0.885 (got %.3f)", pu$implied_r))
ok(approx(pu$pooled_change_sd, 2.651, 0.01), "Pu pooled change SD ~ 2.65")
ok(pu$flag == "ok", "Pu r ~ 0.885 flagged ok (< .95)")

# an impossibly large F: implied change SD falls below the feasible band -> r > 1
big <- prepost_r_from_F(10000, 24.71, 4.137, 8.96, 5.237, 52,
                               24.81, 3.774, 15.95, 5.714, 26)
ok(big$flag == "impossible_high_r", "absurd F -> impossible_high_r (closed form catches |r|>1)")

# alias identity
al <- implied_prepost_r(117.055, 24.71, 4.137, 8.96, 5.237, 52,
                                 24.81, 3.774, 15.95, 5.714, 26)
ok(identical(al, pu), "implied_prepost_r is an alias for prepost_r_from_F")

cat("== sanity: pre-existing helpers still work ==\n")
ok(grim_consistent(15.95, 26) == FALSE, "grim_consistent(15.95, 26) == FALSE")
ok(grim_consistent(15.19, 26) == TRUE,  "grim_consistent(15.19, 26) == TRUE")
ok(approx(eta_from_F(117.055, 76), 0.606, 1e-3), "eta_from_F(117.055, 76) ~ 0.606")

cat(sprintf("\n%s  (%d failures)\n", if (.fails == 0) "ALL TESTS PASSED" else "TESTS FAILED", .fails))
if (.fails > 0) quit(status = 1)
