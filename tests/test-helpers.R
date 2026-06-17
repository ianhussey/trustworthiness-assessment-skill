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

cat("== prepost_r_plausibility (skill-side plausibility layer) ==\n")
# possibility lives in recalc; this is the measure-dependent judgement layer
ok(prepost_r_plausibility(-0.673) == "implausible_negative", "negative r -> implausible_negative")
ok(prepost_r_plausibility(0.458)  == "plausible",            "r 0.46 -> plausible")
ok(prepost_r_plausibility(0.60)   == "typical",              "r 0.60 -> typical (within .5-.75)")
ok(prepost_r_plausibility(0.97)   == "implausibly_high",     "r 0.97 -> implausibly_high")
ok(prepost_r_plausibility(0.10)   == "low_unusual",          "r 0.10 -> low_unusual")
ok(prepost_r_plausibility(1.5)    == "impossible",           "r 1.5 -> impossible (recalc territory)")
ok(prepost_r_plausibility(NA)     == "undefined",            "NA -> undefined")

cat("== recalc engine reachable (pre-post r + eta moved to recalc >= 0.6) ==\n")
if (requireNamespace("recalc", quietly = TRUE)) {
  g  <- recalc::recalc_prepost_r(6.77, 7.45, 13.01, 2, 2, 2)   # Gauhar table -> r < 0
  mid <- (g$recalculated_lower + g$recalculated_upper) / 2
  ok(approx(mid, -0.673, 0.005), sprintf("recalc::recalc_prepost_r Gauhar table -> r ~ -0.673 (got %.3f)", mid))
  e <- recalc::recalc_partial_eta_from_f(117.055, 1, 76, f_digits = 3, eta = 0.606, eta_digits = 3)
  ok(isTRUE(e$consistent), "recalc::recalc_partial_eta_from_f reconciles F=117.055 with eta=.606")
} else {
  cat("  SKIP recalc not installed (>= 0.6 required for the analysis chunks)\n")
}

cat("== GRIM: scrutiny direct + grim_n_profile sweep (skill glue) ==\n")
if (requireNamespace("scrutiny", quietly = TRUE)) {
  ok(scrutiny::grim(15.95, 26, digits_x = 2) == FALSE, "scrutiny::grim(15.95, 26) == FALSE")
  ok(scrutiny::grim(15.19, 26, digits_x = 2) == TRUE,  "scrutiny::grim(15.19, 26) == TRUE")
  # grim_n_profile recovers the Pu sham-post n=21 peak (1/10 at reported n=26)
  sp <- c(15.95, 14.67, 8.76, 24.33, 15.19, 30.90, 10.48, 28.29, 7.67, 4.90)
  pr <- grim_n_profile(sp, 18:26, digits = 2)
  ok(pr$n[which.max(pr$consistent)] == 21 && max(pr$consistent) == 10,
     "grim_n_profile peak at n=21 (10/10); n=26 gives 1/10")
  ok(pr$consistent[pr$n == 26] == 1, "grim_n_profile: 1/10 consistent at reported n=26")
} else {
  cat("  SKIP scrutiny not installed\n")
}
ok(tryCatch({ grim_n_profile(c(15.95), 20:26); FALSE }, error = function(e) TRUE),
   "grim_n_profile requires explicit digits (no silent precision default)")

cat(sprintf("\n%s  (%d failures)\n", if (.fails == 0) "ALL TESTS PASSED" else "TESTS FAILED", .fails))
if (.fails > 0) quit(status = 1)
