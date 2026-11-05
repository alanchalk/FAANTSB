# Simulate one reproducible positive hull-loss severity for every matched claim.

suppressMessages({
  library(data.table)
  library(digest)
})

root <- Sys.getenv("FAANTSB_ROOT", unset = ".")
derived_dir <- file.path(root, "data-raw", "derived")
claims <- as.data.table(readRDS(file.path(derived_dir, "dt_faa_ntsb_hull_values.rds")))

stable_uniform <- function(key, salt) {
  hash <- vapply(
    paste0(key, "|", salt),
    digest2int,
    integer(1),
    USE.NAMES = FALSE
  )
  (as.numeric(hash) + 2147483648.5) / 4294967296
}

claims[, total_loss_probability := fcase(
  damage == "DEST", 0.95,
  damage == "SUBS", 0.03,
  damage == "MINR", 0.001,
  default = 0.01
)]
claims[, is_total_loss := stable_uniform(claim_id, "loss-type") < total_loss_probability]

# Total-loss payments rise with aircraft value, but less than proportionally
# because coverage, salvage and recovery differ between claims.
claims[, total_loss_fraction := 0.35 + 0.65 * qbeta(
  stable_uniform(claim_id, "total-loss-fraction"), 2.0, 1.5
)]
claims[, total_loss_cost := 180000 *
  (synthetic_aircraft_value / 180000)^0.78 * total_loss_fraction]

claims[, partial_repair_base := fcase(
  damage == "DEST", 70000,
  damage == "SUBS", 30000,
  damage == "MINR", 7000,
  default = 15000
)]
repair_sigma <- 0.80
claims[, repair_uncertainty := exp(
  repair_sigma * qnorm(stable_uniform(claim_id, "partial-repair-cost")) -
    repair_sigma^2 / 2
)]
claims[, partial_repair_cost := partial_repair_base *
  (synthetic_aircraft_value / 180000)^0.10 * repair_uncertainty]

claims[, hull_loss_latest_price_level := pmax(500, pmin(
  synthetic_aircraft_value,
  fifelse(is_total_loss, total_loss_cost, partial_repair_cost)
))]

# Express each claim at its accident-date price level using US aircraft PPIs.
replacement_index <- fread(file.path(root, "rawdata", "BLS", "WPU142.csv"))
repair_index <- fread(file.path(root, "rawdata", "BLS", "WPU5541.csv"))
setnames(replacement_index, c("date", "index"))
setnames(repair_index, c("date", "index"))
replacement_index[, date := as.IDate(date)]
repair_index[, date := as.IDate(date)]

index_at <- function(dates, index_table) {
  positions <- findInterval(as.IDate(dates), index_table$date)
  if (any(positions == 0)) stop("Price index does not cover all accident dates")
  index_table$index[positions]
}

replacement_at_accident <- index_at(claims$ev_date, replacement_index)
replacement_factor <- replacement_at_accident / tail(replacement_index$index, 1)
claims[, hull_value := round(
  pmax(500, synthetic_aircraft_value * replacement_factor),
  -2
)]

# The repair series begins in April 2009. Backcast the earlier months using
# the aircraft-and-equipment index, anchored to the first repair observation.
repair_at_accident <- index_at(
  pmax(claims$ev_date, as.Date(repair_index$date[1])), repair_index
)
before_repair_series <- claims$ev_date < repair_index$date[1]
repair_at_accident[before_repair_series] <- repair_index$index[1] *
  replacement_at_accident[before_repair_series] /
  index_at(repair_index$date[1], replacement_index)
repair_factor <- repair_at_accident / tail(repair_index$index, 1)

claims[, inflation_factor := fifelse(
  is_total_loss, replacement_factor, repair_factor
)]
claims[, hull_loss := round(hull_loss_latest_price_level * inflation_factor, -1)]
claims[, hull_loss := pmin(hull_loss, hull_value)]
claims[, hull_loss_ratio := hull_loss / hull_value]
claims[, damage_ratio := hull_loss_ratio]

if (anyNA(claims$hull_loss)) stop("One or more claims have no simulated severity")
if (any(claims$hull_loss <= 0)) stop("Every simulated severity must be positive")
if (anyNA(claims$hull_value) || any(claims$hull_value <= 0)) {
  stop("Every claim must have one positive accident-date hull value")
}
if (any(claims$hull_loss_ratio <= 0 | claims$hull_loss_ratio > 1)) {
  stop("Hull loss ratios must be in (0, 1]")
}

summary_by_damage <- claims[, .(
  claims = .N,
  total_losses = sum(is_total_loss),
  median_damage_ratio = median(damage_ratio),
  median_hull_loss = median(hull_loss),
  mean_hull_loss = mean(hull_loss)
), by = damage]

audit_file <- file.path(derived_dir, "dt_faa_ntsb_hull_audit.rds")
report_file <- file.path(derived_dir, "hull_severity_simulation_report.csv")
saveRDS(claims, audit_file)
fwrite(summary_by_damage, report_file)

cat(sprintf("wrote %s (%d claims)\n", audit_file, nrow(claims)))
print(summary_by_damage)
