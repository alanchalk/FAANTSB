# Create reproducible synthetic aircraft values for the matched hull claims.

suppressMessages({
  library(arrow)
  library(data.table)
  library(digest)
})

root <- Sys.getenv("FAANTSB_ROOT", unset = ".")
source(file.path(root, "data-raw", "hull_value_functions.R"))
derived_dir <- file.path(root, "data-raw", "derived")
claims <- as.data.table(readRDS(file.path(derived_dir, "dt_faa_ntsb_hull_claims.rds")))
frequency <- as.data.table(read_parquet(file.path(
  root, "inst", "extdata", "us_acft_faa_ntsb_freq_v2.parquet"
)))

value_fields <- c(
  "unique_id_line", "faa_acft_type_acft", "faa_acft_type_eng",
  "faa_acft_ac_weight", "faa_acft_no_eng", "faa_acft_no_seats",
  "faa_acft_speed", "acft_age"
)
values <- merge(
  claims,
  frequency[, ..value_fields],
  by = "unique_id_line",
  all.x = TRUE,
  sort = FALSE
)

# Value each aircraft at its age on the accident date.
values[, value_age := as.integer(format(ev_date, "%Y")) - year_mfr]
values[is.na(value_age) | value_age < 0, value_age := acft_age]
values[, value_age := pmax(pmin(value_age, 80), 0)]
add_aircraft_value(values)

if (anyNA(values$synthetic_aircraft_value)) stop("Synthetic aircraft values contain missing values")
if (any(values$synthetic_aircraft_value <= 0)) stop("Synthetic aircraft values must be positive")

setorder(values, claim_id)
output_file <- file.path(derived_dir, "dt_faa_ntsb_hull_values.rds")
saveRDS(values, output_file)

cat(sprintf("wrote %s (%d claim values)\n", output_file, nrow(values)))
print(values[, .(
  claims = .N,
  minimum = min(synthetic_aircraft_value),
  median = median(synthetic_aircraft_value),
  mean = mean(synthetic_aircraft_value),
  maximum = max(synthetic_aircraft_value)
)])
