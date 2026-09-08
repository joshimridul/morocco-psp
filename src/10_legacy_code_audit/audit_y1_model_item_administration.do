version 19.5
clear all
set more off

local data_file : environment MOROCCO_Y1_ADMIN_DATA
local item_file : environment MOROCCO_Y1_ADMIN_ITEMS
local output_csv : environment MOROCCO_Y1_ADMIN_OUTPUT
local output_log : environment MOROCCO_Y1_ADMIN_LOG
local output_summary : environment MOROCCO_Y1_ADMIN_SUMMARY

if `"`data_file'"' == "" | `"`item_file'"' == "" | ///
    `"`output_csv'"' == "" | `"`output_log'"' == "" | ///
    `"`output_summary'"' == "" {
    display as error "Required MOROCCO_Y1_ADMIN_* environment variable is missing."
    exit 198
}

capture log close _all
log using "`output_log'", replace text name(y1_admin)
display as text "ADMIN_AUDIT_START"

confirm file "`data_file'"
confirm file "`item_file'"
use "`data_file'", clear
confirm numeric variable baseline
confirm numeric variable grade

tempname posted item_handle summary_handle
tempfile administration
postfile `posted' str40 analytic_item_id byte baseline double grade ///
    long n_students long n_nonmissing long n_zero long n_one long n_other ///
    double administration_rate using `administration', replace

local item_count 0
local missing_variable_count 0
local positive_cell_count 0
file open `item_handle' using "`item_file'", read text
file read `item_handle' item_id
while r(eof) == 0 {
    local item_id = strtrim(`"`item_id'"')
    if `"`item_id'"' != "" {
        local ++item_count
        capture confirm numeric variable `item_id'
        if _rc {
            local ++missing_variable_count
        }
        else {
            quietly levelsof baseline, local(waves)
            foreach wave of local waves {
                quietly levelsof grade if baseline == `wave', local(grades)
                foreach administered_grade of local grades {
                    quietly count if baseline == `wave' & grade == `administered_grade'
                    local n_students = r(N)
                    quietly count if baseline == `wave' & grade == `administered_grade' & `item_id' < .
                    local n_nonmissing = r(N)
                    if `n_nonmissing' > 0 {
                        quietly count if baseline == `wave' & grade == `administered_grade' & `item_id' == 0
                        local n_zero = r(N)
                        quietly count if baseline == `wave' & grade == `administered_grade' & `item_id' == 1
                        local n_one = r(N)
                        quietly count if baseline == `wave' & grade == `administered_grade' & ///
                            `item_id' < . & !inlist(`item_id', 0, 1)
                        local n_other = r(N)
                        local administration_rate = `n_nonmissing' / `n_students'
                        post `posted' (`"`item_id'"') (`wave') (`administered_grade') ///
                            (`n_students') (`n_nonmissing') (`n_zero') (`n_one') (`n_other') ///
                            (`administration_rate')
                        local ++positive_cell_count
                    }
                }
            }
        }
    }
    file read `item_handle' item_id
}
file close `item_handle'
postclose `posted'

use `administration', clear
sort analytic_item_id baseline grade
export delimited using "`output_csv'", replace

file open `summary_handle' using "`output_summary'", write replace text
file write `summary_handle' "verification_status=complete" _n
file write `summary_handle' "stata_version=`c(stata_version)'" _n
file write `summary_handle' "item_count=`item_count'" _n
file write `summary_handle' "missing_variable_count=`missing_variable_count'" _n
file write `summary_handle' "positive_administration_cells=`positive_cell_count'" _n
file close `summary_handle'

if `missing_variable_count' > 0 {
    display as error "Stored-model items absent from scoring data: `missing_variable_count'"
    exit 111
}

display as text "ADMIN_AUDIT_COMPLETE"
log close y1_admin
exit, clear
