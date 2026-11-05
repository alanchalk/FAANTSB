# Publish the student-facing FAA/NTSB hull-severity dataset.

suppressMessages({
  library(arrow)
  library(data.table)
})

root <- Sys.getenv("FAANTSB_ROOT", unset = ".")
audit <- as.data.table(readRDS(file.path(
  root, "data-raw", "derived", "dt_faa_ntsb_hull_audit.rds"
)))
frequency <- as.data.table(read_parquet(file.path(
  root, "inst", "extdata", "us_acft_faa_ntsb_freq_v2.parquet"
)))
output_file <- Sys.getenv(
  "OUT_PARQUET",
  file.path(root, "inst", "extdata", "us_acft_faa_ntsb_sev_v1.parquet")
)

features <- c(
  "eng_mfr_mdl", "mfr_mdl_code", "type_registrant", "city", "state",
  "zip_code", "region", "county", "country", "street2_ind", "airworthiness",
  "co_owners_num", "faa_acft_make", "faa_acft_model", "faa_acft_type_acft",
  "faa_acft_type_eng", "faa_acft_ac_cat", "faa_acft_build_cert_ind",
  "faa_acft_no_eng", "faa_acft_no_seats", "faa_acft_ac_weight",
  "faa_acft_speed", "faa_eng_make", "faa_eng_model", "faa_eng_type",
  "faa_eng_hp", "faa_eng_thrust", "operation", "kit_indyn", "co_ownership",
  "faa_eng_hp_char", "faa_eng_thrust_char", "acft_age", "zip3", "zip5",
  "lat", "lon"
)

severity <- merge(
  audit[, .(
    claim_id,
    unique_id_line,
    accident_date = ev_date,
    acft_age_at_accident = value_age,
    hull_value,
    hull_loss_ratio,
    hull_loss
  )],
  frequency[, c("unique_id_line", "fold", features), with = FALSE],
  by = "unique_id_line",
  all.x = TRUE,
  sort = FALSE
)
severity[, accident_year := as.integer(format(accident_date, "%Y"))]
severity[, acft_age := as.integer(pmin(50, pmax(0, acft_age_at_accident)))]
severity[, acft_age_at_accident := NULL]
setcolorder(severity, c(
  "claim_id", "unique_id_line", "accident_date", "accident_year",
  features, "fold", "hull_value", "hull_loss", "hull_loss_ratio"
))
setorder(severity, claim_id)

if (anyDuplicated(severity$claim_id)) stop("Published claim IDs are not unique")
if (anyNA(severity$accident_date)) stop("Every published claim must have an accident date")
if (anyNA(severity$accident_year)) stop("Every published claim must have an accident year")
if (anyNA(severity$hull_loss) || any(severity$hull_loss <= 0)) {
  stop("Every published claim must have one positive hull-loss severity")
}
if (anyNA(severity$hull_value) || any(severity$hull_value <= 0)) {
  stop("Every published claim must have one positive accident-date hull value")
}
if (any(severity$hull_loss_ratio <= 0 | severity$hull_loss_ratio > 1)) {
  stop("Published hull loss ratios must be in (0, 1]")
}
if (anyNA(severity$fold)) stop("Every published claim must inherit a frequency-v2 fold")

arrow_type <- function(x) {
  if (inherits(x, "Date")) arrow::date32()
  else if (is.integer(x)) arrow::int64()
  else if (is.numeric(x)) arrow::float64()
  else arrow::large_utf8()
}
target_schema <- schema(setNames(lapply(severity, arrow_type), names(severity)))
table <- as_arrow_table(severity)$cast(target_schema)

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
write_parquet(table, output_file, compression = "zstd")
cat(sprintf("wrote %s (%d rows x %d columns)\n", output_file, nrow(severity), ncol(severity)))
