version 19.0

/* Fail fast on structural defects before the report is compiled. */

use "${EST}/headline.dta", clear
isid score_method panel cohort subject_order
assert _N == 64
assert !missing(b, se, p, n_students, n_schools)
assert se > 0 & inrange(p, 0, 1)

use "${EST}/stable.dta", clear
isid score_method cohort exposure subject_order
assert _N == 40
assert !missing(b, se, p, n_students, n_schools)
assert se > 0 & inrange(p, 0, 1)

use "${EST}/heterogeneity.dta", clear
isid score_method panel cohort subject_order group_order
assert _N == 256
assert !missing(b, se, p, n_students, n_schools)
assert se > 0 & inrange(p, 0, 1)

use "${EST}/grade.dta", clear
isid score_method panel cohort grade subject_order
assert _N == 344
assert !missing(p_by) if !missing(p)
assert inrange(p_by, p, 1) if !missing(p)
assert se > 0 if !missing(b)

use "${EST}/measurement_robustness.dta", clear
isid score_method panel exposure cohort subject_order
assert _N == 216
assert se > 0 & inrange(p, 0, 1) & n_pairs >= 2 if !missing(b)
assert missing(se, p, n_students, n_schools, n_pairs, n_obs) if missing(b)
bysort score_method: assert _N == 12
egen byte method_tag = tag(score_method)
quietly count if method_tag
assert r(N) == 18
drop method_tag

/* The primary and sum-score rows must reproduce their main-table cells. */
keep if inlist(score_method, "primary_irt", "ministry_sum")
rename (b se p n_students n_schools n_pairs n_obs) ///
       (b_robust se_robust p_robust n_students_robust n_schools_robust n_pairs_robust n_obs_robust)
tempfile robustness_reference
save `robustness_reference'

use "${EST}/headline.dta", clear
keep if (panel == "A" & cohort == 4) | ///
        (panel == "B" & cohort == 4) | ///
        (panel == "C" & cohort == 1)
merge 1:1 score_method panel exposure cohort subject_order using `robustness_reference'
assert _merge == 3
assert abs(b - b_robust) < 1e-10
assert abs(se - se_robust) < 1e-10
assert abs(p - p_robust) < 1e-10
assert n_students == n_students_robust
assert n_schools == n_schools_robust
assert n_pairs == n_pairs_robust
assert n_obs == n_obs_robust

foreach table in 01_headline 02_stable 03_gender 04_baseline ///
                     05_grade_1year 06_grade_2year 07_grade_3year ///
                     08_measurement_robustness 09_measurement_sample_retention ///
                     10_math_link_diagnostics 11_primary_irt_diagnostics {
    confirm file "${TABLES}/`table'.tex"
}
confirm file "${CODE}/report/irt_technical_appendix.tex"

capture erase "${QA}/adversarial_review_summary.json"
local qa_marker "/tmp/morocco_psp_regression_qa_passed.txt"
capture erase "`qa_marker'"
shell "/usr/local/bin/Rscript" "${CODE}/qa/adversarial_review.R" ///
    "${REPO}/config/paths.local.yml" "${OUT}" "`qa_marker'"
confirm file "${QA}/adversarial_review_summary.json"
confirm file "`qa_marker'"
