#' FAA aircraft data with NTSB event indicator flag
#'
#' The FAA maintains a list of registered aircraft with various details
#' including the registration number (N-number), the date aircraft was
#' certified and the expiration date. A zip file is available at the link below.
#' The NTSB keeps detailed records of every incident in an Access database.
#' The full Access database (avall.zip) and the database structure (codman.pdf)
#' are available at the links below.
#'
#' @usage data(dt_faa_ntsb_clean)
#'
#' @format A data frame with 2,696,313 rows and 49 columns:
#' \describe{
#'   \item{unique_id_line}{Unique identifier for each row (one per aircraft-year)}
#'   \item{unique_id_ac}{Unique identifier for each aircraft. Not related to the FAA unique_id}
#'   \item{n_number}{FAA N-number (registration number), prefixed with N}
#'   \item{serial_number}{Aircraft serial number assigned by the manufacturer}
#'   \item{source}{FAA data source: master file (active registrations) or dereg file (deregistered aircraft)
#'     \itemize{
#'       \item \code{master}: FAA master (active) file
#'       \item \code{dereg}: FAA deregistered file
#'     }
#'   }
#'   \item{mfr_mdl_code}{Aircraft manufacturer, model and series code from FAA data (7-character code)}
#'   \item{eng_mfr_mdl}{Engine manufacturer and model code from FAA data. Null for ~8.5\% of rows where engine reference not found}
#'   \item{type_registrant}{Type of registered owner. The codes and their descriptions are:
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
#'   }
#'   \item{street2_ind}{0/1 indicator: whether a second street line is present in the registrant address}
#'   \item{city}{Registrant city from Application for Registration (too many levels for direct modelling)}
#'   \item{state}{Registrant US state abbreviation}
#'   \item{zip_code}{Registrant zip code from Application for Registration}
#'   \item{region}{FAA administrative region (X = unknown / blank in source):
#'
#'     | Code | Description                |
#'     |------|----------------------------|
#'     | 1    | Eastern                    |
#'     | 2    | Southwestern               |
#'     | 3    | Central                    |
#'     | 4    | Western-Pacific            |
#'     | 5    | Alaskan                    |
#'     | 7    | Southern                   |
#'     | 8    | European                   |
#'     | C    | Great Lakes                |
#'     | E    | New England                |
#'     | S    | Northwest Mountain         |
#'     | X    | Unknown / blank in source  |
#'   }
#'   \item{county}{County code from Application for Registration. Null for ~0.6\% of rows}
#'   \item{country}{Country code from Application for Registration}
#'   \item{nu_registered}{Number of aircraft registered to the same owner name. Derived field}
#'   \item{co_owners_num}{Number of co-owners listed on the registration. Derived from other_names_1 to other_names_5 fields}
#'   \item{co_ownership}{Y/N indicator: whether aircraft has one or more co-owners (co_owners_num >= 1)
#'     \itemize{
#'       \item \code{Y}: Co-owned
#'       \item \code{N}: Not co-owned
#'     }
#'   }
#'   \item{nu_n_number}{Number of times this n_number appears in the data. Potential leakage — correlated with registration history, not with true risk}
#'   \item{cert_issue_date}{Date the airworthiness certificate was issued}
#'   \item{air_worth_date}{Date the aircraft was determined airworthy}
#'   \item{expiration_date}{Expiration date of the registration}
#'   \item{last_action_date}{Date of last action on the registration record}
#'   \item{airworthiness}{Airworthiness certificate class from FAA Form 8130-6:
#'
#'     | Code | Description                |
#'     |------|----------------------------|
#'     | 1    | Standard                   |
#'     | 2    | Limited                    |
#'     | 3    | Restricted                 |
#'     | 4    | Experimental               |
#'     | 5    | Provisional                |
#'     | 6    | Multiple                   |
#'     | 7    | Primary                    |
#'     | 8    | Special Flight Permit      |
#'     | 9    | Light Sport                |
#'   }
#'   \item{operation}{Operation type, derived from certification field. Meaning varies by airworthiness class:
#'
#'     | airworthiness             | code | operation description |
#'     |---------------------------|------|-----------------------|
#'     | 1 - Standard              | N    | Normal                |
#'     | 1 - Standard              | U    | Utility               |
#'     | 1 - Standard              | A    | Acrobatic             |
#'     | 1 - Standard              | T    | Transport             |
#'     | 1 - Standard              | G    | Glider                |
#'     | 1 - Standard              | B    | Balloon               |
#'     | 1 - Standard              | C    | Commuter              |
#'     | 1 - Standard              | X    | Other or blank        |
#'     | 2 - Limited               | X    | No further detail     |
#'     | 3 - Restricted            | 0    | Other                 |
#'     | 3 - Restricted            | 1    | Agriculture and Pest Control  |
#'     | 3 - Restricted            | 2    | Aerial Surveying      |
#'     | 3 - Restricted            | 3    | Aerial Advertising    |
#'     | 3 - Restricted            | 4    | Forest                |
#'     | 3 - Restricted            | 5    | Patrolling            |
#'     | 3 - Restricted            | 6    | Weather Control       |
#'     | 3 - Restricted            | 7    | Carriage of Cargo     |
#'     | 4 - Experimental          | X    | Limited further detail |
#'     | 5 - Provisional           | X    | No further detail     |
#'     | 6 - Multiple              |      | Same codes as code 3 - Restricted |
#'     | 7 - Primary               | X    | Limited further detail |
#'     | 8 - Special Flight Permit | X    | Mostly ferry flight for repairs, alterations, maintenance or storage |
#'     | 9 - Light Sport           | A    | airplane |
#'     | 9 - Light Sport           | X    | includes: G - Glider; L - Lighter than Air; P - Power-Parachute; W- Weight-Shift-Control |
#'   }
#'   \item{year_mfr}{Year manufactured. Often missing}
#'   \item{faa_acft_make}{Aircraft manufacturer name from FAA ACFTREF.txt. ~49k unique values — too many levels for direct modelling}
#'   \item{faa_acft_model}{Aircraft model name from FAA ACFTREF.txt. ~25k unique values — too many levels for direct modelling}
#'   \item{faa_acft_type_acft}{Aircraft type from FAA ACFTREF.txt. Dataset is filtered to types 4, 5, 6 only:
#'     \itemize{
#'       \item \code{1}: Glider
#'       \item \code{2}: Balloon
#'       \item \code{3}: Blimp/Dirigible
#'       \item \code{4}: Fixed wing single engine
#'       \item \code{5}: Fixed wing multi engine
#'       \item \code{6}: Rotorcraft
#'       \item \code{7}: Weight-shift-control
#'       \item \code{8}: Powered Parachute
#'       \item \code{9}: Gyroplane
#'       \item \code{H}: Hybrid Lift
#'       \item \code{O}: Other
#'     }
#'   }
#'   \item{faa_acft_type_eng}{Aircraft engine type from FAA ACFTREF.txt:
#'     \itemize{
#'       \item \code{0}: None
#'       \item \code{1}: Reciprocating
#'       \item \code{2}: Turbo-prop
#'       \item \code{3}: Turbo-shaft
#'       \item \code{4}: Turbo-jet
#'       \item \code{5}: Turbo-fan
#'       \item \code{6}: Ramjet
#'       \item \code{7}: 2 Cycle
#'       \item \code{8}: 4 Cycle
#'       \item \code{9}: Unknown
#'       \item \code{10}: Electric
#'       \item \code{11}: Rotary
#'     }
#'   }
#'   \item{faa_acft_ac_cat}{Aircraft landing category from FAA ACFTREF.txt:
#'     \itemize{
#'       \item \code{1}: Land
#'       \item \code{2}: Sea
#'       \item \code{3}: Amphibian
#'     }
#'   }
#'   \item{faa_acft_build_cert_ind}{Builder certification code from FAA ACFTREF.txt:
#'     \itemize{
#'       \item \code{0}: Type Certificated
#'       \item \code{1}: Not Type Certificated
#'       \item \code{2}: Light Sport
#'     }
#'   }
#'   \item{faa_acft_no_eng}{Number of engines from FAA ACFTREF.txt. Capped at 4; records with >4 engines removed as likely errors}
#'   \item{faa_acft_no_seats}{Number of seats from FAA ACFTREF.txt. Capped at 400}
#'   \item{faa_acft_ac_weight}{Maximum gross take-off weight class from FAA ACFTREF.txt. Dataset excludes CLASS 4 (UAV/drone):
#'     \itemize{
#'       \item \code{CLASS 1}: Up to 12,499 lb
#'       \item \code{CLASS 2}: 12,500 - 19,999 lb
#'       \item \code{CLASS 3}: 20,000 and over lb
#'       \item \code{CLASS 4}: UAV up to 55 lb
#'     }
#'   }
#'   \item{faa_acft_speed}{Average cruising speed in mph from FAA ACFTREF.txt. Capped at 400. Zero where not recorded}
#'   \item{faa_eng_make}{Engine manufacturer name from FAA ENGINE.txt. Too many levels for direct modelling}
#'   \item{faa_eng_model}{Engine model name from FAA ENGINE.txt. Too many levels for direct modelling}
#'   \item{faa_eng_type}{Engine type from FAA ENGINE.txt (X = missing / not matched):
#'     \itemize{
#'       \item \code{0}: None
#'       \item \code{1}: Reciprocating
#'       \item \code{2}: Turbo-prop
#'       \item \code{3}: Turbo-shaft
#'       \item \code{4}: Turbo-jet
#'       \item \code{5}: Turbo-fan
#'       \item \code{6}: Ramjet
#'       \item \code{7}: 2 Cycle
#'       \item \code{8}: 4 Cycle
#'       \item \code{9}: Unknown
#'       \item \code{10}: Electric
#'       \item \code{11}: Rotary
#'       \item \code{X}: Missing / not matched
#'     }
#'   }
#'   \item{faa_eng_hp}{Engine horsepower from FAA ENGINE.txt. Bucketed: 1-150 mapped to 100, then rounded to nearest 100 (capped at 1500). Null for ~8.5\% where engine not matched}
#'   \item{faa_eng_hp_char}{Engine horsepower category (derived from faa_eng_hp). Preferred over faa_eng_hp for modelling:
#'     \itemize{
#'       \item \code{X}: Missing (engine not matched)
#'       \item \code{Y}: 0 hp
#'       \item \code{A}: 1-150 hp
#'       \item \code{B}: 200 hp
#'       \item \code{C}: 300 hp
#'       \item \code{D}: 400-800 hp
#'       \item \code{E}: 900-1,400 hp
#'       \item \code{F}: 1,500+ hp
#'     }
#'   }
#'   \item{faa_eng_thrust}{Engine thrust in lbf from FAA ENGINE.txt. Bucketed and capped at 50,000. Null for ~8.5\% where engine not matched}
#'   \item{faa_eng_thrust_char}{Engine thrust category (derived from faa_eng_thrust). Preferred over faa_eng_thrust for modelling:
#'     \itemize{
#'       \item \code{X}: Missing (engine not matched)
#'       \item \code{Y}: 0 lbf
#'       \item \code{A}: ~10,000 lbf
#'       \item \code{B}: 20,000-40,000 lbf
#'       \item \code{C}: 50,000+ lbf
#'     }
#'   }
#'   \item{kit_indyn}{Y/N indicator: whether aircraft is kit-built (kit manufacturer is not blank):
#'     \itemize{
#'       \item \code{Y}: Kit-built aircraft
#'       \item \code{N}: Not kit-built
#'     }
#'   }
#'   \item{veh_age}{Aircraft age in years: year(start_date) - year(cert_issue_date). Capped at 50}
#'   \item{start_date}{Start of annual exposure window for this row (YYYY-MM-DD)}
#'   \item{end_date}{End of annual exposure window for this row (YYYY-MM-DD)}
#'   \item{ex}{Exposure in years: pmin(1, (end_date - start_date + 1) / 365.25). Model offset: log(ex)}
#'   \item{nu_cl}{Number of NTSB incidents matched to this aircraft-year. Primary model target}
#' }
#' @source <https://www.faa.gov/licenses_certificates/aircraft_certification/aircraft_registry/releasable_aircraft_download>
#' @source <https://data.ntsb.gov/avdata/FileDirectory/DownloadFile?fileID=C%3A%5Cavdata%5Cavall.zip>
#' @source <https://data.ntsb.gov/avdata/FileDirectory/DownloadFile?fileID=C%3A%5Cavdata%5Ccodman.pdf>
"dt_faa_ntsb_clean"
