# Add hull value, hull loss and damage ratio to frequency v2.
#
# Frequency v2 and severity v1 can then be modelled separately and their
# combination tested on the frequency rows against actual hull losses.
#
# Run order: us_acft_faa_ntsb_freq_v2.R, 02a, 02b, 02c, us_acft_faa_ntsb_sev_v1.R,
# this script, then 02_validate_hull_severity.R. Re-running is safe: any hull
# columns already in the frequency parquet are replaced, and the severity build
# reads only the frequency columns it needs.
#
# Columns added:
#
#   hull_value    Every row. The synthetic aircraft value at the start of the
#                 exposure period, as an underwriter would fix it at inception.
#                 It uses the severity value formula with the aircraft's age in
#                 the exposure year (acft_age) and the aircraft-and-equipment
#                 price index on start_date. Claim rows therefore do not carry
#                 the accident-date value of the severity data: that value
#                 depends on when the accident happened, which would leak the
#                 claim into a pre-loss rating factor.
#   hull_loss     Total hull loss of the row's claims, from severity v1. Zero on
#                 rows with no claim.
#   damage_ratio  Average severity v1 damage ratio of the row's claims, so a
#                 severity model can be fitted on the claim rows weighted by
#                 nu_cl. Equal to the severity value on single-claim rows. Zero
#                 on rows with no claim.

suppressMessages({
  library(arrow)
  library(data.table)
  library(digest)
})

root <- Sys.getenv("FAANTSB_ROOT", unset = ".")
source(file.path(root, "data-raw", "hull_value_functions.R"))
frequency_file <- Sys.getenv(
  "FREQUENCY_PARQUET",
  file.path(root, "inst", "extdata", "us_acft_faa_ntsb_freq_v2.parquet")
)
severity_file <- file.path(root, "inst", "extdata", "us_acft_faa_ntsb_sev_v1.parquet")

frequency <- as.data.table(read_parquet(frequency_file))
severity <- as.data.table(read_parquet(severity_file))

hull_columns <- c("hull_value", "hull_loss", "damage_ratio")
existing <- intersect(hull_columns, names(frequency))
if (length(existing)) frequency[, (existing) := NULL]
published_order <- c(names(frequency), hull_columns)

if (anyDuplicated(frequency$unique_id_line)) stop("Frequency rows are not unique by unique_id_line")

# ---- 1. hull value at the start of every exposure period ----
# acft_age is already the age in the exposure year (start_date's year less the
# FAA manufacture year, clipped to 0-80, imputed when that year is missing or
# later), which is the valuation age the severity formula uses.
valuation <- frequency[, .(
  unique_id_line, faa_acft_ac_weight, faa_acft_type_eng, faa_acft_no_eng,
  faa_acft_no_seats, faa_acft_speed, start_date,
  value_age = pmax(pmin(acft_age, 80L), 0L)
)]
add_aircraft_value(valuation)
replacement_index <- read_price_index(root, "WPU142")
valuation[, hull_value := hull_value_at(
  synthetic_aircraft_value, start_date, replacement_index
)]
frequency[, hull_value := valuation$hull_value]

# ---- 2. claim cost and damage ratio from severity v1 ----
claims <- severity[, .(
  severity_claims = .N,
  hull_loss = sum(hull_loss),
  damage_ratio = sum(damage_ratio) / .N
), by = unique_id_line]

unmatched <- claims[!frequency, on = "unique_id_line"]
if (nrow(unmatched)) stop("Severity claims refer to rows not in frequency v2")

frequency[claims, on = "unique_id_line", `:=`(
  severity_claims = i.severity_claims,
  hull_loss = i.hull_loss,
  damage_ratio = i.damage_ratio
)]
frequency[is.na(severity_claims), `:=`(
  severity_claims = 0L,
  hull_loss = 0,
  damage_ratio = 0
)]

# ---- 3. checks ----
if (any(frequency$severity_claims != frequency$nu_cl)) {
  stop("Severity claim counts do not equal nu_cl on every row")
}
frequency[, severity_claims := NULL]
if (anyNA(frequency$hull_value) || any(frequency$hull_value <= 0)) {
  stop("Every row must have a positive hull value")
}
if (any(frequency[nu_cl == 0, hull_loss != 0 | damage_ratio != 0])) {
  stop("Rows with no claim must have zero hull loss and damage ratio")
}
if (any(frequency[nu_cl > 0, hull_loss <= 0 | damage_ratio <= 0])) {
  stop("Rows with a claim must have a positive hull loss and damage ratio")
}
if (!isTRUE(all.equal(sum(frequency$hull_loss), sum(severity$hull_loss), tolerance = 0))) {
  stop("Frequency hull loss does not total the severity hull loss")
}
if (!isTRUE(all.equal(
  sum(frequency$nu_cl * frequency$damage_ratio), sum(severity$damage_ratio),
  tolerance = 1e-12
))) {
  stop("Claim-weighted frequency damage ratios do not total the severity damage ratios")
}

setcolorder(frequency, published_order)

# ---- 4. write, with the same type mapping as us_acft_faa_ntsb_freq_v2.R ----
arrow_type <- function(x) {
  if (inherits(x, "Date")) arrow::date32()
  else if (is.integer(x)) arrow::int64()
  else if (is.numeric(x)) arrow::float64()
  else arrow::large_utf8()
}
target <- arrow::schema(setNames(lapply(frequency, arrow_type), names(frequency)))
table <- arrow::as_arrow_table(frequency)$cast(target)
write_parquet(table, frequency_file, compression = "zstd")

cat(sprintf(
  "wrote %s (%d rows x %d cols); %d claim rows, hull loss total %.0f\n",
  frequency_file, nrow(frequency), ncol(frequency),
  frequency[nu_cl > 0, .N], sum(frequency$hull_loss)
))
