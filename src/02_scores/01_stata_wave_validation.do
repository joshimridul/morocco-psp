version 19.5
clear all
set more off

args y3_root work_root
local y3_root : subinstr local y3_root "%20" " ", all
local work_root : subinstr local work_root "%20" " ", all
capture log close
log using "`work_root'/logs/y3_stata_wave_validation.log", text replace

local baseline "`y3_root'/4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta"
local pilot    "`y3_root'/4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta"
local endline  "`y3_root'/4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta"

foreach wave in baseline pilot endline {
    use "``wave''", clear
    quietly count
    local n = r(N)
    quietly describe
    local p = r(k)
    display as text "WAVE=`wave' N=`n' P=`p'"

    tempvar duplicate_tag
    quietly duplicates tag id_student_panel subject grade, generate(`duplicate_tag')
    quietly count if `duplicate_tag' > 0
    local duplicate_observations = r(N)
    quietly summarize `duplicate_tag', meanonly
    tempvar first_key
    quietly egen `first_key' = tag(id_student_panel subject grade)
    quietly count if `first_key' == 0
    local duplicate_rows_removed = r(N)
    display as text "DUPLICATE_OBSERVATIONS=`duplicate_observations' DUPLICATE_ROWS_REMOVED=`duplicate_rows_removed'"

    preserve
        contract subject grade
        sort subject grade
        list subject grade _freq, noobs clean abbreviate(20)
    restore

    quietly ds a* f* m*, has(type numeric)
    local candidate_vars `r(varlist)'
    local candidate_count : word count `candidate_vars'
    local nonbinary_count = 0
    foreach variable of local candidate_vars {
        quietly count if !missing(`variable') & !inlist(`variable', 0, 1)
        if r(N) > 0 local nonbinary_count = `nonbinary_count' + 1
    }
    display as text "NUMERIC_AFM_CANDIDATES=`candidate_count' VARIABLES_WITH_NONBINARY_VALUES=`nonbinary_count'"
}

log close
exit, clear
