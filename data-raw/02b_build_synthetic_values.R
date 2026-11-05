# Create reproducible synthetic aircraft values for the matched hull claims.

suppressMessages({
  library(arrow)
  library(data.table)
  library(digest)
})

root <- Sys.getenv("FAANTSB_ROOT", unset = ".")
derived_dir <- file.path(root, "data-raw", "derived")
claims <- as.data.table(readRDS(file.path(derived_dir, "dt_faa_ntsb_hull_claims.rds")))
frequency <- as.data.table(read_parquet(file.path(
  root, "inst", "extdata", "us_acft_faa_ntsb_freq_v2.parquet"
)))

stable_uniform <- function(key, salt) {
  hash <- vapply(
    paste0(key, "|", salt),
    digest2int,
    integer(1),
    USE.NAMES = FALSE
  )
  (as.numeric(hash) + 2147483648.5) / 4294967296
}

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

base_value <- c("CLASS 1" = 180000, "CLASS 2" = 1400000, "CLASS 3" = 9000000)
values[, value_base := unname(base_value[faa_acft_ac_weight])]
values[is.na(value_base), value_base := 180000]

values[, engine_factor := fifelse(
  faa_acft_type_eng %chin% c("4", "5"), 1.70,
  fifelse(faa_acft_type_eng %chin% c("2", "3"), 1.35, 1.00)
)]
values[, engine_count_factor := 1 + 0.16 * pmax(pmin(faa_acft_no_eng, 4L) - 1L, 0L)]
values[, seat_factor := (pmax(pmin(faa_acft_no_seats, 80), 2) / 4)^0.28]
values[, speed_factor := (pmax(pmin(faa_acft_speed, 350), 60) / 100)^0.45]
values[, value_age := as.integer(format(ev_date, "%Y")) - year_mfr]
values[is.na(value_age) | value_age < 0, value_age := acft_age]
values[, value_age := pmax(pmin(value_age, 80), 0)]
values[, age_factor := 0.32 + 0.68 * exp(-value_age / 22)]

values[, synthetic_value_expected := value_base * engine_factor *
  engine_count_factor * seat_factor * speed_factor * age_factor]

value_sigma <- 0.40
values[, value_uncertainty := exp(
  value_sigma * qnorm(stable_uniform(unique_id_line, "aircraft-value")) -
    value_sigma^2 / 2
)]
values[, synthetic_aircraft_value := pmax(
  15000,
  round(synthetic_value_expected * value_uncertainty, -2)
)]

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
