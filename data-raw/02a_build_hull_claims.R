# Build one deterministic FAA match for each in-scope NTSB aircraft occurrence.

suppressMessages({
  library(arrow)
  library(data.table)
})

root <- Sys.getenv("FAANTSB_ROOT", unset = ".")
ntsb_db <- Sys.getenv(
  "NTSB_DB",
  file.path(root, "rawdata", "NTSB", "migration-export.sqlite")
)
frequency_file <- file.path(
  root, "inst", "extdata", "us_acft_faa_ntsb_freq_v2.parquet"
)
derived_dir <- file.path(root, "data-raw", "derived")
output_file <- file.path(derived_dir, "dt_faa_ntsb_hull_claims.rds")
report_file <- file.path(derived_dir, "hull_claim_match_reconciliation.csv")

if (!file.exists(ntsb_db)) stop("NTSB database not found: ", ntsb_db)

load(file.path(root, "data", "dt_faa_ntsb_clean.rda"))
faa <- as.data.table(dt_faa_ntsb_clean)
frequency <- as.data.table(read_parquet(frequency_file))

read_sqlite <- function(query) {
  output <- tempfile(fileext = ".csv")
  on.exit(unlink(output))
  status <- system2(
    "sqlite3",
    c("-header", "-csv", shQuote(ntsb_db), shQuote(query)),
    stdout = output
  )
  if (status != 0L) stop("sqlite3 query failed")
  fread(output)
}

aircraft <- read_sqlite(paste(
  "SELECT ev_id, Aircraft_Key, regis_no, ntsb_no, damage,",
  "acft_make, acft_model, acft_series FROM aircraft"
))
events <- read_sqlite("SELECT ev_id, ntsb_no, ev_type, ev_date FROM events")

events[, ev_date := as.Date(ev_date)]
aircraft[, n_number := toupper(trimws(regis_no))]
aircraft[, claim_id := paste(ev_id, Aircraft_Key, sep = "-")]
claims <- merge(
  aircraft,
  events,
  by = c("ev_id", "ntsb_no"),
  all = FALSE,
  sort = FALSE
)

reconciliation <- data.table(
  stage = c(
    "NTSB aircraft occurrences",
    "Aggregate claims recorded in frequency-v2"
  ),
  rows = c(nrow(claims), as.integer(sum(frequency$nu_cl)))
)

claims <- claims[
  !is.na(n_number) & !n_number %chin% c("", "UNREG", "UNK", "UNKNOWN")
]

normalise_make <- function(x) {
  substr(toupper(fifelse(is.na(x), "", x)), 1, 5)
}

claims[, ntsb_make_key := normalise_make(acft_make)]
frequency_claim_rows <- frequency[nu_cl > 0]
faa <- merge(
  faa[unique_id_line %chin% frequency_claim_rows$unique_id_line],
  frequency_claim_rows[, .(
    unique_id_line,
    expected_claims = as.integer(nu_cl),
    fold
  )],
  by = "unique_id_line",
  all = FALSE,
  sort = FALSE
)
faa[, faa_make_key := normalise_make(faa_acft_make)]

candidates <- merge(
  claims,
  faa[n_number %chin% claims$n_number],
  by = "n_number",
  all = FALSE,
  allow.cartesian = TRUE,
  sort = FALSE
)
candidates <- candidates[
  ntsb_make_key != "" & faa_make_key != "" & ntsb_make_key == faa_make_key
]

candidates[, interval_match := ev_date >= start_date & ev_date <= end_date]
candidates[, date_distance := fifelse(
  interval_match,
  0L,
  pmin(abs(as.integer(ev_date - start_date)), abs(as.integer(ev_date - end_date)))
)]
candidates <- candidates[
  !is.na(cert_issue_date) & ev_date >= cert_issue_date & date_distance < 730L
]
setorder(
  candidates,
  unique_id_line,
  -interval_match,
  date_distance,
  Aircraft_Key,
  claim_id
)
candidates <- unique(candidates, by = c("unique_id_line", "ntsb_no"))
candidates[, candidate_count := .N, by = unique_id_line]

available <- candidates[, .(available_claims = .N), by = unique_id_line]
quota_check <- merge(
  frequency_claim_rows[, .(
    unique_id_line,
    expected_claims = as.integer(nu_cl)
  )],
  available,
  by = "unique_id_line",
  all.x = TRUE
)
quota_check[is.na(available_claims), available_claims := 0L]
if (any(quota_check$available_claims < quota_check$expected_claims)) {
  stop("Not every frequency-v2 claim could be matched to an NTSB occurrence")
}

matched <- candidates[, head(.SD, expected_claims[1L]), by = unique_id_line]
matched[, match_rule := fifelse(interval_match, "event date within row", "nearest row under 730 days")]

reconciliation <- rbind(
  reconciliation,
  data.table(
    stage = "NTSB occurrences assigned to frequency-v2 claims",
    rows = nrow(matched)
  )
)

keep <- c(
  "claim_id", "ev_id", "Aircraft_Key", "ntsb_no", "ev_date", "ev_type",
  "damage", "n_number", "acft_make", "acft_model", "acft_series",
  "unique_id_line", "unique_id_ac", "year_mfr", "fold", "candidate_count", "match_rule",
  "date_distance", "interval_match"
)
matched <- matched[, ..keep]
setorder(matched, claim_id)

if (anyDuplicated(matched$claim_id)) stop("Claim matching did not produce unique claim IDs")
if (anyNA(matched$fold)) stop("One or more matched claims have no inherited fold")
if (nrow(matched) != as.integer(sum(frequency$nu_cl))) {
  stop("Severity claim count does not equal the frequency-v2 aggregate count")
}

dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(matched, output_file)
fwrite(reconciliation, report_file)

print(reconciliation)
cat(sprintf("wrote %s (%d claims)\n", output_file, nrow(matched)))
