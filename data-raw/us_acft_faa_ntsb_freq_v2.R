# data-raw/us_acft_faa_ntsb_freq_v2.R
#
# Reproducible build of the `us_acft_faa_ntsb_freq_v2` dataset -- the cleaned
# variant of v1. Identical to v1 in every respect EXCEPT `region`:
#
#   v1 leaves the FAA region blank for deregistered aircraft, stored as "X".
#       Because "X" is exactly the dereg data source, it is a leak: a model can
#       read deregistration status off `region` and inflate performance. v1
#       keeps this deliberately, as a teaching trap.
#   v2 resolves those blanks from `state` (master aircraft give a near-perfect
#       state -> region map), so `region` is honest geography with no source leak.
#
# Everything else -- the seed-2024 24% sample, the deterministic folds, freq_cl,
# zip lat/lon, the type/representation choices, the type_registrant int trap --
# matches v1 exactly. (`source` is still present in both; it is the "obvious"
# leak students should know to exclude. v1 additionally hides the leak in
# `region`.)
#
# Override the destination with the OUT_PARQUET environment variable.

suppressMessages({
  library(data.table)
  library(arrow)
})

FAANTSB_ROOT <- Sys.getenv("FAANTSB_ROOT", unset = ".")
ZIP_FILE     <- Sys.getenv(
  "US_ZIP_FILE",
  "/Users/axc/Library/CloudStorage/Dropbox/CAS/USA_zip/RawData/US Zip Codes from 2013 Government Data"
)
# Ship the parquet inside the package (inst/extdata), readable via
# system.file("extdata/us_acft_faa_ntsb_freq_v2.parquet", package = "FAANTSB").
OUT_PARQUET  <- Sys.getenv(
  "OUT_PARQUET",
  file.path(FAANTSB_ROOT, "inst", "extdata", "us_acft_faa_ntsb_freq_v2.parquet")
)

PUBLISHED_ORDER <- c(
  "zip5", "unique_id_line", "unique_id_ac", "eng_mfr_mdl", "mfr_mdl_code",
  "n_number", "serial_number", "type_registrant", "city", "state", "zip_code",
  "region", "county", "country", "source", "nu_registered", "street2_ind",
  "airworthiness", "co_owners_num", "faa_acft_make", "faa_acft_model",
  "faa_acft_type_acft", "faa_acft_type_eng", "faa_acft_ac_cat",
  "faa_acft_build_cert_ind", "faa_acft_no_eng", "faa_acft_no_seats",
  "faa_acft_ac_weight", "faa_acft_speed", "faa_eng_make", "faa_eng_model",
  "faa_eng_type", "faa_eng_hp", "faa_eng_thrust", "start_date", "end_date",
  "nu_n_number", "nu_cl", "ex", "operation", "kit_indyn", "co_ownership",
  "faa_eng_hp_char", "faa_eng_thrust_char", "acft_age", "fold", "freq_cl",
  "zip3", "lat", "lon"
)

# ---- 1. clean rda ----
load(file.path(FAANTSB_ROOT, "data", "dt_faa_ntsb_clean.rda"))
dt <- as.data.table(dt_faa_ntsb_clean)

# ---- 1b. resolve region for deregistered aircraft from state (v2 only) ----
# The FAA DEREG file carries no `region` column, so deregistered aircraft arrive
# with region == "X". region is fully determined by US state: the master
# aircraft (which have both) give a near-perfect state -> region map (58/59
# states >= 99% single-region), resolving ~100% of the dereg rows. This is the
# one and only difference from v1.
region_by_state <- dt[region != "X", .N, by = .(state, region)]
setorder(region_by_state, state, -N)
region_by_state <- region_by_state[, .(region_lk = region[1]), by = state]
dt[region_by_state, on = "state",
   region := fifelse(region == "X" & !is.na(region_lk), region_lk, region)]

# ---- 2. exclusions + deterministic 24% sample ----
dt <- dt[faa_acft_ac_weight != "CLASS 4"]
dt <- dt[!is.na(country)]
set.seed(2024)
idx <- sort(sample(nrow(dt), round(0.24 * nrow(dt), 0), replace = FALSE))
dt <- dt[idx]

# ---- 3. deterministic folds ----
dt[, fold := unique_id_line %% 10]
dt[fold %in% c(7, 8, 9), fold := 99]
dt[fold %in% 0:6, fold := fold + 1]

# ---- 4. derived columns ----
dt[, freq_cl := nu_cl / ex]
dt[, zip3 := trimws(substring(zip_code, 1, 3))]
dt[, zip5 := trimws(substring(zip_code, 1, 5))]

# ---- 5. US zip lat/lon ----
dt_zip <- fread(ZIP_FILE, colClasses = c("ZIP" = "character"))
setnames(dt_zip, c("zip5", "lat", "lon"))
dt_zip <- unique(dt_zip, by = "zip5")
dt <- merge(dt, dt_zip, by = "zip5", all.x = TRUE, all.y = FALSE, sort = FALSE)

# ---- 6. drop date columns, rename ----
dt[, c("year_mfr", "last_action_date", "cert_issue_date",
       "air_worth_date", "expiration_date") := NULL]
setnames(dt, "veh_age", "acft_age")

# ---- 6b. deliberate column representations (same as v1) ----
factor_cols <- names(dt)[vapply(dt, is.factor, logical(1))]
dt[, (factor_cols) := lapply(.SD, as.character), .SDcols = factor_cols]
dt[, type_registrant := as.integer(type_registrant)]   # int trap (same as v1)
dt[, fold := as.integer(fold)]
dt[, acft_age := as.integer(acft_age)]
dt[, co_owners_num := as.integer(co_owners_num)]

setcolorder(dt, PUBLISHED_ORDER)

# ---- 7. write ----
arrow_type <- function(x) {
  if (inherits(x, "Date")) arrow::date32()
  else if (is.integer(x)) arrow::int64()
  else if (is.numeric(x)) arrow::float64()
  else arrow::large_utf8()
}
target <- arrow::schema(setNames(lapply(dt, arrow_type), names(dt)))
tbl <- arrow::as_arrow_table(dt)$cast(target)

dir.create(dirname(OUT_PARQUET), showWarnings = FALSE, recursive = TRUE)
write_parquet(tbl, OUT_PARQUET, compression = "zstd")
cat(sprintf("wrote %s  (%d rows x %d cols)\n", OUT_PARQUET, nrow(dt), ncol(dt)))
