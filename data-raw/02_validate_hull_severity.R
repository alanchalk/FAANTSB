# Validate the published severity dataset against its audit and frequency inputs.

suppressMessages({
  library(arrow)
  library(data.table)
})

root <- Sys.getenv("FAANTSB_ROOT", unset = ".")
severity <- as.data.table(read_parquet(file.path(
  root, "inst", "extdata", "us_acft_faa_ntsb_sev_v1.parquet"
)))
frequency <- as.data.table(read_parquet(file.path(
  root, "inst", "extdata", "us_acft_faa_ntsb_freq_v2.parquet"
)))
audit <- as.data.table(readRDS(file.path(
  root, "data-raw", "derived", "dt_faa_ntsb_hull_audit.rds"
)))

stopifnot(
  nrow(severity) == nrow(audit),
  !anyDuplicated(severity$claim_id),
  !anyNA(severity$accident_date),
  inherits(severity$accident_date, "Date"),
  !anyNA(severity$accident_year),
  all(severity$accident_year == as.integer(format(severity$accident_date, "%Y"))),
  !anyNA(severity$hull_loss),
  all(severity$hull_loss > 0),
  !anyNA(severity$hull_value),
  all(severity$hull_value > 0),
  !anyNA(severity$damage_ratio),
  all(severity$damage_ratio > 0 & severity$damage_ratio <= 1),
  isTRUE(all.equal(
    severity$damage_ratio,
    severity$hull_loss / severity$hull_value,
    tolerance = 1e-12
  )),
  !any(c("damage", "synthetic_aircraft_value") %chin% names(severity))
)

age_check <- merge(
  severity[, .(claim_id, acft_age)],
  audit[, .(claim_id, expected_age = as.integer(pmin(50, pmax(0, value_age))))],
  by = "claim_id",
  all.x = TRUE
)
stopifnot(
  !anyNA(age_check$expected_age),
  all(age_check$acft_age == age_check$expected_age)
)

fold_check <- merge(
  severity[, .(unique_id_line, severity_fold = fold)],
  unique(frequency[, .(unique_id_line, frequency_fold = fold)]),
  by = "unique_id_line",
  all.x = TRUE
)
stopifnot(
  !anyNA(fold_check$frequency_fold),
  all(fold_check$severity_fold == fold_check$frequency_fold)
)

claim_count_check <- merge(
  severity[, .(severity_claims = .N), by = unique_id_line],
  frequency[nu_cl > 0, .(
    unique_id_line,
    frequency_claims = as.integer(nu_cl)
  )],
  by = "unique_id_line",
  all = TRUE
)
stopifnot(
  !anyNA(claim_count_check$severity_claims),
  !anyNA(claim_count_check$frequency_claims),
  all(claim_count_check$severity_claims == claim_count_check$frequency_claims)
)

gamma_deviance <- function(actual, predicted) {
  sum(2 * ((actual - predicted) / predicted - log(actual / predicted)))
}

# This fixed reference model uses only information available before an accident.
# It guards against making the synthetic target either trivial or unlearnable.
reference_model <- glm(
  hull_loss ~ accident_year + acft_age + log1p(faa_acft_no_seats) +
    log1p(faa_acft_speed) + faa_acft_ac_weight + faa_acft_type_acft +
    faa_acft_type_eng + faa_acft_no_eng,
  data = severity[fold != 99],
  family = Gamma(link = "log")
)
holdout <- severity[fold == 99]
holdout_prediction <- predict(reference_model, newdata = holdout, type = "response")
holdout_prediction <- holdout_prediction *
  sum(holdout$hull_loss) / sum(holdout_prediction)
holdout_null <- rep(mean(holdout$hull_loss), nrow(holdout))
holdout_pr2 <- 1 - gamma_deviance(holdout$hull_loss, holdout_prediction) /
  gamma_deviance(holdout$hull_loss, holdout_null)
stopifnot(holdout_pr2 >= 0.20, holdout_pr2 <= 0.32)

cat(sprintf(
  "validated %d claims; held-out Gamma PR-squared %.3f; all folds inherited\n",
  nrow(severity), holdout_pr2
))
