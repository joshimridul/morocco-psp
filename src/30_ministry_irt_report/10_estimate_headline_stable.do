version 19.0

/* Headline Table 1 and the cohort-stable Table 2. */

tempfile headline stable control_results
tempname ph ps pc
postfile `ph' str16 score_method str1 panel byte exposure cohort pooled ///
    subject_order str8 subject double(b se p n_students n_schools n_pairs n_obs) ///
    using `headline', replace
postfile `ps' str16 score_method byte cohort exposure subject_order ///
    str8 subject double(b se p n_students n_schools n_pairs n_obs) ///
    using `stable', replace
postfile `pc' str16 score_method str12 table_family str12 panel_id ///
    str8 subject str244 controls using `control_results', replace

capture program drop psp_estimate_stable_loaded
program define psp_estimate_stable_loaded
    syntax, METHOD(string) COHORT(integer) EXPOSURE(integer) ///
        CONTROLS(string) POSTHANDLE(name) CONTROLHANDLE(name)
    local order = 0
    foreach subject of global SUBJECTS {
        local ++order
        local outcome "`subject'_score"
        psp_subject_restriction, subject("`subject'")
        local subject_if "`r(restriction)'"
        quietly psp_select_controls, outcome(`outcome') subject("`subject'") ///
            controls("`controls'") gradevar(grade)
        local selected "`r(selected)'"
        post `controlhandle' ("`method'") ("stable") ///
            ("c`cohort'e`exposure'") ("`subject'") ("`selected'")
        psp_post_interactions, controls("`selected'")
        local selected_post "`r(interactions)'"
        quietly reghdfe `outcome' i.post#i.grade#i.pair_est ///
            i.post#i.grade i.post#i.pair_est `selected_post' post post_treat ///
            if `outcome' < . `subject_if', absorb(student_est) vce(cluster pair_est)
        quietly psp_capture_effect
        assert r(ok) == 1
        post `posthandle' ("`method'") (`cohort') (`exposure') (`order') ///
            ("`subject'") (r(b)) (r(se)) (r(p)) (r(n_students)) ///
            (r(n_schools)) (r(n_pairs)) (r(n_obs))
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
        local controls "`r(controls)'"
        psp_estimate_headline_loaded, method("`method'") panel("`panel'") ///
            exposure(`exposure') cohort(`cohort') controls("`controls'") ///
            posthandle(`ph') controlhandle(`pc')
    }

    psp_load_pool, files("c1e1_irt_panel.dta c2e1_irt_panel.dta c3e1_irt_panel.dta") ///
        cohorts(1 2 3) method("`method'")
    quietly psp_available_controls, cohort(2)
    psp_estimate_headline_loaded, method("`method'") panel("A") exposure(1) ///
        cohort(4) controls("`r(controls)'") posthandle(`ph') ///
        controlhandle(`pc') weight(cohort_weight)

    psp_load_pool, files("c1e2_irt_panel.dta c2e2_irt_panel.dta") ///
        cohorts(1 2) method("`method'")
    quietly psp_available_controls, cohort(2)
    psp_estimate_headline_loaded, method("`method'") panel("B") exposure(2) ///
        cohort(4) controls("`r(controls)'") posthandle(`ph') ///
        controlhandle(`pc') weight(cohort_weight)

    foreach spec in "c1e1 1 1" "c1e2 1 2" "c1e3 1 3" ///
                        "c2e1 2 1" "c2e2 2 2" {
        tokenize `"`spec'"'
        local panel_id "`1'"
        local cohort = `2'
        local exposure = `3'
        psp_load_panel, file("`panel_id'_irt_panel.dta") method("`method'") stable
        quietly psp_available_controls, cohort(`cohort')
        psp_estimate_stable_loaded, method("`method'") cohort(`cohort') ///
            exposure(`exposure') controls("`r(controls)'") ///
            posthandle(`ps') controlhandle(`pc')
    }
}

postclose `ph'
postclose `ps'
postclose `pc'

use `headline', clear
sort score_method panel cohort subject_order
save "${EST}/headline.dta", replace
export delimited using "${EST}/headline.csv", replace

use `stable', clear
sort score_method cohort exposure subject_order
save "${EST}/stable.dta", replace
export delimited using "${EST}/stable.csv", replace

use `control_results', clear
sort score_method table_family panel_id subject
save "${EST}/selected_controls_headline_stable.dta", replace
export delimited using "${EST}/selected_controls_headline_stable.csv", replace
