version 19.5
clear all
set more off

local ster_file : environment MOROCCO_Y1_STER_FILE
local subject_label : environment MOROCCO_Y1_SUBJECT
local output_log : environment MOROCCO_Y1_OUTPUT_LOG
local output_summary : environment MOROCCO_Y1_OUTPUT_SUMMARY
local output_params : environment MOROCCO_Y1_OUTPUT_PARAMS
local output_group : environment MOROCCO_Y1_OUTPUT_GROUP

if `"`ster_file'"' == "" | `"`subject_label'"' == "" | ///
    `"`output_log'"' == "" | `"`output_summary'"' == "" | ///
    `"`output_params'"' == "" | `"`output_group'"' == "" {
    display as error "Required MOROCCO_Y1_* environment variable is missing."
    exit 198
}

capture log close _all
log using "`output_log'", replace text name(y1_ster_probe)

display as text "PROBE_START"
display as text "subject=`subject_label'"
display as text "stata_version=`c(stata_version)'"
display as text "ster_file=`ster_file'"

confirm file "`ster_file'"
estimates use "`ster_file'"

display as text "ESTIMATES_DESCRIBE_START"
estimates describe
display as text "ESTIMATES_DESCRIBE_END"

display as text "ERETURN_LIST_START"
ereturn list
display as text "ERETURN_LIST_END"

capture confirm matrix e(item_par)
local has_item_par = (_rc == 0)
display as text "has_item_par=`has_item_par'"

if `has_item_par' {
    display as text "ITEM_PAR_DIMENSIONS_START"
    display as result "rows=" rowsof(e(item_par)) " cols=" colsof(e(item_par))
    display as text "ITEM_PAR_DIMENSIONS_END"

    tempname item_par item_se item_n
    matrix `item_par' = e(item_par)
    matrix `item_se' = e(item_par_se)
    matrix `item_n' = e(item_group_N)
    local item_equations : roweq `item_par'
    local item_rows : rownames `item_par'
    local n_item_rows = rowsof(`item_par')
    matrix colnames `item_par' = a b
    matrix colnames `item_se' = se_a se_b
    matrix colnames `item_n' = n_model

    preserve
        clear
        svmat double `item_par', names(col)
        svmat double `item_se', names(col)
        svmat double `item_n', names(col)
        generate str64 item_id = ""
        generate str20 model_type = ""
        forvalues index = 1/`n_item_rows' {
            local item_equation : word `index' of `item_equations'
            local item_name : word `index' of `item_rows'
            replace item_id = "`item_equation'" in `index'
            replace model_type = "`item_name'" in `index'
        }
        generate str12 subject = "`subject_label'"
        generate byte fixed_in_combined_model = (se_a == 0 & se_b == 0)
        order subject item_id model_type a b se_a se_b fixed_in_combined_model n_model
        export delimited using "`output_params'", replace
    restore
}

capture confirm matrix e(group_par)
local has_group_par = (_rc == 0)
if `has_group_par' {
    tempname group_par group_se group_n
    matrix `group_par' = e(group_par)
    matrix `group_se' = e(group_par_se)
    matrix `group_n' = e(group_N)
    local group_rows : rownames `group_par'
    local n_group_rows = rowsof(`group_par')
    matrix colnames `group_par' = value
    matrix colnames `group_se' = standard_error

    preserve
        clear
        svmat double `group_par', names(col)
        svmat double `group_se', names(col)
        generate str40 parameter = ""
        forvalues index = 1/`n_group_rows' {
            local parameter_name : word `index' of `group_rows'
            replace parameter = "`parameter_name'" in `index'
        }
        generate str12 subject = "`subject_label'"
        generate double n_model = `group_n'[1,1]
        order subject parameter value standard_error n_model
        export delimited using "`output_group'", replace
    restore
}

capture local cmdline `"`e(cmdline)'"'
capture local model_cmd `"`e(cmd)'"'
capture local item_names `"`e(items)'"'
capture local model_N = e(N)
capture local model_items = e(N_items)
capture local model_groups = e(N_gr)
capture local model_ll = e(ll)

file open summary using "`output_summary'", write replace text
file write summary "probe_status=complete" _n
file write summary "subject=`subject_label'" _n
file write summary "stata_version=`c(stata_version)'" _n
file write summary "model_command=`model_cmd'" _n
file write summary "estimation_command=`cmdline'" _n
file write summary "n_observations=`model_N'" _n
file write summary "n_items=`model_items'" _n
file write summary "n_groups=`model_groups'" _n
file write summary "log_likelihood=`model_ll'" _n
file write summary "has_item_par=`has_item_par'" _n
file write summary "has_group_par=`has_group_par'" _n
file write summary "item_names=`item_names'" _n
file close summary

display as text "PROBE_COMPLETE"
log close y1_ster_probe
exit, clear
