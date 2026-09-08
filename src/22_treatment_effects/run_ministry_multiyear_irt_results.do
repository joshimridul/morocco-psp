version 19.0
clear all
set more off
set varabbrev off
set seed 20260720

/*
  Re-estimate all Ministry headline, baseline-grade, and heterogeneity panels
  with fixed-Year-1-scale IRT outcomes. Inputs are analysis-ready copies below
  work_root; legacy source files are never written. Only aggregate estimates
  are exported.
*/

args work_root
if `"`work_root'"' == "" {
    di as error "Usage: do run_ministry_multiyear_irt_results.do <work_root>"
    exit 198
}

global panel_dir `"`work_root'/outputs/y1_y3_irt/07_ministry_multiyear_results/analysis_inputs"'
global out_dir   `"`work_root'/outputs/y1_y3_irt/07_ministry_multiyear_results"'
capture mkdir "$out_dir"
capture mkdir "$out_dir/logs"

capture log close _all
log using "$out_dir/logs/ministry_multiyear_irt_results.log", text replace

foreach command in reghdfe pdslasso unique {
    capture which `command'
    if _rc {
        di as error "Required command is unavailable: `command'"
        exit 199
    }
}

global methods "ministry_sum irt_chained_strict irt_pooled_strict_all irt_pooled_strict_control irt_grade_specific_strict irt_chained_provisional"
global subjects "overall arabic french math"
global pupil_c1 "female repeated tayssir grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global pupil_c2 "female grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global pupil_c3 "female grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global school_controls "n_teachers urban regional_dev total_enrolled7_sum perc_female perc_tayssir avg_score7_mu perc_ssbenef"

tempfile headline grade heterogeneity selected_controls
tempname post_head post_grade post_het post_sel
postfile `post_head' str32 score_method str1 panel byte exposure byte cohort byte pooled ///
    byte subject_order str8 subject double(b se p n_students n_schools n_pairs n_obs) ///
    using `headline', replace
postfile `post_grade' str32 score_method str1 panel byte exposure byte cohort byte pooled ///
    byte subject_order byte grade str8 subject ///
    double(b se p n_students n_schools n_pairs n_obs) using `grade', replace
postfile `post_het' str32 score_method str1 panel byte exposure byte cohort byte pooled ///
    byte subject_order byte group_order str8 subject str16 subgroup ///
    double(b se p n_students n_schools n_pairs n_obs) using `heterogeneity', replace
postfile `post_sel' str32 score_method str12 sample_scope str8 panel_id ///
    str8 subject str244 controls using `selected_controls', replace

capture program drop prepare_method
program define prepare_method
    syntax, METHOD(string) [POOLed]

    tempvar analysis_score n_score
    if "`method'" == "ministry_sum" generate double `analysis_score' = score
    else generate double `analysis_score' = `method'

    if "`pooled'" == "" {
        capture confirm numeric variable student_id
        if !_rc generate long student_est = student_id
        else encode student_id, generate(student_est)
    }
    else {
        egen long student_est = group(cohort_pool student_id)
    }

    bysort student_est: egen byte `n_score' = count(`analysis_score')
    keep if `n_score' == 2
    drop `n_score'
    isid student_est post
    xtset student_est post

    foreach variable in overall_score arabic_score french_score math_score score_baseline {
        capture drop `variable'
    }
    generate double overall_score = `analysis_score'
    generate double arabic_score = `analysis_score' if subject == 1
    generate double french_score = `analysis_score' if subject == 2
    generate double math_score = `analysis_score' if subject == 3
    bysort student_est: egen double score_baseline = max(cond(post == 0, `analysis_score', .))
    bysort student_est: egen byte grade_base = max(cond(post == 0, grade, .))
    generate byte post_treat = post * treated
end

capture program drop select_controls
program define select_controls, rclass
    syntax, OUTCOME(name) SUBJECT(string) PAIRvar(name) IDvar(name) ///
        GRADEvar(name) CONTROLS(string) [WEIGHTvar(name) REGRESSION]

    local subject_if
    if "`subject'" == "arabic" local subject_if "& subject == 1"
    if "`subject'" == "french" local subject_if "& subject == 2"
    if "`subject'" == "math"   local subject_if "& subject == 3"

    tempvar change control_mean residual
    sort `idvar' post
    by `idvar': generate double `change' = `outcome'[2] - `outcome'[1] if _n == 2
    if "`regression'" != "" {
        quietly regress `change' i.`gradevar'##i.`pairvar' if treated == 0, ///
            vce(cluster `pairvar')
        quietly predict double `residual', residuals
    }
    else {
        bysort `pairvar' `gradevar': egen double `control_mean' = ///
            mean(cond(treated == 0 & post == 1, `change', .))
        generate double `residual' = `change' - `control_mean'
    }

    local selected
    if strtrim("`controls'") != "" {
        if "`weightvar'" == "" {
            quietly pdslasso `residual' treated (`controls') ///
                if post == 1 & `outcome' < . `subject_if', cluster(`pairvar')
        }
        else {
            quietly pdslasso `residual' treated (`controls') ///
                if post == 1 & `outcome' < . `subject_if' [aw=`weightvar'], ///
                cluster(`pairvar')
        }
        local selected "`e(xselected)'"
    }
    return local selected "`selected'"
end

capture program drop post_counts
program define post_counts, rclass
    syntax, IDvar(name) SCHOOLvar(name) PAIRvar(name)
    tempvar tag_student tag_school tag_pair
    quietly egen byte `tag_student' = tag(`idvar') if e(sample)
    quietly count if `tag_student' == 1
    return scalar n_students = r(N)
    quietly egen byte `tag_school' = tag(`schoolvar') if e(sample)
    quietly count if `tag_school' == 1
    return scalar n_schools = r(N)
    quietly egen byte `tag_pair' = tag(`pairvar') if e(sample)
    quietly count if `tag_pair' == 1
    return scalar n_pairs = r(N)
    quietly count if e(sample)
    return scalar n_obs = r(N)
end

capture program drop estimate_single_panel
program define estimate_single_panel
    syntax, FILE(string) PANELID(string) COHORT(integer) PANEL(string) ///
        EXPOSURE(integer) METHOD(string) POSTHEAD(name) POSTGRADE(name) ///
        POSTHET(name) POSTSEL(name)

    use "$panel_dir/`file'", clear
    prepare_method, method("`method'")

    local controls
    foreach variable in ${pupil_c`cohort'} $school_controls {
        capture confirm numeric variable `variable'
        if !_rc local controls `controls' `variable'
    }

    local order = 0
    foreach sub of global subjects {
        local ++order
        local outcome "`sub'_score"
        local subject_if
        if "`sub'" == "arabic" local subject_if "& subject == 1"
        if "`sub'" == "french" local subject_if "& subject == 2"
        if "`sub'" == "math"   local subject_if "& subject == 3"

        quietly select_controls, outcome(`outcome') subject("`sub'") ///
            pairvar(pair_id) idvar(student_est) gradevar(grade) controls("`controls'") ///
            regression
        local selected "`r(selected)'"
        post `postsel' ("`method'") ("cohort") ("`panelid'") ("`sub'") ("`selected'")

        local selected_post
        foreach variable of local selected {
            capture confirm numeric variable `variable'
            if !_rc local selected_post `selected_post' c.`variable'#i.post
        }

        quietly reghdfe `outcome' i.post#i.grade#i.pair_id ///
            i.post#i.grade i.post#i.pair_id `selected_post' post post_treat ///
            if `outcome' < . `subject_if', absorb(student_est) vce(cluster pair_id)
        local b = _b[post_treat]
        local se = _se[post_treat]
        quietly test post_treat
        local p = r(p)
        quietly post_counts, idvar(student_est) schoolvar(cd_etab) pairvar(pair_id)
        post `posthead' ("`method'") ("`panel'") (`exposure') (`cohort') (0) ///
            (`order') ("`sub'") (`b') (`se') (`p') (r(n_students)) ///
            (r(n_schools)) (r(n_pairs)) (r(n_obs))

        quietly select_controls, outcome(`outcome') subject("`sub'") ///
            pairvar(pair_id) idvar(student_est) gradevar(grade_base) controls("`controls'")
        local selected_grade "`r(selected)'"
        local grade_panel_id "`panelid'g"
        post `postsel' ("`method'") ("cohortgrade") ("`grade_panel_id'") ("`sub'") ("`selected_grade'")
        local selected_grade_post
        foreach variable of local selected_grade {
            capture confirm numeric variable `variable'
            if !_rc local selected_grade_post `selected_grade_post' c.`variable'#i.post
        }

        local max_grade = 7 - `exposure'
        forvalues g = 1/`max_grade' {
            quietly count if grade_base == `g' & post == 0 & `outcome' < . `subject_if'
            local n0 = r(N)
            quietly count if grade_base == `g' & post == 1 & `outcome' < . `subject_if'
            local n1 = r(N)
            quietly summarize treated if grade_base == `g' & post == 1 & `outcome' < . `subject_if', meanonly
            local both = r(N) > 0 & r(min) < r(max)
            if `n0' == 0 | `n1' == 0 | !`both' {
                post `postgrade' ("`method'") ("`panel'") (`exposure') (`cohort') (0) ///
                    (`order') (`g') ("`sub'") (.) (.) (.) (.) (.) (.) (.)
            }
            else {
                capture quietly reghdfe `outcome' `selected_grade_post' post post_treat ///
                    if `outcome' < . `subject_if' & grade_base == `g', ///
                    absorb(student_est i.post#i.pair_id) vce(cluster pair_id)
                local model_ok = (_rc == 0)
                if `model_ok' {
                    capture local coefficient_check = _b[post_treat]
                    if _rc local model_ok = 0
                    else if missing(_se[post_treat]) | _se[post_treat] <= 0 local model_ok = 0
                }
                if !`model_ok' {
                    post `postgrade' ("`method'") ("`panel'") (`exposure') (`cohort') (0) ///
                        (`order') (`g') ("`sub'") (.) (.) (.) (.) (.) (.) (.)
                }
                else {
                    local bg = _b[post_treat]
                    local seg = _se[post_treat]
                    quietly test post_treat
                    local pg = r(p)
                    quietly post_counts, idvar(student_est) schoolvar(cd_etab) pairvar(pair_id)
                    post `postgrade' ("`method'") ("`panel'") (`exposure') (`cohort') (0) ///
                        (`order') (`g') ("`sub'") (`bg') (`seg') (`pg') ///
                        (r(n_students)) (r(n_schools)) (r(n_pairs)) (r(n_obs))
                }
            }
        }

        tempvar qbase hetero_q
        generate byte `qbase' = .
        replace `qbase' = 1 if bottom_`sub' == 1 & post == 0
        replace `qbase' = 4 if top_`sub' == 1 & post == 0
        bysort student_est: egen byte `hetero_q' = max(`qbase')

        foreach h in 1 2 3 5 {
            if `h' == 1 {
                local subgroup "Female"
                local group_if "female == 1"
            }
            if `h' == 2 {
                local subgroup "Male"
                local group_if "female == 0"
            }
            if `h' == 3 {
                local subgroup "Bottom"
                local group_if "`hetero_q' == 1"
            }
            if `h' == 5 {
                local subgroup "Top"
                local group_if "`hetero_q' == 4"
            }
            capture quietly reghdfe `outcome' `selected_post' post post_treat ///
                if `outcome' < . `subject_if' & (`group_if'), ///
                absorb(student_est i.post#i.grade#i.pair_id) vce(cluster pair_id)
            local model_ok = (_rc == 0)
            if `model_ok' {
                capture local coefficient_check = _b[post_treat]
                if _rc local model_ok = 0
            }
            if !`model_ok' {
                post `posthet' ("`method'") ("`panel'") (`exposure') (`cohort') (0) ///
                    (`order') (`h') ("`sub'") ("`subgroup'") ///
                    (.) (.) (.) (.) (.) (.) (.)
            }
            else {
                local bh = _b[post_treat]
                local seh = _se[post_treat]
                quietly test post_treat
                local ph = r(p)
                quietly post_counts, idvar(student_est) schoolvar(cd_etab) pairvar(pair_id)
                post `posthet' ("`method'") ("`panel'") (`exposure') (`cohort') (0) ///
                    (`order') (`h') ("`sub'") ("`subgroup'") ///
                    (`bh') (`seh') (`ph') (r(n_students)) (r(n_schools)) ///
                    (r(n_pairs)) (r(n_obs))
            }
        }
        drop `qbase' `hetero_q'
    }
end

capture program drop estimate_pooled_panel
program define estimate_pooled_panel
    syntax, PANEL(string) EXPOSURE(integer) FILES(string) COHORTS(numlist) ///
        METHOD(string) POSTHEAD(name) POSTGRADE(name) POSTHET(name) POSTSEL(name)

    local k = 0
    local poolfiles
    foreach file of local files {
        local ++k
        local cohort : word `k' of `cohorts'
        use "$panel_dir/`file'", clear
        generate byte cohort_pool = `cohort'
        tempfile pool`k'
        save `pool`k'', replace
        local poolfiles `poolfiles' `pool`k''
    }
    local first : word 1 of `poolfiles'
    use `first', clear
    local nfiles : word count `poolfiles'
    if `nfiles' > 1 {
        forvalues index = 2/`nfiles' {
            local next : word `index' of `poolfiles'
            append using `next'
        }
    }

    prepare_method, method("`method'") pooled
    egen long pair_pool = group(cohort_pool pair_id)
    bysort cohort_pool: egen long cohort_n = count(student_est)
    generate double cohort_weight = 1 / cohort_n

    local controls
    foreach variable in $pupil_c2 $school_controls {
        capture confirm numeric variable `variable'
        if !_rc local controls `controls' `variable'
    }

    local order = 0
    foreach sub of global subjects {
        local ++order
        local outcome "`sub'_score"
        local subject_if
        if "`sub'" == "arabic" local subject_if "& subject == 1"
        if "`sub'" == "french" local subject_if "& subject == 2"
        if "`sub'" == "math"   local subject_if "& subject == 3"

        quietly select_controls, outcome(`outcome') subject("`sub'") ///
            pairvar(pair_pool) idvar(student_est) gradevar(grade) controls("`controls'") ///
            weightvar(cohort_weight)
        local selected "`r(selected)'"
        local panel_id "pooled_e`exposure'"
        post `postsel' ("`method'") ("pooled") ("`panel_id'") ("`sub'") ("`selected'")

        local selected_post
        foreach variable of local selected {
            capture confirm numeric variable `variable'
            if !_rc local selected_post `selected_post' c.`variable'#i.post
        }

        quietly reghdfe `outcome' `selected_post' post post_treat ///
            if `outcome' < . `subject_if' [aw=cohort_weight], ///
            absorb(student_est i.post#i.grade#i.pair_pool) vce(cluster pair_pool)
        local b = _b[post_treat]
        local se = _se[post_treat]
        quietly test post_treat
        local p = r(p)
        tempvar school_pool
        egen long `school_pool' = group(cohort_pool cd_etab)
        quietly post_counts, idvar(student_est) schoolvar(`school_pool') pairvar(pair_pool)
        post `posthead' ("`method'") ("`panel'") (`exposure') (4) (1) ///
            (`order') ("`sub'") (`b') (`se') (`p') (r(n_students)) ///
            (r(n_schools)) (r(n_pairs)) (r(n_obs))

        quietly select_controls, outcome(`outcome') subject("`sub'") ///
            pairvar(pair_pool) idvar(student_est) gradevar(grade_base) ///
            controls("`controls'") weightvar(cohort_weight)
        local selected_grade "`r(selected)'"
        local grade_panel_id "pooled`exposure'g"
        post `postsel' ("`method'") ("pooledgrade") ("`grade_panel_id'") ("`sub'") ("`selected_grade'")
        local selected_grade_post
        foreach variable of local selected_grade {
            capture confirm numeric variable `variable'
            if !_rc local selected_grade_post `selected_grade_post' c.`variable'#i.post
        }

        local max_grade = 7 - `exposure'
        forvalues g = 1/`max_grade' {
            tempvar eligible n_grade grade_weight
            generate byte `eligible' = `outcome' < . & grade_base == `g'
            if "`sub'" == "arabic" replace `eligible' = `eligible' & subject == 1
            if "`sub'" == "french" replace `eligible' = `eligible' & subject == 2
            if "`sub'" == "math" replace `eligible' = `eligible' & subject == 3
            bysort cohort_pool: egen long `n_grade' = total(`eligible')
            generate double `grade_weight' = 1 / `n_grade' if `eligible'

            quietly summarize treated if `eligible' & post == 1, meanonly
            local both = r(N) > 0 & r(min) < r(max)
            if !`both' {
                post `postgrade' ("`method'") ("`panel'") (`exposure') (4) (1) ///
                    (`order') (`g') ("`sub'") (.) (.) (.) (.) (.) (.) (.)
            }
            else {
                capture quietly reghdfe `outcome' `selected_grade_post' post post_treat ///
                    if `eligible' [aw=`grade_weight'], ///
                    absorb(student_est i.post#i.pair_pool) vce(cluster pair_pool)
                local model_ok = (_rc == 0)
                if `model_ok' {
                    capture local coefficient_check = _b[post_treat]
                    if _rc local model_ok = 0
                    else if missing(_se[post_treat]) | _se[post_treat] <= 0 local model_ok = 0
                }
                if !`model_ok' {
                    post `postgrade' ("`method'") ("`panel'") (`exposure') (4) (1) ///
                        (`order') (`g') ("`sub'") (.) (.) (.) (.) (.) (.) (.)
                }
                else {
                    local bg = _b[post_treat]
                    local seg = _se[post_treat]
                    quietly test post_treat
                    local pg = r(p)
                    quietly post_counts, idvar(student_est) schoolvar(`school_pool') pairvar(pair_pool)
                    post `postgrade' ("`method'") ("`panel'") (`exposure') (4) (1) ///
                        (`order') (`g') ("`sub'") (`bg') (`seg') (`pg') ///
                        (r(n_students)) (r(n_schools)) (r(n_pairs)) (r(n_obs))
                }
            }
            drop `eligible' `n_grade' `grade_weight'
        }

        tempvar qbase hetero_q
        generate byte `qbase' = .
        replace `qbase' = 1 if bottom_`sub' == 1 & post == 0
        replace `qbase' = 4 if top_`sub' == 1 & post == 0
        bysort student_est: egen byte `hetero_q' = max(`qbase')
        foreach h in 1 2 3 5 {
            if `h' == 1 {
                local subgroup "Female"
                local group_if "female == 1"
            }
            if `h' == 2 {
                local subgroup "Male"
                local group_if "female == 0"
            }
            if `h' == 3 {
                local subgroup "Bottom"
                local group_if "`hetero_q' == 1"
            }
            if `h' == 5 {
                local subgroup "Top"
                local group_if "`hetero_q' == 4"
            }
            capture quietly reghdfe `outcome' `selected_post' post post_treat ///
                if `outcome' < . `subject_if' & (`group_if') [aw=cohort_weight], ///
                absorb(student_est i.post#i.grade#i.pair_pool) vce(cluster pair_pool)
            local model_ok = (_rc == 0)
            if `model_ok' {
                capture local coefficient_check = _b[post_treat]
                if _rc local model_ok = 0
            }
            if !`model_ok' {
                post `posthet' ("`method'") ("`panel'") (`exposure') (4) (1) ///
                    (`order') (`h') ("`sub'") ("`subgroup'") ///
                    (.) (.) (.) (.) (.) (.) (.)
            }
            else {
                local bh = _b[post_treat]
                local seh = _se[post_treat]
                quietly test post_treat
                local ph = r(p)
                quietly post_counts, idvar(student_est) schoolvar(`school_pool') pairvar(pair_pool)
                post `posthet' ("`method'") ("`panel'") (`exposure') (4) (1) ///
                    (`order') (`h') ("`sub'") ("`subgroup'") ///
                    (`bh') (`seh') (`ph') (r(n_students)) (r(n_schools)) ///
                    (r(n_pairs)) (r(n_obs))
            }
        }
        drop `qbase' `hetero_q'
    }
end

foreach method of global methods {
    di as text "Estimating score method: `method'"
    estimate_single_panel, file("c1e1_irt_panel.dta") panelid("c1e1") ///
        cohort(1) panel("A") exposure(1) method("`method'") ///
        posthead(`post_head') postgrade(`post_grade') posthet(`post_het') postsel(`post_sel')
    estimate_single_panel, file("c2e1_irt_panel.dta") panelid("c2e1") ///
        cohort(2) panel("A") exposure(1) method("`method'") ///
        posthead(`post_head') postgrade(`post_grade') posthet(`post_het') postsel(`post_sel')
    estimate_single_panel, file("c3e1_irt_panel.dta") panelid("c3e1") ///
        cohort(3) panel("A") exposure(1) method("`method'") ///
        posthead(`post_head') postgrade(`post_grade') posthet(`post_het') postsel(`post_sel')
    estimate_single_panel, file("c1e2_irt_panel.dta") panelid("c1e2") ///
        cohort(1) panel("B") exposure(2) method("`method'") ///
        posthead(`post_head') postgrade(`post_grade') posthet(`post_het') postsel(`post_sel')
    estimate_single_panel, file("c2e2_irt_panel.dta") panelid("c2e2") ///
        cohort(2) panel("B") exposure(2) method("`method'") ///
        posthead(`post_head') postgrade(`post_grade') posthet(`post_het') postsel(`post_sel')
    estimate_single_panel, file("c1e3_irt_panel.dta") panelid("c1e3") ///
        cohort(1) panel("C") exposure(3) method("`method'") ///
        posthead(`post_head') postgrade(`post_grade') posthet(`post_het') postsel(`post_sel')

    estimate_pooled_panel, panel("A") exposure(1) ///
        files("c1e1_irt_panel.dta c2e1_irt_panel.dta c3e1_irt_panel.dta") ///
        cohorts(1 2 3) method("`method'") posthead(`post_head') ///
        postgrade(`post_grade') posthet(`post_het') postsel(`post_sel')
    estimate_pooled_panel, panel("B") exposure(2) ///
        files("c1e2_irt_panel.dta c2e2_irt_panel.dta") ///
        cohorts(1 2) method("`method'") posthead(`post_head') ///
        postgrade(`post_grade') posthet(`post_het') postsel(`post_sel')
}

postclose `post_head'
postclose `post_grade'
postclose `post_het'
postclose `post_sel'

use `headline', clear
sort score_method panel cohort subject_order
export delimited using "$out_dir/ministry_headline_irt_estimates.csv", replace
save "$out_dir/ministry_headline_irt_estimates.dta", replace

use `grade', clear
sort score_method panel cohort grade subject_order
export delimited using "$out_dir/ministry_grade_irt_estimates.csv", replace
save "$out_dir/ministry_grade_irt_estimates.dta", replace

use `heterogeneity', clear
sort score_method panel group_order cohort subject_order
export delimited using "$out_dir/ministry_heterogeneity_irt_estimates.csv", replace
save "$out_dir/ministry_heterogeneity_irt_estimates.dta", replace

use `selected_controls', clear
sort score_method sample_scope panel_id subject
export delimited using "$out_dir/ministry_irt_selected_controls.csv", replace

di as result "MINISTRY MULTIYEAR IRT RESULTS COMPLETE"
log close
