version 19.5
clear all
set more off

local data_file : environment MOROCCO_Y1_SCORE_DATA
local ster_file : environment MOROCCO_Y1_STER_FILE
local subject_label : environment MOROCCO_Y1_SUBJECT
local stored_score : environment MOROCCO_Y1_STORED_SCORE
local output_log : environment MOROCCO_Y1_OUTPUT_LOG
local output_summary : environment MOROCCO_Y1_OUTPUT_SUMMARY

if `"`data_file'"' == "" | `"`ster_file'"' == "" | ///
    `"`subject_label'"' == "" | `"`stored_score'"' == "" | ///
    `"`output_log'"' == "" | `"`output_summary'"' == "" {
    display as error "Required MOROCCO_Y1_* environment variable is missing."
    exit 198
}

capture log close _all
log using "`output_log'", replace text name(y1_score_verify)

display as text "VERIFY_START"
display as text "subject=`subject_label'"
display as text "stata_version=`c(stata_version)'"

confirm file "`data_file'"
confirm file "`ster_file'"
use "`data_file'", clear
confirm numeric variable baseline
confirm numeric variable `stored_score'

local control_var ""
capture confirm numeric variable treated
if !_rc local control_var "treated"
if `"`control_var'"' == "" {
    capture confirm numeric variable treat
    if !_rc local control_var "treat"
}
if `"`control_var'"' == "" {
    display as error "Neither treated nor treat is available."
    exit 111
}

display as text "control_variable=`control_var'"
tabulate `control_var' baseline, missing

estimates use "`ster_file'"
capture drop audit_raw_theta audit_raw_se audit_standardized audit_difference audit_abs_difference
uirt_theta audit_raw_theta audit_raw_se

quietly summarize audit_raw_theta if baseline == 0 & `control_var' == 0
local control_n = r(N)
local control_mean = r(mean)
local control_sd = r(sd)
if `control_n' == 0 | missing(`control_sd') | `control_sd' <= 0 {
    display as error "Cannot recover a valid endline-control transformation."
    exit 498
}

generate double audit_standardized = (audit_raw_theta - `control_mean') / `control_sd'
generate double audit_difference = audit_standardized - `stored_score'
generate double audit_abs_difference = abs(audit_difference)

quietly count if audit_standardized < . & `stored_score' < .
local comparison_n = r(N)
quietly summarize audit_difference
local difference_mean = r(mean)
local difference_sd = r(sd)
local difference_min = r(min)
local difference_max = r(max)
quietly summarize audit_abs_difference
local maximum_absolute_difference = r(max)
quietly correlate audit_standardized `stored_score'
local correlation = r(rho)

display as text "TIEOUT_RESULTS_START"
display as result "control_n=`control_n'"
display as result "control_raw_mean=`control_mean'"
display as result "control_raw_sd=`control_sd'"
display as result "comparison_n=`comparison_n'"
display as result "difference_mean=`difference_mean'"
display as result "difference_sd=`difference_sd'"
display as result "maximum_absolute_difference=`maximum_absolute_difference'"
display as result "correlation=`correlation'"
display as text "TIEOUT_RESULTS_END"

file open summary using "`output_summary'", write replace text
file write summary "verification_status=complete" _n
file write summary "subject=`subject_label'" _n
file write summary "stata_version=`c(stata_version)'" _n
file write summary "control_variable=`control_var'" _n
file write summary "control_n=`control_n'" _n
file write summary "control_raw_mean=`control_mean'" _n
file write summary "control_raw_sd=`control_sd'" _n
file write summary "comparison_n=`comparison_n'" _n
file write summary "difference_mean=`difference_mean'" _n
file write summary "difference_sd=`difference_sd'" _n
file write summary "difference_min=`difference_min'" _n
file write summary "difference_max=`difference_max'" _n
file write summary "maximum_absolute_difference=`maximum_absolute_difference'" _n
file write summary "correlation=`correlation'" _n
file close summary

display as text "VERIFY_COMPLETE"
log close y1_score_verify
exit, clear

