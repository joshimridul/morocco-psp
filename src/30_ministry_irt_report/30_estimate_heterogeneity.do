version 19.0

/* Gender and baseline-performance heterogeneity (Tables 3 and 4). */

tempfile heterogeneity control_results
tempname ph pc
postfile `ph' str16 score_method str1 panel byte exposure cohort pooled ///
    subject_order group_order str8 subject str16 subgroup ///
    double(b se p n_students n_schools n_pairs n_obs) using `heterogeneity', replace
postfile `pc' str16 score_method str12 table_family str12 panel_id ///
    str8 subject str244 controls using `control_results', replace

capture program drop psp_estimate_hetero_loaded
program define psp_estimate_hetero_loaded
    syntax, METHOD(string) PANEL(string) EXPOSURE(integer) COHORT(integer) ///
        CONTROLS(string) POSTHANDLE(name) CONTROLHANDLE(name) [WEIGHT(name)]

    local order = 0
    foreach subject of global SUBJECTS {
        local ++order
        local outcome "`subject'_score"
        psp_subject_restriction, subject("`subject'")
        local subject_if "`r(restriction)'"

        local selection_option
        if "`weight'" != "" {
            if "`method'" == "ministry_sum" {
                /* Exact historical benchmark: the delivered code selected
                   controls with the full-stacked-cohort weight. */
                local selection_option "weight(`weight') cellmean"
            }
            else {
                tempvar subject_eligible subject_cohort_n subject_weight
                generate byte `subject_eligible' = (`outcome' < .)
                if "`subject'" == "arabic" replace `subject_eligible' = `subject_eligible' & subject == 1
                if "`subject'" == "french" replace `subject_eligible' = `subject_eligible' & subject == 2
                if "`subject'" == "math"   replace `subject_eligible' = `subject_eligible' & subject == 3
                bysort cohort_pool: egen long `subject_cohort_n' = total(`subject_eligible')
                generate double `subject_weight' = 1 / `subject_cohort_n' if `subject_eligible' & `subject_cohort_n' > 0
                local selection_option "weight(`subject_weight') cellmean"
            }
        }
        quietly psp_select_controls, outcome(`outcome') subject("`subject'") ///
            controls("`controls'") gradevar(grade) `selection_option'
        local selected "`r(selected)'"
        post `controlhandle' ("`method'") ("heterogeneity") ///
            ("`panel'`cohort'") ("`subject'") ("`selected'")
        psp_post_interactions, controls("`selected'")
        local selected_post "`r(interactions)'"

        tempvar baseline_quartile quartile
        generate byte `baseline_quartile' = .
        replace `baseline_quartile' = 1 if bottom_`subject' == 1 & post == 0
        replace `baseline_quartile' = 4 if top_`subject' == 1 & post == 0
        bysort student_est: egen byte `quartile' = max(`baseline_quartile')

        foreach group in 1 2 3 5 {
            if `group' == 1 {
                local subgroup "Female"
                local group_if "female == 1"
            }
            if `group' == 2 {
                local subgroup "Male"
                local group_if "female == 0"
            }
            if `group' == 3 {
                local subgroup "Bottom"
                local group_if "`quartile' == 1"
            }
            if `group' == 5 {
                local subgroup "Top"
                local group_if "`quartile' == 4"
            }

            local regression_weight
            if "`weight'" != "" {
                if "`method'" == "ministry_sum" {
                    local regression_weight "[aw=`weight']"
                }
                else {
                    tempvar group_eligible group_cohort_n group_weight
                    generate byte `group_eligible' = (`outcome' < . & (`group_if'))
                    if "`subject'" == "arabic" replace `group_eligible' = `group_eligible' & subject == 1
                    if "`subject'" == "french" replace `group_eligible' = `group_eligible' & subject == 2
                    if "`subject'" == "math"   replace `group_eligible' = `group_eligible' & subject == 3
                    bysort cohort_pool: egen long `group_cohort_n' = total(`group_eligible')
                    generate double `group_weight' = 1 / `group_cohort_n' if `group_eligible' & `group_cohort_n' > 0
                    local regression_weight "[aw=`group_weight']"
                }
            }
            if "`method'" == "ministry_sum" {
                capture quietly reghdfe `outcome' `selected_post' post post_treat ///
                    if `outcome' < . `subject_if' & (`group_if') `regression_weight', ///
                    absorb(student_est i.post#i.grade#i.pair_est) ///
                    vce(cluster pair_est)
            }
            else {
                capture quietly reghdfe `outcome' i.post#i.grade#i.pair_est ///
                    i.post#i.grade i.post#i.pair_est `selected_post' post post_treat ///
                    if `outcome' < . `subject_if' & (`group_if') `regression_weight', ///
                    absorb(student_est) vce(cluster pair_est)
            }
            local estimable = (_rc == 0)
            if `estimable' {
                quietly psp_capture_effect
                local estimable = r(ok)
            }
            if `estimable' {
                post `posthandle' ("`method'") ("`panel'") (`exposure') (`cohort') ///
                    (`cohort' == 4) (`order') (`group') ("`subject'") ///
                    ("`subgroup'") (r(b)) (r(se)) (r(p)) (r(n_students)) ///
                    (r(n_schools)) (r(n_pairs)) (r(n_obs))
            }
            else {
                post `posthandle' ("`method'") ("`panel'") (`exposure') (`cohort') ///
                    (`cohort' == 4) (`order') (`group') ("`subject'") ///
                    ("`subgroup'") (.) (.) (.) (.) (.) (.) (.)
            }
        }
        drop `baseline_quartile' `quartile'
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
        psp_estimate_hetero_loaded, method("`method'") panel("`panel'") ///
            exposure(`exposure') cohort(`cohort') controls("`r(controls)'") ///
            posthandle(`ph') controlhandle(`pc')
    }

    psp_load_pool, files("c1e1_irt_panel.dta c2e1_irt_panel.dta c3e1_irt_panel.dta") ///
        cohorts(1 2 3) method("`method'")
    quietly psp_available_controls, cohort(2)
    psp_estimate_hetero_loaded, method("`method'") panel("A") ///
        exposure(1) cohort(4) controls("`r(controls)'") posthandle(`ph') ///
        controlhandle(`pc') weight(cohort_weight)

    psp_load_pool, files("c1e2_irt_panel.dta c2e2_irt_panel.dta") ///
        cohorts(1 2) method("`method'")
    quietly psp_available_controls, cohort(2)
    psp_estimate_hetero_loaded, method("`method'") panel("B") ///
        exposure(2) cohort(4) controls("`r(controls)'") posthandle(`ph') ///
        controlhandle(`pc') weight(cohort_weight)
}

postclose `ph'
postclose `pc'

use `heterogeneity', clear
sort score_method panel group_order cohort subject_order
save "${EST}/heterogeneity.dta", replace
export delimited using "${EST}/heterogeneity.csv", replace

use `control_results', clear
sort score_method panel_id subject
save "${EST}/selected_controls_heterogeneity.dta", replace
export delimited using "${EST}/selected_controls_heterogeneity.csv", replace
