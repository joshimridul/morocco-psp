version 19.0

/*
  Measurement-method robustness for the three headline exposure estimands.

  Every method is run through the same prespecified regression program. The
  one- and two-year results pool the available cohorts with equal total
  cohort weight; the three-year result is Cohort 1, the only cohort observed
  for three years. Each method uses its available balanced two-wave sample.
*/

tempfile robustness control_results
tempname pr pc
postfile `pr' str28 score_method str1 panel byte exposure cohort pooled ///
    subject_order str8 subject double(b se p n_students n_schools n_pairs n_obs) ///
    using `robustness', replace
postfile `pc' str28 score_method str12 table_family str12 panel_id ///
    str8 subject str244 controls using `control_results', replace

foreach method of global ROBUSTNESS_METHODS {
    di as text "Estimating measurement robustness method: `method'"
    psp_load_pool, files("c1e1_irt_panel.dta c2e1_irt_panel.dta c3e1_irt_panel.dta") ///
        cohorts(1 2 3) method("`method'")
    quietly psp_available_controls, cohort(2)
    psp_estimate_headline_loaded, method("`method'") panel("A") exposure(1) ///
        cohort(4) controls("`r(controls)'") posthandle(`pr') ///
        controlhandle(`pc') weight(cohort_weight) allowempty mincohorts(3)

    psp_load_pool, files("c1e2_irt_panel.dta c2e2_irt_panel.dta") ///
        cohorts(1 2) method("`method'")
    quietly psp_available_controls, cohort(2)
    psp_estimate_headline_loaded, method("`method'") panel("B") exposure(2) ///
        cohort(4) controls("`r(controls)'") posthandle(`pr') ///
        controlhandle(`pc') weight(cohort_weight) allowempty mincohorts(2)

    psp_load_panel, file("c1e3_irt_panel.dta") method("`method'")
    quietly psp_available_controls, cohort(1)
    psp_estimate_headline_loaded, method("`method'") panel("C") exposure(3) ///
        cohort(1) controls("`r(controls)'") posthandle(`pr') ///
        controlhandle(`pc') allowempty
}

postclose `pr'
postclose `pc'

use `robustness', clear
sort panel score_method subject_order
save "${EST}/measurement_robustness.dta", replace
export delimited using "${EST}/measurement_robustness.csv", replace

use `control_results', clear
sort score_method panel_id subject
save "${EST}/selected_controls_measurement_robustness.dta", replace
export delimited using "${EST}/selected_controls_measurement_robustness.csv", replace
