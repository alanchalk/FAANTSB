# 01a_read_data.R

# libraries needed
library(data.table)
library(RSQLite)
library(sqldf)
library(lubridate)

dir_project <- getwd()
dir_rawdata <- file.path(dir_project, 'rawdata')
dir_rdata <- file.path(dir_project, 'data')


#-------------------------------------------------------------------------------
# Read FAA data

# read master; 292094
dt_faa_master <- fread(file=file.path(dir_rawdata, 'ReleasableAircraft/MASTER.txt'))
temp_colnames <- tolower(colnames(dt_faa_master))
temp_colnames <- gsub("[)$]", "", temp_colnames)
temp_colnames <- gsub("[' '-]", "_", temp_colnames)
temp_colnames <- gsub("\\(", "_", temp_colnames)
colnames(dt_faa_master) <- temp_colnames
rm(temp_colnames)

# last column is just NA
sum(!is.na(dt_faa_master$v35))
dt_faa_master[, v35 := NULL]

# add source
dt_faa_master[, source := 'master']

# read dereg and clean up row names to be consistent with master
# problem with row 194470, so skip it
dt_faa_dereg1 <- fread(file=file.path(dir_rawdata, 'ReleasableAircraft/DEREG.txt'),
                      nrows=194469)

dt_faa_dereg2 <-fread(file=file.path(dir_rawdata, 'ReleasableAircraft/DEREG.txt'),
                      skip=194471,
                      header=FALSE)

# manual check that columns are the same
#dt_faa_dereg1[1, 1:10]
#dt_faa_dereg2[1, 1:10]

#dt_faa_dereg1[1, 11:20]
#dt_faa_dereg2[1, 11:20]

#dt_faa_dereg1[1, 21:30]
#dt_faa_dereg2[1, 21:30]

colnames(dt_faa_dereg2) <- colnames(dt_faa_dereg1)

# 372,926
dt_faa_dereg <- rbindlist(list(dt_faa_dereg1, dt_faa_dereg2),
                           use.names = TRUE,
                           fill=TRUE)

rm(dt_faa_dereg1, dt_faa_dereg2)
gc()

temp_colnames <- tolower(colnames(dt_faa_dereg))
temp_colnames <- gsub("[)$]", "", temp_colnames)
temp_colnames <- gsub("[' '-]", "_", temp_colnames)
temp_colnames <- gsub("\\(", "_", temp_colnames)
colnames(dt_faa_dereg) <- temp_colnames
rm(temp_colnames)

# add source
dt_faa_dereg[, source := 'dereg']

# put the dereg data together with master data
setdiff(colnames(dt_faa_master), colnames(dt_faa_dereg))
setdiff(colnames(dt_faa_dereg), colnames(dt_faa_master))

# the following are in dereg and not in master
#[1] "street_mail"           "street2_mail"          "city_mail"
#[4] "state_abbrev_mail"     "zip_code_mail"         "county_mail"
#[7] "country_mail"          "cancel_date"           "indicator_group"
#[10] "exp_country"           "last_act_date"         "street_physical"
#[13] "street2_physical"      "city_physical"         "state_abbrev_physical"
#[16] "zip_code_physical"     "county_physical"       "country_physical"
#[19] "v39"

# physical mail is mostly missing and in anycase will only use
# an indicator as to whether street 2 is blank or not
# so rename the street_mail to street and remove physical
#sum(dt_faa_dereg$street_mail == '', na.rm = TRUE)
#sum(dt_faa_dereg$street_physical == '', na.rm = TRUE)
#sum(dt_faa_dereg$street2_mail == '', na.rm = TRUE)
setnames(dt_faa_dereg, 'street_mail', 'street')
setnames(dt_faa_dereg, 'street2_mail', 'street2')
setnames(dt_faa_dereg, 'city_mail', 'city')
setnames(dt_faa_dereg, 'state_abbrev_mail', 'state_abbrev')
setnames(dt_faa_dereg, 'zip_code_mail', 'zip_code')
setnames(dt_faa_dereg, 'county_mail', 'county')
setnames(dt_faa_dereg, 'country_mail', 'country')

dt_faa_dereg[, street_physical :=  NULL]
dt_faa_dereg[, street2_physical :=  NULL]
dt_faa_dereg[, city_physical :=  NULL]
dt_faa_dereg[, state_abbrev_physical :=  NULL]
dt_faa_dereg[, zip_code_physical :=  NULL]
dt_faa_dereg[, county_physical :=  NULL]
dt_faa_dereg[, country_physical :=  NULL]
dt_faa_dereg[, v39 :=  NULL]

setnames(dt_faa_dereg, 'state_abbrev', 'state')
setnames(dt_faa_dereg, 'last_act_date', 'last_action_date')

# checking in data spec, indicator_group colname seems to be type_registrant
# though distribution between 3 and 7 is different (corp vs LLC)
#round(100*table(dt_faa_dereg$indicator_group)/dim(dt_faa_dereg)[1], 0)
#round(100*table(dt_faa_master$type_registrant)/dim(dt_faa_master)[1], 0)
setnames(dt_faa_dereg, 'indicator_group', 'type_registrant')

# export country is not in master.  delete
dt_faa_dereg[, exp_country := NULL]

# after owners1-5, dereg has cancel_date and master has expiration_date
# on master these dates can be in the future
# on dereg it looks like the ones which are not missing are in the past
setnames(dt_faa_dereg, 'cancel_date', 'expiration_date')

# check consistency again
setdiff(colnames(dt_faa_master), colnames(dt_faa_dereg))
setdiff(colnames(dt_faa_dereg), colnames(dt_faa_master))
# in master and not in dereg
# [1] "type_aircraft" "type_engine"   "fract_owner"   "unique_id"

# from later work
# it is clear that "type_aircraft" "type_engine" merge on using mfr_mdl_code
# from ACFTREF.txt
dt_faa_master[, type_aircraft := NULL]
dt_faa_master[, type_engine := NULL]

# remove unique_id and then at the end create new one
dt_faa_master[, unique_id := NULL]

# "fract_owner"   will be on master records and not on dereg records
# 665,020 records
dt_faa_all <- rbindlist(list(dt_faa_master, dt_faa_dereg),
                        fill = TRUE)

#rm(dt_faa_master, dt_faa_dereg)

dt_faa_all[, unique_id_ac := 1:.N]

#fract_owner should be derivable from presence of owner2.. info - but leave for now
#table(dt_faa_master$fract_owner)


#-------------------------------------------------------------------------------
# read aircraft information

dt_faa_acftref <- fread(file=file.path(dir_rawdata, 'ReleasableAircraft/ACFTREF.txt'))
dt_faa_acftref[, V14 := NULL]
dt_faa_acftref[, "TC-DATA-SHEET" := NULL]
dt_faa_acftref[, "TC-DATA-HOLDER" := NULL]

temp_colnames <- tolower(colnames(dt_faa_acftref))
temp_colnames <- gsub("[)$]", "", temp_colnames)
temp_colnames <- gsub("[' '-]", "_", temp_colnames)
temp_colnames <- gsub("\\(", "_", temp_colnames)
colnames(dt_faa_acftref) <- temp_colnames

setnames(dt_faa_acftref,
         c("code",
           "mfr", "model", "type_acft",
           "type_eng", "ac_cat", "build_cert_ind", "no_eng",
           "no_seats", "ac_weight", "speed"),
         c("mfr_mdl_code",
           "faa_acft_make", "faa_acft_model", "faa_acft_type_acft",
           "faa_acft_type_eng", "faa_acft_ac_cat", "faa_acft_build_cert_ind", "faa_acft_no_eng",
           "faa_acft_no_seats", "faa_acft_ac_weight", "faa_acft_speed")
         )

dt_faa_acftref[, faa_acft_make := toupper(faa_acft_make)]
dt_faa_acftref[, faa_acft_model := toupper(faa_acft_model)]


#-------------------------------------------------------------------------------
# read engine information

dt_faa_engine <- fread(file=file.path(dir_rawdata, 'ReleasableAircraft/ENGINE.txt'))
#sum(!is.na(dt_faa_engine$V7))
dt_faa_engine[, V7 := NULL]

temp_colnames <- tolower(colnames(dt_faa_engine))
colnames(dt_faa_engine) <- temp_colnames

setnames(dt_faa_engine,
         c("code", "mfr", "model", "type", "horsepower","thrust"),
         c("eng_mfr_mdl", "faa_eng_make", "faa_eng_model", "faa_eng_type", "faa_eng_hp","faa_eng_thrust"))


#-------------------------------------------------------------------------------
# n_number: N-Number: Identification number assigned to aircraft.
# serial_number: Serial Number: The complete aircraft serial number assigned to the aircraft by the manufacturer.

# mfr_mdl_code: Aircraft Mfr Model Code: Aircraft Manufacturer Code + Model Code + Series Code
# eng_mfr_mdl: Engine Mfr Mode Code: Engine Manufacturer Code + Model Code
# year_mfr: Year Mfr: Year manufactured.
# type_registrant: Type Registrant: 1-9 eg 1=Individual, 3=Corporation, 7=LLC
# name: Registrant’s Name: deleted, but derived field name_num_registered
# street: Street1: deleted
# street2: Street2: deleted, but derived field street2_ind 0 or 1
# city: Registrant’s City
# state: Registrant’s State
# zip_code: Registrant’s Zip Code
# region: Registrant’s Region
# county: County Mail: A code representing the county
# country: Country Mail: A code representing the country
# last_action_date: Last Activity Date - converted from int to Date
# cert_issue_date: Certificate Issue Date - converted from int to Date
# certification: Certification requested and uses: airworthiness code and operation1-9 broken out
# type_aircraft: Type Aircraft e.g. 4 - Fixed wing single engine 5 - Fixed wing multi engine 6 - Rotorcraft
# type_engine: Type Engine e.g. 1 - Reciprocating, 2 - Turbo-prop
# status_code: Status Code e.g. V=Valid Registration
# mode_s_code: Mode S Code - Aircraft Transponder Code - removed
# fract_owner: Fractional Ownership. Y - Registration has fractional ownership blank - Registration is not fractional owned
# air_worth_date: Airworthiness Date - converted to date
# other_names_1 - removed, but derived co_owners_num
# other_names_2 - removed, but derived co_owners_num
# other_names_3 - removed, but derived co_owners_num
# other_names_4 - removed, but derived co_owners_num
# other_names_5 - removed, but derived co_owners_num
# expiration_date - convert int to date
# unique_id - Unique ID
# kit_mfr - Kit Mfr
# kit_model - Kit Model
# mode_s_code_hex: Mode S Code Hex - Mode S Code in hex format - removed
# v35 - removed

dt_faa_all[, n_number := paste0('N', n_number)]

# these 5 fields will be merged on - though they will be text
# and not codes
# dt_faa_all[, `:=` (air_mfr_code = substr(mfr_mdl_code, 1, 3),
#                    air_mdl_code = substr(mfr_mdl_code, 4, 5),
#                    air_ser_code = substr(mfr_mdl_code, 6, 7),
#                    eng_mfr_code = substr(eng_mfr_mdl, 1, 3),
#                    eng_mdl_code = substr(eng_mfr_mdl, 4, 5)
#                    )
#               ]

# these are needed for merging
#dt_faa_all[, mfr_mdl_code := NULL]
#dt_faa_all[, eng_mfr_mdl := NULL]
table(dt_faa_all$name)[1:5]
dt_faa_all[, nu_registered := .N, by = name]
dt_faa_all[name == '', nu_registered := 1]
dt_faa_all[name == 'SALE REPORTED', nu_registered := 1]
dt_faa_all[name == 'REGISTRATION PENDING', nu_registered := 1]

dt_faa_all[, name := NULL]
table(dt_faa_all$nu_registered)
# check cases with lots registered

# dt_faa_all[nu_registered == 6512 ,]$name
# dt_faa_all[nu_registered == 3537 ,]$name
# dt_faa_all[nu_registered == 3249 ,]$name
# dt_faa_all[nu_registered == 1786 ,]$name
# dt_faa_all[nu_registered == 1732 ,]$name
# dt_faa_all[nu_registered == 1651 ,]$name
# dt_faa_all[nu_registered == 1481 ,]$name
# dt_faa_all[nu_registered == 1282 ,]$name

dt_faa_all[, street := NULL]

dt_faa_all[, street2_ind := ifelse(nzchar(trimws(street2)), 1, 0)]
dt_faa_all[, street2 := NULL]
table(dt_faa_all$street2_ind)

dt_faa_all[, last_action_date := as.Date(as.character(last_action_date), format = "%Y%m%d")]
dt_faa_all[, cert_issue_date := as.Date(as.character(cert_issue_date), format = "%Y%m%d")]

dt_faa_all[, certification_len := nchar(certification)]
table(dt_faa_all$certification_len)

dt_faa_all[, `:=` (airworthiness = substr(certification, 1,1),
                      operation1 = substr(certification, 2, 2),
                      operation2 = substr(certification, 3, 3),
                      operation3 = substr(certification, 4, 4),
                      operation4 = substr(certification, 5, 5),
                      operation5 = substr(certification, 6, 6),
                      operation6 = substr(certification, 7, 7),
                      operation7 = substr(certification, 8, 8),
                      operation8 = substr(certification, 9, 9),
                      operation9 = substr(certification, 10, 10)
                      )
              ]
dt_faa_all[airworthiness %in% c('', '0'), airworthiness := 'X']
table(dt_faa_all$operation9)
dt_faa_all[airworthiness == '1', list(airworthiness, operation1)]
dt_faa_all[airworthiness == '2', certification]
dt_faa_all[airworthiness == '3', certification]

dt_faa_all[, mode_s_code := NULL]

dt_faa_all[, air_worth_date := as.Date(as.character(air_worth_date), format = "%Y%m%d")]

dt_faa_all[,
              co_owners_num := rowSums(.SD != ''),
              .SDcols = patterns('^other_names_')]
dt_faa_all[, (paste0('other_names_', 1:5)) := NULL]
dt_faa_all[, list(fract_owner, co_owners_num)]
table(dt_faa_all$fract_owner, dt_faa_all$co_owners_num)
# fract_owner mostly blank
dt_faa_all[, fract_owner := NULL]

dt_faa_all[, expiration_date := as.Date(as.character(expiration_date), format = "%Y%m%d")]

dt_faa_all[, mode_s_code_hex := NULL]

# 664,978 (loose 42 which have no match to code in acftref file)
dt_faa_all <- merge(dt_faa_all,
                    dt_faa_acftref,
                    by.x = 'mfr_mdl_code',
                    by.y = 'mfr_mdl_code',
                    all.x = FALSE,
                    all.y = FALSE)

# there are 238,833 missing eng_mfr_mdl on faa and so
# would reduce from 664,978 to 426,124
# for now keep all and create indicator for missing eng_mfr_mdl
dt_faa_all <- merge(dt_faa_all,
                    dt_faa_engine,
                    by.x = 'eng_mfr_mdl',
                    by.y = 'eng_mfr_mdl',
                    all.x = TRUE,
                    all.y = FALSE)

dt_faa_all[, eng_mfr_mdl_miss_ind := 1 * is.na(eng_mfr_mdl)]


# claims start from 2008
# if expiration_date < 31Dec2007 then delete
# if cert_issue_date = max(1Jan2018, cert_issue_date)
# recalculate ex
from_date <- as.Date('20080101', format = "%Y%m%d")
# max ev_date in ntsb
to_date <- as.Date('20230830', format = "%Y%m%d")
dim(dt_faa_all)
dt_faa_all <- dt_faa_all[expiration_date >= from_date, ]
dim(dt_faa_all)

dt_faa_all[, start_date := pmax(from_date, cert_issue_date)]
dt_faa_all[, end_date := pmin(to_date, expiration_date)]

# one case where expiration_date before start_date
# 220 cases same day i.e.
# leaves 410,083
#dt_faa_all[expiration_date == start_date, list(expiration_date, start_date)]
dt_faa_all <- dt_faa_all[expiration_date > start_date,]

#expand lines to have one line per year
dt_faa_all[, `:=`(start_year = year(start_date), end_year = year(end_date))]
dt_expanded <- dt_faa_all[ ,
                          list(curr_year = seq(start_year, end_year)),
                          by = unique_id_ac]
# now merge back onto dt_faa_all
# on each line
dt_faa_all <- merge(dt_expanded,
                    dt_faa_all,
                    by = 'unique_id_ac')
rm(dt_expanded)

# finally create start_date and end_date for each year
dt_faa_all[, start_date := pmax(start_date, as.Date(paste0(curr_year, '0101'), format = "%Y%m%d"))]
dt_faa_all[, end_date := pmin(end_date, as.Date(paste0(curr_year, '1231'), format = "%Y%m%d"))]

dt_faa_all[, start_year := NULL]
dt_faa_all[, end_year := NULL]

dt_faa_all[, unique_id_line := 1:.N]


#-------------------------------------------------------------------------------
# NTSB contains aircraft and accident details for aircraft involved in events
# Connect to NTSB database

con <- dbConnect(RSQLite::SQLite(), "/Users/axc/Dropbox/CAS/NTSB_data_prep/rawdata/migration-export.sqlite")
dbListTables(con)
# my convention is dt_ prefix for data.tables
# not to be confused with the dt_aircraft in the database
# 26,630 aircraft in the database
dt_ntsb_aircraft <- dbReadTable(con, "aircraft")
dt_ntsb_aircraft <- as.data.table(dt_ntsb_aircraft)
# 26,214 events
dt_ntsb_events <- dbReadTable(con, "events")
dt_ntsb_events <- as.data.table(dt_ntsb_events)
dt_ntsb_events[, ev_date := as.Date(ev_date)]

dbDisconnect(con)
rm(con)

# merge by ntsb_no but clean first
dim(dt_ntsb_aircraft)
dt_ntsb_aircraft <- dt_ntsb_aircraft[!is.na(regis_no), ]
dt_ntsb_aircraft <- dt_ntsb_aircraft[!(regis_no %in% c('UNREG', 'UNK', 'unknown')), ]
dim(dt_ntsb_aircraft)

dt_ntsb_aircraft[, acft_make := toupper(acft_make)]
dt_ntsb_aircraft[, acft_model := toupper(acft_model)]

setnames(dt_ntsb_aircraft, 'regis_no', 'n_number')

# 25,800 merged by ntsb_no
dt_ntsb <- merge(dt_ntsb_aircraft[, list(n_number, ntsb_no, acft_serial_no, acft_make, acft_model, acft_series)],
                 dt_ntsb_events[, list(ntsb_no, ev_type, ev_date)],
                 by = 'ntsb_no')

setnames(dt_ntsb, 'acft_make', 'ntsb_acft_make')
setnames(dt_ntsb, 'acft_model', 'ntsb_acft_model')
setnames(dt_ntsb, 'acft_series', 'ntsb_acft_series')

dt_ntsb[, nucl := .N, by = n_number]
table(dt_ntsb$nucl)

sum(duplicated(dt_ntsb$ntsb_no))

# originally was like this - so cleaned regis_no above
# looks like something is wrong
#    1     2     3     4     7    35   128
#24117  1398    96    12    14    35   128

# regis_no: NA, UNREG, UNK, unknown
#dt_ntsb[nucl == 4,]
#dt_ntsb[nucl == 7,]
#dt_ntsb[nucl == 35,]
#dt_ntsb[nucl == 128,]

# having checked number of claims per craft - delete
dt_ntsb[, nu_cl := 0]


#-------------------------------------------------------------------------------
# merge NTSB ev_type and ev_date with FAA data

# do n_numbers appear twice on dt_faa_all
# there are no dups just in master
# but there are dups in dereg
dt_faa_all[, nu_n_number := .N, by = list(n_number, source)]
# table(dt_faa_all$nu_n_number, dt_faa_all$source)

# but there are plenty in master that were in dereg
# dt_faa_all[, nu_n_number := .N, by = list(n_number)]
# table(dt_faa_all$nu_n_number, dt_faa_all$source)

# visually inspect
# dt_dups <- dt_faa_all[nu_n_number >= 4, ]
# setorder(dt_dups, 'n_number', "cert_issue_date")

# 1. there are records with missing cert_issue_date
# 2. otherwise should merge if claims between between cert_issue_date and expiration_date

# on master, 8k missing, 284k not missing
# on dereg, 103k missing, 270k not missing
dt_faa_all[, cert_issue_date_miss := 1 * is.na(cert_issue_date)]
# dt_faa_all[, .N, by=list(cert_issue_date_miss, source)]
dt_temp <- dt_faa_all[cert_issue_date_miss == 1 & !is.na(expiration_date), ]

# without cert_issue_date there is no way to estimate the exposure
# or to be sure which n_number to merge the claim to
# I could do something with the expiration_date on the missing cert_issue_date_miss

dim(dt_faa_all)
dt_faa_all <- dt_faa_all[!is.na(cert_issue_date), ]
dim(dt_faa_all)
dt_faa_all[, cert_issue_date_miss := NULL]

# I need to inspect cases of missing expiration_date
# is it only missing on the last cert_issue_date_miss
dt_faa_all[, expiration_date_miss := 1 * is.na(expiration_date)]
table(dt_faa_all$expiration_date_miss)
setorder(dt_faa_all, 'cert_issue_date', 'expiration_date')

# in the case of twoor more nu_n_number there are
# 681 missing and almost all of these have per 1985 cert_issue_date
dt_temp <- dt_faa_all[nu_n_number >= 2, ]
setorder(dt_temp, 'n_number',  'cert_issue_date', 'expiration_date')
dt_miss <- dt_faa_all[expiration_date_miss == 1, ]

dt_faa_all <- dt_faa_all[!((nu_n_number >= 2) & (expiration_date_miss == 1)), ]

# there are just 301 missing expiration_date_miss otherwise
# these are also all pre 1985
dt_miss <- dt_faa_all[expiration_date_miss == 1, ]
dt_faa_all <- dt_faa_all[!(expiration_date_miss == 1), ]
dt_faa_all[, expiration_date_miss := NULL]

# dt_faa_ntsb <- sqldf("
# SELECT dt_faa_all.*,
#        dt_ntsb.ntsb_no, dt_ntsb.ev_date, dt_ntsb.ev_type,
#        dt_ntsb.ntsb_acft_make, dt_ntsb.ntsb_acft_model
# FROM dt_faa_all
# JOIN dt_ntsb
# ON dt_faa_all.n_number = dt_ntsb.regis_no
#    AND dt_ntsb.ev_date BETWEEN dt_faa_all.cert_issue_date AND dt_faa_all.expiration_date
# ")
#dt_faa_ntsb <- data.table(dt_faa_ntsb)

# due to manual check of a small number claims being out of period by a few months
# I decided instead to merge all and then to calculate how far out and
# to accept out by a year or so if it helps to merge more

# dt_ntsb has 25,623 events
# 23,973 lines on merged file of which 19,131 are unique
dt_ntsb_faa <- merge(dt_ntsb,
                     dt_faa_all[, list(unique_id_line, n_number,
                                       start_date, end_date, cert_issue_date,
                                       faa_acft_make)],
                     all.x = FALSE,
                     all.y = FALSE,
                     by.x = 'n_number',
                     by.y = 'n_number')

# 18,567 unique claim numbers
length(unique(dt_ntsb_faa$ntsb_no))

dt_ntsb_faa[, merge_days := 0]
dt_ntsb_faa[ev_date > end_date, merge_days := ev_date - end_date]
dt_ntsb_faa[ev_date < start_date, merge_days := start_date - ev_date]


# try to keep as many has we can
# take the least merge_days for each ntsb_no
# 18,567
dt_ntsb_faa <- dt_ntsb_faa[, .SD[which.min(merge_days)], by = 'ntsb_no']
#vec_temp <- table(dt_ntsb_faa$merge_days)
#hist(dt_ntsb_faa$merge_days)

# allow two years leeway- 12,360
dt_ntsb_faa <- dt_ntsb_faa[merge_days < 730 & ev_date >= cert_issue_date]
dt_ntsb_faa[, merge_days := NULL]

# number merged by year
# the events go from 2008 to 2023, about 800 per year
dt_results <- dt_ntsb_faa[, .N, by = .(ev_year = year(ev_date))]
setorder(dt_results, 'ev_year')
dt_results

# original events data also goes from 2008 and has about 1600 per year
# investigate non match
dt_results <- dt_ntsb[, .N, by = .(ev_year = year(ev_date))]
setorder(dt_results, 'ev_year')
dt_results

# manually review some non merges
#dt_non_merge <- dt_ntsb[!dt_ntsb_faa, on = 'ntsb_no']

# N7380U, 2008 # event date 7/2/2008 and reg is 11/6/2018 to 27/8/2018
# N6827M, 2008 # event date 14/3/2008 and reg is 12/1/2009 to 30.4.2029
# N180JP, 2008 # event date 23/3/2008 and reg is 1/7/2020 to 31/7/2027
# n_num <- '180JP'
# dt_ntsb[regis_no == paste0('N',n_num)]
# dt_faa_dereg[n_number == n_num, list(n_number, mfr_mdl_code, year_mfr, air_worth_date, expiration_date, cert_issue_date)]
# dt_faa_master[n_number == n_num, list(n_number, mfr_mdl_code, year_mfr, air_worth_date, expiration_date, cert_issue_date)]

# manually review poor merges - some due to missing reg dates and so
# using the record from dereg - could try various things
# but running out of time
# N1001N ev date 6/12/2013
# N1001R
# N10033
# dt_non_merge <- dt_ntsb_faa[merge_days > 2000]
# n_num <- '1001N'
# dt_ntsb[regis_no == paste0('N',n_num)]
# dt_faa_dereg[n_number == n_num, list(n_number, mfr_mdl_code, year_mfr, air_worth_date, expiration_date, cert_issue_date)]
# dt_faa_master[n_number == n_num, list(n_number, mfr_mdl_code, year_mfr, air_worth_date, expiration_date, cert_issue_date)]

# there are 3 duplicated of 12,322 out of 25,623 which merged
# same n_number overlapping dates
idx_dup <- duplicated(dt_faa_ntsb$ntsb_no, fromLast = TRUE) |
           duplicated(dt_faa_ntsb$ntsb_no, fromLast = FALSE)
dt_temp <- dt_faa_ntsb[idx_dup, ]

# 991 don't match the make between FAA and NTSB - delete
idx <- substr(dt_ntsb_faa$faa_acft_make, 1, 5) != substr(dt_ntsb_faa$ntsb_acft_make, 1, 5)
dt_temp <- dt_ntsb_faa[idx,]
dt_ntsb_faa <- dt_ntsb_faa[!idx,]

# of the remaining 11,485, 701 don't have engine details - keep for now
table(dt_ntsb_faa$eng_mfr_mdl_miss_ind)
#dt_ntsb_faa <- dt_ntsb_faa[eng_mfr_mdl_miss_ind == 0,]
#dt_ntsb_faa[, eng_mfr_mdl_miss_ind := NULL]

# this leaves 13,450 which merged out of 25,000
# create a unique id on dt_faa_all
# merge claims bank to
sum(duplicated(dt_ntsb_faa$ntsb_no))

# 250 with more than one merged claim
sum(duplicated(dt_ntsb_faa$unique_id_ac))

# create one line per unique_id_ac with number of claims
dt_merge <- dt_ntsb_faa[,
                        list(nu_cl = .N),
                        by = unique_id_line]

dim(dt_faa_all) # 2884186     54
dim(dt_merge)   # 13,200       2
sum(dt_merge$nu_cl) # 13,450

dt_faa_all <- merge(dt_faa_all,
                    dt_merge,
                    by.x = 'unique_id_line',
                    by.y = 'unique_id_line',
                    all.x = TRUE,
                    all.y = TRUE)
dim(dt_faa_all) # 2884186     55
dt_faa_all[is.na(nu_cl), nu_cl := 0]
sum(dt_faa_all$nu_cl) # 13,450

dt_faa_all[, ex := pmin(1, as.integer(end_date - start_date + 1) / 365.25)]

dt_results <- dt_faa_all[, .N, by = .(year = year(start_date))]
setorder(dt_results, 'year')
dt_results

sum(dt_faa_all$nu_cl) / sum(dt_faa_all$ex)

dt_faa_all[, eng_mfr_mdl_miss_ind := NULL]
dt_faa_all[, curr_year := NULL]
dt_faa_all[, certification_len := NULL]
colnames(dt_faa_all)

dt_faa_ntsb <- dt_faa_all
rm(dt_faa_all)

dt_faa_ntsb[, certification := NULL]

# 1 - Standard
table(dt_faa_ntsb[airworthiness == '1']$operation1)
dt_faa_ntsb[(airworthiness == '1') &
  !(operation1 %in%  c('A', 'B', 'C', 'G', 'N', 'T', 'U')),
            operation1 := 'X']
dt_faa_ntsb[(airworthiness == '1'), operation := operation1]
table(dt_faa_ntsb[airworthiness == '1']$operation1)

# 2 - Limited
table(dt_faa_ntsb[airworthiness == '2']$operation1)
dt_faa_ntsb[airworthiness == '2', operation := 'X']
table(dt_faa_ntsb[airworthiness == '2']$operation)

# 3 - Restricted
# operation1 mostly 1 - Agriculture and Pest Control
# but often goes with operation2 4 - Forest
# anyway use 1 and fill with 2 & 3 if 0 or blank
table(dt_faa_ntsb[airworthiness == '3']$operation1)
table(dt_faa_ntsb[airworthiness == '3']$operation2)
table(dt_faa_ntsb[airworthiness == '3']$operation3)

dt_faa_ntsb[(airworthiness == '3'), operation := operation1]
dt_faa_ntsb[(airworthiness == '3') & (operation %in% c('', '0')),
            operation := operation2]
dt_faa_ntsb[(airworthiness == '3') & (operation %in% c('', '0')),
            operation := operation3]
dt_faa_ntsb[(airworthiness == '3') & (operation %in% c('', '0')),
            operation := '0']
table(dt_faa_ntsb[(airworthiness == '3')]$operation)

# 4 - experimental is mostly 2-exhibition or 8A - Reg. Prior to 01/31/08
# so just set all to X
table(dt_faa_ntsb[airworthiness == '4']$operation1)
table(dt_faa_ntsb[airworthiness == '4']$operation2)
dt_faa_ntsb[airworthiness == '4' & operation2 != '',
            list(airworthiness,
                   operation1, operation2, operation3
                   )]

dt_faa_ntsb[(airworthiness == '4'), operation := 'X']

#for 5- 5 - Provisional:  only 40 all 1
table(dt_faa_ntsb[airworthiness == '5']$operation1)
table(dt_faa_ntsb[airworthiness == '5']$operation2)
dt_faa_ntsb[(airworthiness == '5'), operation := 'X']

# for 6- 6 – Multiple, operation1 mostly 1=standard,
# operation2 mostly 3
# so use operation3 which seems to properly differentiate
# and is the same as codes for 3-restricted
table(dt_faa_ntsb[airworthiness == '6']$operation1)
table(dt_faa_ntsb[airworthiness == '6']$operation2)
table(dt_faa_ntsb[airworthiness == '6']$operation3)
dt_faa_ntsb[(airworthiness == '6'), operation := operation3]
dt_faa_ntsb[(airworthiness == '6') & (operation3 == ''),
            operation := '0']
table(dt_faa_ntsb[(airworthiness == '6')]$operation)

# for 7 - primary: only 15 of these in total split
# 15 for r&d rest for amateur built
table(dt_faa_ntsb[airworthiness == '7']$operation1)
table(dt_faa_ntsb[airworthiness == '7']$operation2)
table(dt_faa_ntsb[airworthiness == '7']$operation3)
dt_faa_ntsb[(airworthiness == '7'), operation := 'X']

# 8 - Special Flight Permit - mostly 1 - Ferry flight for repairs, alterations, maintenance or storage
# about 1400 are 3-Operation in excess of maximum certificated
# but don't break out
table(dt_faa_ntsb[airworthiness == '8']$operation1)
table(dt_faa_ntsb[airworthiness == '8']$operation2)
table(dt_faa_ntsb[airworthiness == '8']$operation3)
dt_faa_ntsb[(airworthiness == '8'), operation := 'X']

# 9 – Light Sport, operation1 is A(airplane)G(glider)LPW
# break out A only rest as X
table(dt_faa_ntsb[airworthiness == '9']$operation1)
table(dt_faa_ntsb[airworthiness == '9']$operation2)
table(dt_faa_ntsb[airworthiness == '9']$operation3)
dt_faa_ntsb[(airworthiness == '9'), operation := 'X']
dt_faa_ntsb[(airworthiness == '9') & (operation1 == 'A'),
            operation := 'A']


table(dt_faa_ntsb$operation, dt_faa_ntsb$airworthiness)

dt_faa_ntsb[, `:=` (operation1 = NULL,
                    operation2 = NULL,
                    operation3 = NULL,
                    operation4 = NULL,
                    operation5 = NULL,
                    operation6 = NULL,
                    operation7 = NULL,
                    operation8 = NULL,
                    operation9 = NULL
                    )
            ]
colnames(dt_faa_ntsb)

save(dt_faa_ntsb, file = file.path(dir_rdata, 'dt_faa_ntsb.RData'))


