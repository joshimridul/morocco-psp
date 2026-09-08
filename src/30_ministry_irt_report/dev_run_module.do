version 19.0
clear all
set more off
set varabbrev off
set seed 20260720

/* Developer utility for rerunning one module after a failed full build. */
args repo_root module methods
if `"`methods'"' == "" local methods "primary_irt"
global REPO `"`repo_root'"'
shell "/usr/local/bin/Rscript" ///
    "${REPO}/src/30_ministry_irt_report/config_to_stata.R" ///
    "${REPO}/config/paths.local.yml" "/tmp/morocco_psp_irt_paths.do"
do "/tmp/morocco_psp_irt_paths.do"
global CODE "${REPO}/src/30_ministry_irt_report"
global PANEL_DIR "${WORK}/outputs/y1_y3_irt/07_ministry_multiyear_results/analysis_inputs"
/* Development reruns are quarantined from the release directory. */
global OUT "${WORK}/outputs/y1_y3_irt/08_ministry_irt_report/dev"
global EST "${OUT}/estimates"
global TABLES "${OUT}/tables"
global LOGS "${OUT}/logs"
global QA "${OUT}/qa"
capture mkdir "${OUT}"
capture mkdir "${EST}"
capture mkdir "${TABLES}"
capture mkdir "${LOGS}"
capture mkdir "${QA}"
global METHODS "`methods'"
global ROBUSTNESS_METHODS "primary_irt primary_wle subject_final_control grade_final_all grade_final_control pooled_strict_all pooled_strict_control grade_specific_strict grade_strict_control chained_strict direct_strict pooled_andy_core pooled_broad dev_schools_final chained_provisional direct_provisional ministry_sum_same_sample ministry_sum"
global SUBJECTS "overall arabic french math"
global PUPIL_C1 "female repeated tayssir grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global PUPIL_C2 "female grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global PUPIL_C3 "female grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global SCHOOL_CONTROLS "n_teachers urban regional_dev total_enrolled7_sum perc_female perc_tayssir avg_score7_mu perc_ssbenef"
capture log close _all
log using "${LOGS}/dev_`module'.log", text replace
do "${CODE}/lib/analysis_programs.do"
do "${CODE}/`module'.do"
log close
