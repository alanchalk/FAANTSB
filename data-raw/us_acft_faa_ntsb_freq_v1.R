# data-raw/us_acft_faa_ntsb_freq_v1.R
#
# Reproducible build of the published `us_acft_faa_ntsb_freq_v1` dataset from
# the FAANTSB clean rda. Writes parquet directly, replacing the legacy path
# (frozen 03__dt_sample24.RData -> hand-exported CSV -> datasets-repo parquet).
#
# Row selection and folds are fully deterministic from `dt_faa_ntsb_clean`:
#   1. exclude drones (faa_acft_ac_weight == "CLASS 4") and missing country
#   2. 24% random sample, set.seed(2024)  -- reproduces the published rows exactly
#   3. fold = unique_id_line %% 10; {7,8,9} -> 99 (test); {0..6} -> +1 (CV 1..7)
# then derive freq_cl, zip5/zip3, merge US zip lat/lon, drop date columns,
# rename veh_age -> acft_age.
#
# Validated against the published parquet: identical rows and column values,
# with three prior CSV-serialisation artefacts removed at source --
#   - missing strings kept as NA (parquet null) instead of ""
#   - foreign zip codes trimmed of trailing whitespace
#   - no CSV quote-doubling of embedded quotes
#
# Output is a single parquet for the datasets repo to pull. Override the
# destination with the OUT_PARQUET environment variable.

suppressMessages({
  library(data.table)
  library(arrow)
})

FAANTSB_ROOT <- Sys.getenv("FAANTSB_ROOT", unset = ".")
ZIP_FILE     <- Sys.getenv(
  "US_ZIP_FILE",
  "/Users/axc/Library/CloudStorage/Dropbox/CAS/USA_zip/RawData/US Zip Codes from 2013 Government Data"
)
# Ship the parquet inside the package (inst/extdata), so consumers can
# install.packages / install_github("alanchalk/FAANTSB") and read it via
# system.file("extdata/us_acft_faa_ntsb_freq_v1.parquet", package = "FAANTSB").
OUT_PARQUET  <- Sys.getenv(
  "OUT_PARQUET",
  file.path(FAANTSB_ROOT, "inst", "extdata", "us_acft_faa_ntsb_freq_v1.parquet")
)

# Column order of the published parquet (kept stable for downstream consumers).
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

# ---- 6b. deliberate column representations ----
# In the rda, several code columns are factors whose levels are numeric strings
# (e.g. type_registrant: "1".."9"). On the legacy CSV path, fwrite wrote those
# labels and polars then *inferred* Int64 for the all-numeric ones and string
# for the rest -- an inconsistent serialisation artefact, not a chosen type.
# Make it deliberate: write honest categoricals as strings.
factor_cols <- names(dt)[vapply(dt, is.factor, logical(1))]
dt[, (factor_cols) := lapply(.SD, as.character), .SDcols = factor_cols]

# STUDENT TRAP (deliberate): type_registrant is a categorical registrant-type
# code, but is shipped as an integer so students must recognise it needs casting
# to a factor before modelling. Every other code column is an honest string.
dt[, type_registrant := as.integer(type_registrant)]

# Integer columns R promoted to double (e.g. fold via `fold + 1`, NA-bearing
# numerics). Restore integer type.
dt[, fold := as.integer(fold)]
dt[, acft_age := as.integer(acft_age)]
dt[, co_owners_num := as.integer(co_owners_num)]

setcolorder(dt, PUBLISHED_ORDER)

# ---- 7. write ----
# Match the published parquet's arrow widths (int64 / large_string / date32 /
# double) so the only schema change vs the published file is the deliberate
# string recoding above. R's defaults (int32 / string) read identically, but
# matching widths keeps the drop-in schema diff clean.
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
