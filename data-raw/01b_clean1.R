# 01a_read_data.R

# libraries needed
library(data.table)
library(RSQLite)
library(sqldf)
library(lubridate)

library(mgcv)

dir_project <- getwd()
dir_rawdata <- file.path(dir_project, 'rawdata')
dir_rdata <- file.path(dir_project, 'data')

load(file = file.path(dir_rdata, 'dt_faa_ntsb.RData'))
dim(dt_faa_ntsb)

vars_all <- colnames(dt_faa_ntsb)
sum(dt_faa_ntsb$nu_cl)
fn_table <- function(var_check, order='ex'){
  dt_results <- dt_faa_ntsb[, list(ex=round(sum(ex)/1000,0),
                                   nu_cl=sum(nu_cl),
                                   freq=sum(nu_cl) / sum(ex)),
                            by=var_check]
  if (order=='ex') {
    setorder(dt_results, -ex)
  } else {
    setorderv(dt_results, var_check)
    }
  dt_results
}


var_target <- 'nu_cl'
var_offset <- 'ex'
vars_ind <- setdiff(vars_all,
                    c(var_target,
                      var_offset,
                      c("unique_id_ac", "unique_id_line", "eng_mfr_mdl", "mfr_mdl_code",
                      "n_number", "serial_number", "city","zip_code",
                      "last_action_date", "cert_issue_date", "air_worth_date",
                      "expiration_date",
                      "start_date", "end_date")))
vars_ind

# year_mfr: about 20% missing for year_mfr and have veh_age estimated from cert_issue_date
table(dt_faa_ntsb$year_mfr, useNA = 'always')
vars_ind <- setdiff(vars_ind, "year_mfr")
vars_ind

# type_registrant 17 missing, corporation and LLC similar things
# possibly different freq due to age (corporation was more on dereg )
# 1 - Individual
# 2 - Partnership
# 3 - Corporation
# 4 - Co-Owned
# 5 – Government
# 7 - LLC
# 8 - Non Citizen Corporation 9 - Non Citizen Co-Owned
table(dt_faa_ntsb$type_registrant, useNA = 'always')
fn_table('type_registrant')
dt_faa_ntsb[, type_registrant := as.character(type_registrant)]
dt_faa_ntsb[is.na(type_registrant), type_registrant := '1']
fn_table('type_registrant')

# state, region, county, country
fn_table('state')
fn_table('region')
fn_table('county')
fn_table('country')

# for now use region only
# 1 - Eastern
# 2 - Southwestern
# 3 - Central
# 4 - Western-Pacific
# 5 - Alaskan
# 7 - Southern
# 8 - European
# C - Great Lakes
# E - New England
# S - Northwest Mountain
vars_ind <- setdiff(vars_ind, c('state', 'county', 'country'))
table(dt_faa_ntsb$region, useNA = 'always')
# put missings as X though better to calculate from state
dt_faa_ntsb[region == '', region := 'X']
table(dt_faa_ntsb$region, useNA = 'always')

# status_code some look like leakage
# also this was the latest status on pulled data
# and will not be correct for the historic lines created
vars_ind
table(dt_faa_ntsb$status_code, useNA = 'always')
fn_table('status_code')
dt_faa_ntsb[, status_code := NULL]
vars_ind <- setdiff(vars_ind, c('status_code'))

# kit_mfr, kit_model
table(dt_faa_ntsb$kit_mfr, useNA = 'always')[1:5]
table(dt_faa_ntsb$kit_model, useNA = 'always')[1:5]
# replace with kit_ind
dt_faa_ntsb[, kit_indyn := "N"]
dt_faa_ntsb[!(kit_mfr == ''), kit_indyn := "Y"]
table(dt_faa_ntsb$kit_indyn, useNA = 'always')
dt_faa_ntsb[, kit_mfr := NULL]
dt_faa_ntsb[, kit_model := NULL]
vars_ind <- setdiff(vars_ind, c('kit_mfr', 'kit_model'))
vars_ind <- c(vars_ind, 'kit_indyn')

# source
table(dt_faa_ntsb$source, useNA = 'always')
vars_ind <- setdiff(vars_ind, c('source'))

#nu_registered
table(dt_faa_ntsb$nu_registered, useNA = 'always')

#street2_ind
dt_faa_ntsb[, street2_ind := as.character(street2_ind)]
table(dt_faa_ntsb$street2_ind, useNA = 'always')

# airworthiness
table(dt_faa_ntsb$airworthiness, useNA = 'always')

#co_owners_num - set to indicator of 0
table(dt_faa_ntsb$co_owners_num, useNA = 'always')
fn_table('co_owners_num')
dt_faa_ntsb[, co_ownership := 'N']
dt_faa_ntsb[co_owners_num >= 1, co_ownership := 'Y']
vars_ind <- setdiff(vars_ind, 'co_owners_num')
vars_ind <- c(vars_ind, 'co_ownership')

#"faa_acft_make"           "faa_acft_model"
#"faa_acft_type_acft"      "faa_acft_type_eng"
#"faa_acft_ac_cat"         "faa_acft_build_cert_ind"
#"faa_eng_make"            "faa_eng_model"
#"faa_eng_type"
length(unique(dt_faa_ntsb$faa_acft_make)) # 48798
length(unique(dt_faa_ntsb$faa_acft_model)) # 24985
length(unique(dt_faa_ntsb$faa_acft_type_acft)) # 11
length(unique(dt_faa_ntsb$faa_acft_type_eng)) # 12
length(unique(dt_faa_ntsb$faa_acft_ac_cat)) # 3
length(unique(dt_faa_ntsb$faa_acft_build_cert_ind)) # 3
length(unique(dt_faa_ntsb$faa_eng_make)) # 242
length(unique(dt_faa_ntsb$faa_eng_model)) # 2364
length(unique(dt_faa_ntsb$faa_eng_type)) # 11

table(dt_faa_ntsb$faa_acft_type_acft, useNA = 'always')
table(dt_faa_ntsb$faa_acft_type_eng, useNA = 'always')
table(dt_faa_ntsb$faa_acft_ac_cat, useNA = 'always')
table(dt_faa_ntsb$faa_acft_build_cert_ind, useNA = 'always')
table(dt_faa_ntsb$faa_eng_type, useNA = 'always')

#1 - Glider
#2 - Balloon
#3 - Blimp/Dirigible
#4 - Fixed wing single engine
#5 - Fixed wing multi engine
# 6 - Rotorcraft
#7 - Weight-shift-control
#8 - Powered Parachute
#9 - Gyroplane
#H - Hybrid Lift
#O - Other
dt_faa_ntsb[, faa_acft_type_acft := as.character(faa_acft_type_acft)]
fn_table('faa_acft_type_acft')
# keep 4/5/6 only
dt_faa_ntsb <- dt_faa_ntsb[faa_acft_type_acft %in% c('4','5','6')]

dt_faa_ntsb[, faa_acft_type_eng := as.character(faa_acft_type_eng)]
dt_faa_ntsb[, faa_acft_ac_cat := as.character(faa_acft_ac_cat)]
dt_faa_ntsb[, faa_acft_build_cert_ind := as.character(faa_acft_build_cert_ind)]

dt_faa_ntsb[, faa_eng_type := as.character(faa_eng_type)]
dt_faa_ntsb[is.na(faa_eng_type), faa_eng_type := 'X']

vars_ind <- setdiff(vars_ind,
                    c('faa_acft_make', 'faa_acft_model',
                      'faa_eng_make', 'faa_eng_model'))

table(dt_faa_ntsb$faa_acft_no_eng, useNA = 'always')
fn_table('faa_acft_no_eng', order = 'var')
# quick look at 2 examples, one is error, one is massive airship
dt_temp <- dt_faa_ntsb[faa_acft_no_eng > 4, ]
# limit to 4 or less
dt_faa_ntsb <- dt_faa_ntsb[faa_acft_no_eng <= 4, ]
fn_table('faa_acft_no_eng', order = 'var')

table(dt_faa_ntsb$faa_acft_no_seats, useNA = 'always')
fn_table('faa_acft_no_seats', order = 'var')
dt_faa_ntsb[faa_acft_no_seats > 400, faa_acft_no_seats := 400]
fn_table('faa_acft_no_seats', order = 'var')

table(dt_faa_ntsb$faa_acft_ac_weight, useNA = 'always')
fn_table('faa_acft_ac_weight', order = 'var')

table(dt_faa_ntsb$faa_acft_speed, useNA = 'always')
fn_table('faa_acft_speed', order = 'var')
dt_faa_ntsb[faa_acft_speed > 400, faa_acft_speed := 400]
fn_table('faa_acft_speed', order = 'var')

table(dt_faa_ntsb$faa_eng_hp, useNA = 'always')
fn_table('faa_eng_hp', order = 'var')
# do make it easier to deal with na and zero, turn into categorical
# A 1-150
# B 101-200
# C 201-300
# D =

dt_faa_ntsb[faa_eng_hp >= 1 & faa_eng_hp <= 150, faa_eng_hp := 100]
dt_faa_ntsb[faa_eng_hp > 150, faa_eng_hp := round(faa_eng_hp, -2)]
dt_faa_ntsb[faa_eng_hp > 1500, faa_eng_hp := 1500]
fn_table('faa_eng_hp', order = 'var')

dt_faa_ntsb[is.na(faa_eng_hp), faa_eng_hp_char := 'X']
dt_faa_ntsb[faa_eng_hp == 0, faa_eng_hp_char := 'Y']
dt_faa_ntsb[faa_eng_hp == 100, faa_eng_hp_char := 'A']
dt_faa_ntsb[faa_eng_hp == 200, faa_eng_hp_char := 'B']
dt_faa_ntsb[faa_eng_hp == 300, faa_eng_hp_char := 'C']
dt_faa_ntsb[faa_eng_hp >= 400 & faa_eng_hp <= 800, faa_eng_hp_char := 'D']
dt_faa_ntsb[faa_eng_hp >= 900 & faa_eng_hp <= 1400, faa_eng_hp_char := 'E']
dt_faa_ntsb[faa_eng_hp == 1500, faa_eng_hp_char := 'F']
fn_table('faa_eng_hp_char', order = 'var')
vars_ind <- setdiff(vars_ind, 'faa_eng_hp')
vars_ind <- c(vars_ind, 'faa_eng_hp_char')


table(dt_faa_ntsb$faa_eng_thrust, useNA = 'always')
fn_table('faa_eng_thrust', order = 'var')
dt_faa_ntsb[faa_eng_thrust > 50000, faa_eng_thrust := 50000]
dt_faa_ntsb[faa_eng_thrust > 1, faa_eng_thrust := round(faa_eng_thrust, -3)]
dt_faa_ntsb[faa_eng_thrust > 1000, faa_eng_thrust := round(faa_eng_thrust, -3)]
dt_faa_ntsb[faa_eng_thrust > 10000, faa_eng_thrust := round(faa_eng_thrust, -4)]
dt_faa_ntsb[faa_eng_thrust > 1 & faa_eng_thrust < 10000, faa_eng_thrust := 10000]

fn_table('faa_eng_thrust', order = 'var')
#dt_faa_ntsb <- dt_faa_ntsb[!is.na(faa_eng_thrust)]
dt_faa_ntsb[is.na(faa_eng_thrust), faa_eng_thrust_char := 'X']
dt_faa_ntsb[faa_eng_thrust == 0, faa_eng_thrust_char := 'Y']
dt_faa_ntsb[faa_eng_thrust == 10000, faa_eng_thrust_char := 'A']
dt_faa_ntsb[faa_eng_thrust == 20000, faa_eng_thrust_char := 'B']
dt_faa_ntsb[faa_eng_thrust == 30000, faa_eng_thrust_char := 'B']
dt_faa_ntsb[faa_eng_thrust == 40000, faa_eng_thrust_char := 'B']
dt_faa_ntsb[faa_eng_thrust == 50000, faa_eng_thrust_char := 'C']

vars_ind <- setdiff(vars_ind, 'faa_eng_thrust')
vars_ind <- c(vars_ind, 'faa_eng_thrust_char')

table(dt_faa_ntsb$operation, useNA = 'always')
dt_faa_ntsb[is.na(operation), operation := 'X']
table(dt_faa_ntsb$operation, useNA = 'always')

table(dt_faa_ntsb$kit_indyn, useNA = 'always')

# feature engineering
dt_faa_ntsb[, veh_age := (year(start_date) - year(cert_issue_date))]
dt_faa_ntsb[, veh_age := pmin(50, veh_age)]
dim(dt_faa_ntsb[veh_age == 0])

vars_ind <- c(vars_ind, 'veh_age')
dt_results <- fn_table('veh_age', order='var')
plot(dt_results$freq)

# check for ex == 0
dt_faa_ntsb[ex == 0, list(nu_cl = sum(nu_cl))]
dt_faa_ntsb <- dt_faa_ntsb[ex > 0,]

fmla_ <- as.formula(paste0(var_target, ' ~ ', paste0(vars_ind, collapse = " + ")))

sapply(dt_faa_ntsb[, vars_ind, with = FALSE], function(x) sum(is.na(x)))

glm_1 <- glm(fmla_,
             family = poisson,
             offset = log(dt_faa_ntsb[[var_offset]]),
             data = dt_faa_ntsb)
summary(glm_1)

vars_types <- sapply(dt_faa_ntsb[, vars_ind, with = FALSE], is.numeric)
vars_ind_num <- vars_ind[vars_types]
vars_ind_char <- setdiff(vars_ind, vars_ind_numeric)

dt_faa_ntsb <- dt_faa_ntsb[, (vars_ind_char) := lapply(.SD, as.factor), .SDcols = vars_ind_char]


sapply(dt_faa_ntsb[, vars_ind_char, with = FALSE], function(x) length(unique(x)))
sapply(dt_faa_ntsb[, vars_ind_char, with = FALSE], function(x) sum(is.na(x)))

sapply(dt_faa_ntsb[, vars_ind_num, with = FALSE], function(x) sum(is.na(x)))

fmla_n <- paste0(paste0("s(", vars_ind_num, ", bs='cr', k=3)"), collapse = " + ")

fmla_ <- as.formula(paste0(var_target, ' ~ ',
                           fmla_n,
                           ' + ',
                           paste0(vars_ind_char, collapse = " + ")))

bam_1 <- bam(
             fmla_,
             family=poisson(),
             offset = log(dt_faa_ntsb[[var_offset]]),
             data = dt_faa_ntsb)

plot(bam_1)
summary(bam_1)
table(dt_faa_ntsb$type_registrant)
dt_faa_ntsb_clean <- dt_faa_ntsb
save(dt_faa_ntsb, file = file.path(dir_rdata, 'dt_faa_ntsb_clean.RData'))

#install.packages("devtools")
#install.packages("usethis")
library(devtools)
library(usethis)


create_package("/Users/axc/Dropbox/CAS/packages/FAANTSB")
load(file = file.path('/Users/axc/Dropbox/CAS/NTSB_data_prep/data', 'dt_faa_ntsb_clean.RData'))
dt_faa_ntsb_clean <- dt_faa_ntsb
rm(dt_faa_ntsb)
usethis::use_data(dt_faa_ntsb_clean)
usethis::use_data_raw()

usethis::use_git()
library(roxygen2)

devtools::document()
devtools::check()
devtools::build()

install.packages("/Users/axc/Dropbox/CAS/packages/FAANTSB_0.0.0.9000.tar.gz",
                 repos = NULL,
                 type = "source")

usethis::use_vignette("FAANTSB-introduction")
devtools::build_vignettes()
