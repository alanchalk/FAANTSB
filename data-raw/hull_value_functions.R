# Shared aircraft-value and price-index functions.
#
# Sourced by 02b and 02c (the hull-severity build) and by
# 03_add_hull_columns_to_freq_v2.R. Keeping one copy means the severity hull
# value and the frequency-v2 hull value always come from the same formula.

# A stable uniform draw in (0, 1) keyed by an identifier, so rebuilds repeat.
stable_uniform <- function(key, salt) {
  hash <- vapply(
    paste0(key, "|", salt),
    digest::digest2int,
    integer(1),
    USE.NAMES = FALSE
  )
  (as.numeric(hash) + 2147483648.5) / 4294967296
}

# Add a synthetic aircraft value at the latest price level, by reference.
#
# Needs unique_id_line, the FAA aircraft fields below and value_age, the
# aircraft's age in whole years at the valuation date. The value uncertainty is
# keyed by unique_id_line, so every valuation of one aircraft-year shares it.
add_aircraft_value <- function(dt) {
  base_value <- c("CLASS 1" = 180000, "CLASS 2" = 1400000, "CLASS 3" = 9000000)
  dt[, value_base := unname(base_value[faa_acft_ac_weight])]
  dt[is.na(value_base), value_base := 180000]

  dt[, engine_factor := fifelse(
    faa_acft_type_eng %chin% c("4", "5"), 1.70,
    fifelse(faa_acft_type_eng %chin% c("2", "3"), 1.35, 1.00)
  )]
  dt[, engine_count_factor := 1 + 0.16 * pmax(pmin(faa_acft_no_eng, 4L) - 1L, 0L)]
  dt[, seat_factor := (pmax(pmin(faa_acft_no_seats, 80), 2) / 4)^0.28]
  dt[, speed_factor := (pmax(pmin(faa_acft_speed, 350), 60) / 100)^0.45]
  dt[, age_factor := 0.32 + 0.68 * exp(-value_age / 22)]

  dt[, synthetic_value_expected := value_base * engine_factor *
    engine_count_factor * seat_factor * speed_factor * age_factor]

  value_sigma <- 0.40
  dt[, value_uncertainty := exp(
    value_sigma * qnorm(stable_uniform(unique_id_line, "aircraft-value")) -
      value_sigma^2 / 2
  )]
  dt[, synthetic_aircraft_value := pmax(
    15000,
    round(synthetic_value_expected * value_uncertainty, -2)
  )]
  invisible(dt)
}

# Read a frozen BLS producer price index series from rawdata/BLS.
read_price_index <- function(root, series) {
  index <- data.table::fread(file.path(root, "rawdata", "BLS", paste0(series, ".csv")))
  data.table::setnames(index, c("date", "index"))
  index[, date := as.IDate(date)]
  index
}

# The index value in force on each date.
index_at <- function(dates, index_table) {
  positions <- findInterval(as.IDate(dates), index_table$date)
  if (any(positions == 0)) stop("Price index does not cover all dates")
  index_table$index[positions]
}

# Restate a latest-price-level aircraft value at the price level of a date,
# using the aircraft-and-equipment index (WPU142).
hull_value_at <- function(synthetic_aircraft_value, dates, replacement_index) {
  factor <- index_at(dates, replacement_index) / tail(replacement_index$index, 1)
  round(pmax(500, synthetic_aircraft_value * factor), -2)
}
