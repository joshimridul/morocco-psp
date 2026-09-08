version 19.0

/* Grade-specific effects; grade is the student's baseline grade. */

tempfile grade control_results
tempname pg pc
postfile `pg' str16 score_method str1 panel byte exposure cohort pooled ///
    subject_order grade str8 subject double(b se p n_students n_schools n_pairs n_obs) ///
    using `grade', replace
postfile `pc' str16 score_method str12 table_family str12 panel_id ///
    str8 subject str244 controls using `control_results', replace

capture program drop psp_estimate_grade_loaded
program define psp_estimate_grade_loaded
    syntax, METHOD(string) PANEL(string) EXPOSURE(integer) COHORT(integer) ///
        CONTROLS(string) POSTHANDLE(name) CONTROLHANDLE(name) [WEIGHT(name)]

    local order = 0
    foreach subject of global SUBJECTS {
        local ++order
        local outcome "`subject'_score"
        psp_subject_restriction, subject("`subject'")
        local subject_if "`r(restriction)'"

        local selection_weight
        if "`weight'" != "" {
            tempvar subject_eligible subject_cohort_n subject_weight
            generate byte `subject_eligible' = (`outcome' < .)
            if "`subject'" == "arabic" replace `subject_eligible' = `subject_eligible' & subject == 1
            if "`subject'" == "french" replace `subject_eligible' = `subject_eligible' & subject == 2
            if "`subject'" == "math"   replace `subject_eligible' = `subject_eligible' & subject == 3
            bysort cohort_pool: egen long `subject_cohort_n' = total(`subject_eligible')
            generate double `subject_weight' = 1 / `subject_cohort_n' if `subject_eligible' & `subject_cohort_n' > 0
            local selection_weight "weight(`subject_weight')"
        }
        quietly psp_select_controls, outcome(`outcome') subject("`subject'") ///
            controls("`controls'") gradevar(grade_base) cellmean `selection_weight'
        local selected "`r(selected)'"
        post `controlhandle' ("`method'") ("grade") ("`panel'`cohort'") ///
            ("`subject'") ("`selected'")
        psp_post_interactions, controls("`selected'")
        local selected_post "`r(interactions)'"

        local max_grade = 7 - `exposure'
        forvalues grade = 1/`max_grade' {
            local regression_weight
            tempvar eligible cohort_grade_n grade_weight
            generate byte `eligible' = (`outcome' < . & grade_base == `grade')
            if "`subject'" == "arabic" replace `eligible' = `eligible' & subject == 1
            if "`subject'" == "french" replace `eligible' = `eligible' & subject == 2
            if "`subject'" == "math"   replace `eligible' = `eligible' & subject == 3

            if "`weight'" != "" {
                bysort cohort_pool: egen long `cohort_grade_n' = total(`eligible')
                generate double `grade_weight' = 1 / `cohort_grade_n' if `eligible'
                local regression_weight "[aw=`grade_weight']"
            }

            quietly summarize treated if `eligible' & post == 1, meanonly
            local estimable = r(N) > 0 & r(min) < r(max)
            if `estimable' {
                if "`method'" == "ministry_sum" {
                    /* Preserve the historical absorb() parameterization for
                       the exact Ministry sum-score benchmark. */
                    capture quietly reghdfe `outcome' `selected_post' post post_treat ///
                        if `eligible' `regression_weight', ///
                        absorb(student_est i.post#i.pair_est) ///
                        vce(cluster pair_est)
                }
                else {
                    capture quietly reghdfe `outcome' i.post#i.pair_est ///
                        i.post `selected_post' post_treat ///
                        if `eligible' `regression_weight', ///
                        absorb(student_est) vce(cluster pair_est)
                }
                local estimable = (_rc == 0)
                if `estimable' {
                    quietly psp_capture_effect
                    local estimable = r(ok)
                }
            }

            if `estimable' {
                post `posthandle' ("`method'") ("`panel'") (`exposure') (`cohort') ///
                    (`cohort' == 4) (`order') (`grade') ("`subject'") ///
                    (r(b)) (r(se)) (r(p)) (r(n_students)) (r(n_schools)) ///
                    (r(n_pairs)) (r(n_obs))
            }
            else {
                post `posthandle' ("`method'") ("`panel'") (`exposure') (`cohort') ///
                    (`cohort' == 4) (`order') (`grade') ("`subject'") ///
                    (.) (.) (.) (.) (.) (.) (.)
            }
            drop `eligible'
            capture drop `cohort_grade_n' `grade_weight'
        }
    }
end

foreach method of global METHODS {
    foreach spec in "c1e1 1 A 1" "c2e1 2 A 1" "c3e1 3 A 1" ///
                        "c1e2 1 B 2" "c2e2 2 B 2" "c1e3 1 C 3" {
        tokenize `"`spec'"'
        local panel_id "`1'"
        local cohort = `2'
        local panel "`3'"
        local exposure = `4'
        psp_load_panel, file("`panel_id'_irt_panel.dta") method("`method'")
        quietly psp_available_controls, cohort(`cohort')
        psp_estimate_grade_loaded, method("`method'") panel("`panel'") ///
            exposure(`exposure') cohort(`cohort') controls("`r(controls)'") ///
            posthandle(`pg') controlhandle(`pc')
    }

    psp_load_pool, files("c1e1_irt_panel.dta c2e1_irt_panel.dta c3e1_irt_panel.dta") ///
        cohorts(1 2 3) method("`method'")
    quietly psp_available_controls, cohort(2)
    psp_estimate_grade_loaded, method("`method'") panel("A") exposure(1) ///
        cohort(4) controls("`r(controls)'") posthandle(`pg') ///
        controlhandle(`pc') weight(cohort_weight)

    psp_load_pool, files("c1e2_irt_panel.dta c2e2_irt_panel.dta") ///
        cohorts(1 2) method("`method'")
    quietly psp_available_controls, cohort(2)
    psp_estimate_grade_loaded, method("`method'") panel("B") exposure(2) ///
        cohort(4) controls("`r(controls)'") posthandle(`pg') ///
        controlhandle(`pc') weight(cohort_weight)
}

postclose `pg'
postclose `pc'

use `grade', clear
preserve
    keep if !missing(p)
    sort score_method panel cohort p
    by score_method panel cohort: generate int p_rank = _n
    by score_method panel cohort: generate int family_m = _N
    generate double harmonic_piece = 1 / p_rank
    by score_method panel cohort: egen double harmonic_m = total(harmonic_piece)
    generate double p_by_raw = p * family_m * harmonic_m / p_rank
    gsort score_method panel cohort -p_rank
    by score_method panel cohort: generate double p_by = p_by_raw if _n == 1
    by score_method panel cohort: replace p_by = min(p_by_raw, p_by[_n-1]) if _n > 1
    replace p_by = min(p_by, 1)
    keep score_method panel cohort grade subject_order p_by
    tempfile adjusted
    save `adjusted', replace
restore
merge 1:1 score_method panel cohort grade subject_order using `adjusted', assert(1 3) nogen
sort score_method panel cohort grade subject_order
order score_method panel exposure cohort pooled grade subject_order subject ///
    b se p p_by n_students n_schools n_pairs n_obs
save "${EST}/grade.dta", replace
export delimited using "${EST}/grade.csv", replace

use `control_results', clear
sort score_method panel_id subject
save "${EST}/selected_controls_grade.dta", replace
export delimited using "${EST}/selected_controls_grade.csv", replace
