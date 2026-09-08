version 19.0
clear all
set more off
set varabbrev off
set seed 20260720

/*
  One-click entry point.

  Usage:
    stata-mp -b do 00_master.do <repo_root> [compile_pdf] [reuse_estimates]

  The script refreshes the read-only-source analysis panels, estimates both
  the preferred release-candidate IRT outcome and the previously reported standardized
  sum score, writes aggregate LaTeX tables from Stata, and runs regression QA.
*/

args repo_root compile_pdf reuse_estimates
if `"`repo_root'"' == "" {
    di as error "Usage: do 00_master.do <repo_root> [compile_pdf] [reuse_estimates]"
    exit 198
}

global REPO `"`repo_root'"'
local stata_paths "/tmp/morocco_psp_irt_paths.do"
capture erase "`stata_paths'"
shell "/usr/local/bin/Rscript" ///
    "${REPO}/src/30_ministry_irt_report/config_to_stata.R" ///
    "${REPO}/config/paths.local.yml" "`stata_paths'"
confirm file "`stata_paths'"
do "`stata_paths'"
global CODE "${REPO}/src/30_ministry_irt_report"
global PANEL_DIR "${WORK}/outputs/y1_y3_irt/07_ministry_multiyear_results/analysis_inputs"
global OUT "${WORK}/outputs/y1_y3_irt/08_ministry_irt_report"
global EST "${OUT}/estimates"
global TABLES "${OUT}/tables"
global LOGS "${OUT}/logs"
global QA "${OUT}/qa"
if `"`compile_pdf'"' == "" local compile_pdf 1
if `"`reuse_estimates'"' == "" local reuse_estimates 0

capture mkdir "${OUT}"
capture mkdir "${EST}"
capture mkdir "${TABLES}"
capture mkdir "${LOGS}"
capture mkdir "${QA}"

local run_date = subinstr("`c(current_date)'", " ", "", .)
local run_time = subinstr("`c(current_time)'", ":", "", .)
local run_stamp "`run_date'T`run_time'"
local master_log "${LOGS}/00_master_`run_stamp'.log"
capture log close _all
log using "`master_log'", text replace name(master)

global METHODS "primary_irt ministry_sum"
global ROBUSTNESS_METHODS "primary_irt primary_wle subject_final_control grade_final_all grade_final_control pooled_strict_all pooled_strict_control grade_specific_strict grade_strict_control chained_strict direct_strict pooled_andy_core pooled_broad dev_schools_final chained_provisional direct_provisional ministry_sum_same_sample ministry_sum"
global SUBJECTS "overall arabic french math"
global PUPIL_C1 "female repeated tayssir grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global PUPIL_C2 "female grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global PUPIL_C3 "female grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global SCHOOL_CONTROLS "n_teachers urban regional_dev total_enrolled7_sum perc_female perc_tayssir avg_score7_mu perc_ssbenef"

do "${CODE}/lib/analysis_programs.do"
psp_require reghdfe pdslasso

/* Every build, including a layout-only rebuild, must pass the measurement gate. */
local lineage_marker "/tmp/morocco_psp_measurement_release_verified.txt"
capture erase "`lineage_marker'"
shell "/usr/local/bin/Rscript" ///
    "${CODE}/verify_measurement_release.R" "${REPO}" ///
    "${REPO}/config/paths.local.yml" "`lineage_marker'"
confirm file "`lineage_marker'"

if `reuse_estimates' == 0 {
    di as text "Refreshing analysis panels with the preferred release-candidate IRT score"
    local panel_marker "/tmp/morocco_psp_irt_panels_ready.txt"
    capture erase "`panel_marker'"
    shell "/usr/local/bin/Rscript" "${REPO}/src/22_treatment_effects/prepare_ministry_multiyear_irt_panels.R" "${REPO}/config/paths.local.yml" "`panel_marker'"
    confirm file "`panel_marker'"
    confirm file "${PANEL_DIR}/c1e1_irt_panel.dta"
    use "${PANEL_DIR}/c1e1_irt_panel.dta", clear
    confirm numeric variable irt_primary

    do "${CODE}/10_estimate_headline_stable.do"
    do "${CODE}/15_estimate_measurement_robustness.do"
    do "${CODE}/20_estimate_grade.do"
    do "${CODE}/30_estimate_heterogeneity.do"
}
else {
    foreach result in headline stable measurement_robustness grade heterogeneity {
        confirm file "${EST}/`result'.dta"
    }
}
do "${CODE}/40_export_latex.do"
do "${CODE}/90_validate_outputs.do"

if `compile_pdf' == 1 {
    copy "${CODE}/report/ministry_irt_report.tex" ///
        "${OUT}/ministry_irt_report.tex", replace
    copy "${CODE}/report/irt_technical_appendix.tex" ///
        "${OUT}/irt_technical_appendix.tex", replace
    capture erase "${OUT}/ministry_irt_report.pdf"
    shell "/Library/TeX/texbin/latexmk" -cd -pdf -interaction=nonstopmode ///
        -halt-on-error -output-directory="${OUT}" "${OUT}/ministry_irt_report.tex"
    confirm file "${OUT}/ministry_irt_report.pdf"
}

di as result "MINISTRY IRT REGRESSION PIPELINE COMPLETE"
log close master
copy "`master_log'" "${LOGS}/00_master.log", replace
