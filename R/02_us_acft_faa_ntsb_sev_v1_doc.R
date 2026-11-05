#' Simulated US aircraft hull-claim severity
#'
#' A claim-level severity dataset paired with `us_acft_faa_ntsb_freq_v2`.
#' Each row is an NTSB aircraft occurrence matched to one FAA aircraft-year row.
#' The positive `hull_loss` target is simulated from pre-event aircraft value,
#' NTSB physical-damage class and reproducible claim-level uncertainty. Aircraft
#' value, damage ratio and damage class are deliberately excluded to prevent
#' target leakage.
#'
#' Shared rating factors use the same definitions and cleaning as the frequency
#' v2 dataset. `fold` is inherited from the matched frequency row.
#'
#' @name us_acft_faa_ntsb_sev_v1
#' @docType data
#' @format A Parquet dataset with one row per included aircraft occurrence.
#' Important columns are:
#' \describe{
#'   \item{claim_id}{Stable NTSB event-aircraft identifier.}
#'   \item{unique_id_line}{Identifier of the matched frequency-v2 aircraft-year row.}
#'   \item{accident_date}{Date of the NTSB accident or incident.}
#'   \item{accident_year}{Calendar year derived from `accident_date` for use as a numeric modelling feature.}
#'   \item{fold}{Fold inherited from the matched frequency-v2 row.}
#'   \item{hull_loss}{Simulated positive aircraft physical-damage cost at the accident-date price level.}
#' }
#' @source FAA aircraft registration data and NTSB occurrence data; severity is simulated.
NULL
