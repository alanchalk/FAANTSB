#' FAA aircraft data with NTSB event indicator flag
#'
#' The FAA maintains a list of registered aircraft with various details
#' including date the registration number (n number), the date aircraft was
#' certified and the expiration date.  The full data can be downloaded from
#' @source <https://www.faa.gov/licenses_certificates/aircraft_certification/aircraft_registry/releasable_aircraft_download>
#' The NTSB keeps detailed records of every incidents in a access database.
#' The full data and the database structure can be downloaded from
#' avall.zip
#' @source <https://data.ntsb.gov/avdata/FileDirectory/DownloadFile?fileID=C%3A%5Cavdata%5Cavall.zip>
#' codman.pdf
#' @source <https://data.ntsb.gov/avdata/FileDirectory/DownloadFile?fileID=C%3A%5Cavdata%5Ccodman.pdf>
#'
#' @format ## `dt_faa_ntsb_clean`
#' A data frame with 2,696,313 rows and 49 columns:
#' \describe{
#'   \item{unique_id_line}{A unique id for each line of data}
#'   \item{unique_id_ac}{A unique id for each aircraft.  Not related to the unique_id on the FAA data}
#'   \item{n_number}{n number from the FAA data.  The prefix N has been added}
#'   \item{serial_number}{serial number from the FAA data}
#'   \item{source}{Source of the data; either the FAA master file or the FAA dergistered file}
#'   \item{mfr_mdl_code}{Aircraft manufacture and model code from the FAA data}
#'   \item{eng_mfr_mdl}{Engine manufacture and model code from the FAA data}
#'   \item{unique_id_line}{A unique id for each line of data}
#'\describe{
#'   \item{type_registrant}{The type of the registered owner. The codes and their corresponding descriptions are as follows:
#'
#'     | Code | Description                |
#'     |------|----------------------------|
#'     | 1    | Individual                 |
#'     | 2    | Partnership                |
#'     | 3    | Corporation                |
#'     | 4    | Co-Owned                   |
#'     | 5    | Government                 |
#'     | 7    | LLC                        |
#'     | 8    | Non Citizen Corporation    |
#'     | 9    | Non Citizen Co-Owned       |
#' }
#'
#'   \item{street2_ind}{0/1 indicator of whether or not there is second street line in address}
#'   \item{city}{The city name which appears on the Application for Registration, AC Form 8050-1 or the latest address reported}
#'   \item{state}{The state name which appears on the Application for Registration, AC Form 8050-1 or the latest address reported.}
#'   \item{zip_code}{The postal Zip Code which appears on the Application for Registration, AC Form 8050-1 or the latest address reported.}
#' \describe{
#'   \item{region}{A character column indicating the region. The region codes are as follows (blanks in original data are replaced with X and may be derivable from city):
#'     \itemize{
#'       \item \code{1}: Eastern
#'       \item \code{2}: Southwestern
#'       \item \code{3}: Central
#'       \item \code{4}: Western-Pacific
#'       \item \code{5}: Alaskan
#'       \item \code{7}: Southern
#'       \item \code{8}: European
#'       \item \code{C}: Great Lakes
#'       \item \code{E}: New England
#'       \item \code{S}: Northwest Mountain
#'     }
#'   }
#'   \item{county}{A code representing the county which appears on the Application for Registration.}
#'   \item{country}{A code representing the country which appears on the Application for Registration.}
#'   \item{nu_registered}{A derived field: The number of aircraft registered to this owner}
#'   \item{co_owners_num}{A derived field: The number of co-owners}
#'   \item{co_ownership}{A derived field: Whether or not the aircraft is co-onwed}
#'   \item{nu_n_number}{A derived field: The number of time an n_number appears in a data source}
#'   \item{cert_issue_date}{}
#'   \item{air_worth_date}{}
#'   \item{expiration_date}{}
#'   \item{last_action_date}{}
#' \describe{
#'   \item{airworthiness}{The airworthiness certificate class which is reported on the Application for Airworthiness, FAA Form 8130-6:
#'     \itemize{
#'       \item \code{1}: Standard
#'       \item \code{2}: Limited
#'       \item \code{3}: Restricted
#'       \item \code{4}: Experimental
#'       \item \code{5}: Provisional
#'       \item \code{6}: Multiple
#'       \item \code{7}: Primary
#'       \item \code{8}: Special Flight Permit
#'       \item \code{9}: Light Sport
#'     }
#'   }
#'
#' \describe{
#'   \item{operation}{For some airworthiness codes there is more detail about the operation.  There can be up to 6 operations, only one is chosen:
#'     \itemize{
#'       \item \code{1}: Standard
#'         \itemize{
#'           \item \code{N}: Normal
#'           \item \code{U}: Utility
#'           \item \code{A}: Acrobatic
#'           \item \code{T}: Transport
#'           \item \code{G}: Glider
#'           \item \code{B}: Balloon
#'           \item \code{C}: Commuter
#'           \item \code{X}: Other or blank
#'         }
#'       \item \code{2}: Limited
#'         \itemize{
#'           \item \code{X}: No further detail within limited.  All coded to X
#'         }
#'       \item \code{3}: Restricted
#'          \itemize{
#'            \item \code{0}: Other
#'            \item \code{1}: Agriculture and Pest Control
#'            \item \code{2}: Aerial Surveying
#'            \item \code{3}: Aerial Advertising
#'            \item \code{4}: Forest
#'            \item \code{5}: Patrolling
#'            \item \code{6}: Weather Control
#'            \item \code{7}: Carriage of Cargo
#'          }
#'       \item \code{4}: Experimental
#'         \itemize{
#'           \item \code{X}: Limited further detail in FAA so all coded to X
#'         }
#'       \item \code{6}: Multiple
#'         \itemize{
#'           \item Same codes as code 3, restricted
#'         }
#'       \item \code{7}: Primary
#'         \itemize{
#'           \item \code{X}: Very few of these (split between R&D and amateur) all coded to X
#'         }
#'       \item \code{8}: Special Flight Permit
#'         \itemize{
#'           \item \code{X}: Mostly ferry flight for repairs, alterations, maintenance or storage.  All coded to X
#'         }
#'       \item \code{9}: Light Sport
#'         \itemize{
#'           \item \code{A}: airplane
#'           \item \code{X}: includes: G - Glider; L - Lighter than Air; P - Power-Parachute; W- Weight-Shift-Control,
#'         }
#'     }
#'   }
#'
#'   \item{year_mfr}{Year manufactured.  Often missing}
#'
#'   \item{faa_acft_make}{aircraft make. merged from ReleasableAircraft/ACFTREF.txt}
#'
#'   \item{faa_acft_model}{aircraft model. merged from ReleasableAircraft/ACFTREF.txt}
#'
#' \describe{
#'   \item{faa_acft_type_acft}{aircraft type. merged from ReleasableAircraft/ACFTREF.txt}
#' }
#'   \item{faa_acft_type_eng}{}
#'   \item{faa_acft_ac_cat}{}
#'   \item{faa_acft_build_cert_ind}{}
#'   \item{faa_acft_no_eng}{}
#'   \item{faa_acft_no_seats}{}
#'   \item{faa_acft_ac_weight}{}
#'   \item{faa_acft_speed}{}
#'   \item{faa_eng_make}{}
#'   \item{faa_eng_model}{}
#'   \item{faa_eng_type}{}
#'   \item{faa_eng_hp}{}
#'   \item{faa_eng_hp_char}{}
#'   \item{faa_eng_thrust}{}
#'   \item{faa_eng_thrust_char}{}
#'   \item{kit_indyn}{}
#'   \item{veh_age}{}
#'   \item{start_date}{}
#'   \item{end_date}{}
#'   \item{ex}{}
#'   \item{nu_cl}{}
"dt_faa_ntsb_clean"

