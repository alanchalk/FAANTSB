# data-raw/us_acft_faa_ntsb_freq_v2.R
#
# Reproducible build of the `us_acft_faa_ntsb_freq_v2` dataset -- the cleaned
# variant of v1. It corrects two known data-quality problems in v1:
#
#   v1 leaves the FAA region blank for deregistered aircraft, stored as "X".
#       Because "X" is exactly the dereg data source, it is a leak: a model can
#       read deregistration status off `region` and inflate performance. v1
#       keeps this deliberately, as a teaching trap.
#   v2 resolves those blanks from `state` (master aircraft give a near-perfect
#       state -> region map), so `region` is honest geography with no source leak.
#
# `acft_age` uses manufacture year when the FAA supplies it. Only records with
# no manufacture year fall back to certificate tenure, which is the v1 measure.
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

# ---- 6. calculate aircraft age, then drop source dates ----
dt[, `:=`(
  exposure_year = as.integer(format(start_date, "%Y")),
  certificate_year = as.integer(format(cert_issue_date, "%Y"))
)]
dt[, certificate_age := exposure_year - certificate_year]

# Learn the missing-year fallback from one row per aircraft registration. Using
# annual rows would count the same aircraft repeatedly and overstate support.
age_training <- dt[
  !is.na(year_mfr) & !is.na(certificate_age) & exposure_year >= year_mfr
]
setorder(age_training, unique_id_ac, start_date)
age_training <- age_training[, .SD[1L], by = unique_id_ac]
age_training[, actual_age := exposure_year - year_mfr]

global_age_fit <- lm(actual_age ~ certificate_age, data = age_training)
global_age_intercept <- unname(coef(global_age_fit)[1L])
global_age_beta <- unname(coef(global_age_fit)[2L])

model_age_stats <- age_training[, .(
  model_age_n = .N,
  model_mean_age = mean(actual_age),
  model_mean_certificate_age = mean(certificate_age)
), by = .(faa_acft_make, faa_acft_model)]

model_age_fits <- age_training[, {
  fit <- if (.N >= 20L && uniqueN(certificate_age) >= 2L) {
    lm(actual_age ~ certificate_age)
  } else {
    NULL
  }
  .(
    model_age_intercept = if (is.null(fit)) NA_real_ else unname(coef(fit)[1L]),
    model_age_beta = if (is.null(fit)) NA_real_ else unname(coef(fit)[2L])
  )
}, by = .(faa_acft_make, faa_acft_model)]

make_age_stats <- age_training[, .(
  make_age_n = .N,
  make_mean_age = mean(actual_age),
  make_mean_certificate_age = mean(certificate_age)
), by = faa_acft_make]

dt[model_age_stats, on = .(faa_acft_make, faa_acft_model), `:=`(
  model_age_n = i.model_age_n,
  model_mean_age = i.model_mean_age,
  model_mean_certificate_age = i.model_mean_certificate_age
)]
dt[model_age_fits, on = .(faa_acft_make, faa_acft_model), `:=`(
  model_age_intercept = i.model_age_intercept,
  model_age_beta = i.model_age_beta
)]
dt[make_age_stats, on = .(faa_acft_make), `:=`(
  make_age_n = i.make_age_n,
  make_mean_age = i.make_mean_age,
  make_mean_certificate_age = i.make_mean_certificate_age
)]

dt[, global_age_prediction :=
  global_age_intercept + global_age_beta * certificate_age]
dt[, make_age_prediction :=
  make_mean_age + global_age_beta * (certificate_age - make_mean_certificate_age)]
dt[, model_age_prediction :=
  model_mean_age + global_age_beta * (certificate_age - model_mean_certificate_age)]

# Sparse make/model averages are shrunk towards the make-level prediction.
dt[, model_weight := model_age_n / (model_age_n + 10)]
dt[, sparse_model_prediction :=
  model_weight * model_age_prediction + (1 - model_weight) * make_age_prediction]

dt[, age_source := fcase(
  !is.na(year_mfr) & exposure_year >= year_mfr, "faa_manufacture_year",
  !is.na(model_age_intercept), "make_model_regression",
  !is.na(model_age_prediction) & !is.na(make_age_prediction), "make_model_shrunk",
  !is.na(make_age_prediction), "make_average",
  default = "global_regression"
)]
dt[, acft_age := fcase(
  age_source == "faa_manufacture_year", as.numeric(exposure_year - year_mfr),
  age_source == "make_model_regression",
    model_age_intercept + model_age_beta * certificate_age,
  age_source == "make_model_shrunk", sparse_model_prediction,
  age_source == "make_average", make_age_prediction,
  default = global_age_prediction
)]
dt[, acft_age := as.integer(round(pmax(0, pmin(50, acft_age))))]
if (anyNA(dt$acft_age)) stop("Aircraft-age imputation left missing values")

print(dt[, .N, by = age_source][order(-N)])

dt[, c("year_mfr", "last_action_date", "cert_issue_date",
       "air_worth_date", "expiration_date", "veh_age",
       "exposure_year", "certificate_year", "certificate_age",
       "model_age_n", "model_mean_age", "model_mean_certificate_age",
       "model_age_intercept", "model_age_beta", "make_age_n",
       "make_mean_age", "make_mean_certificate_age", "global_age_prediction",
       "make_age_prediction", "model_age_prediction", "model_weight",
       "sparse_model_prediction", "age_source") := NULL]

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
