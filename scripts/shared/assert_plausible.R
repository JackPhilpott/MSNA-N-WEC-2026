# ==============================================================================
# assert_plausible() - output-plausibility gate (2026-09-08 pipeline audit,
# pass 4). Companion to assert_fresh.R: that function checks an INPUT is
# current before a script reads it; this one checks an OUTPUT is sane before
# a script trusts/writes it. Same root problem as the whole audit this week -
# assert_fresh() closed "a stale artifact gets read as if current," but
# nothing checked "the number this script is about to write looks like a
# real result, not a bug" - see project memory
# project_output_plausibility_gap_2026-09-08 for the fuller case history
# (75-of-314 strata showing achieved_sample > target_sample, a resweep
# leaving 38% of rows unmatched, both caught only by a human noticing).
#
# Deliberately narrow: checks ONE named value against an expected numeric
# range, hard-stops if outside it. Not a validation framework - each call
# site states its own expected range explicitly, in context, same
# "duplicated not imported" convention as the rest of this project. A range
# that's wrong because the data genuinely, legitimately moved should be
# updated explicitly by whoever's touching that call site, not silenced.
# ==============================================================================

#' @param label Short name for this check, used in messages.
#' @param value The number to check (already computed by the caller).
#' @param expected_range c(low, high) - inclusive.
#' @param context Optional extra string for the error message (e.g. what
#'   would explain a legitimate move outside range).
assert_plausible <- function(label, value, expected_range, context = NULL) {
  lo <- expected_range[1]; hi <- expected_range[2]
  if (is.null(value) || length(value) == 0 || is.na(value)) {
    stop(sprintf("assert_plausible(%s): value is NA/missing - cannot check plausibility, don't proceed on an unknown.", label))
  }
  if (value < lo || value > hi) {
    stop(sprintf(
      paste0(
        "assert_plausible(%s): IMPLAUSIBLE VALUE %s, expected [%s, %s]%s.\n",
        "This looks like a bug, not a real data change - stopping before this ",
        "gets written/trusted. If this range is genuinely wrong (a real, ",
        "understood shift), update the expected range explicitly at this call ",
        "site - don't just remove or widen the check to make it pass."
      ),
      label, format(value), format(lo), format(hi),
      if (!is.null(context)) paste0(" (", context, ")") else ""
    ))
  }
  cat(sprintf("assert_plausible(%s): %s within expected [%s, %s].\n", label, format(value), format(lo), format(hi)))
  invisible(TRUE)
}
