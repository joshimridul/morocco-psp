version 19.0

/*
  Shared programs for the Ministry IRT regression pipeline.

  Design invariant:
    - two observations per student (baseline and selected follow-up);
    - student fixed effects;
    - treatment x post is the estimand;
    - matched-pair clustered standard errors;
    - matched-pair x baseline-grade trends;
    - double-selected baseline controls, interacted with post;
    - equal total cohort weight in pooled specifications.
*/

capture program drop psp_require
program define psp_require
    syntax anything(name=commands)
    foreach command of local commands {
        capture which `command'
        if _rc {
            di as error "Required Stata command is unavailable: `command'"
            exit 199
        }
    }
end

capture program drop psp_available_controls
program define psp_available_controls, rclass
    syntax, COHORT(integer)
    local candidates "${PUPIL_C`cohort'} $SCHOOL_CONTROLS"
    local available
    foreach variable of local candidates {
        capture confirm numeric variable `variable'
        if !_rc local available `available' `variable'
    }
    return local controls "`available'"
end

capture program drop psp_subject_restriction
program define psp_subject_restriction, rclass
    syntax, SUBJECT(string)
    local restriction
    if "`subject'" == "arabic" local restriction "& subject == 1"
    if "`subject'" == "french" local restriction "& subject == 2"
    if "`subject'" == "math"   local restriction "& subject == 3"
    return local restriction "`restriction'"
end

capture program drop psp_prepare_loaded_panel
program define psp_prepare_loaded_panel
    syntax, METHOD(string) [POOLED STABLE]

    if "`stable'" != "" keep if stable_sample == 1

    local score_variable
    if "`method'" == "primary_irt"            local score_variable "irt_primary"
    if "`method'" == "primary_wle"            local score_variable "irt_primary_wle"
    if "`method'" == "subject_final_control"  local score_variable "irt_subject_final_control"
    if "`method'" == "grade_final_all"        local score_variable "irt_grade_final_all"
    if "`method'" == "grade_final_control"    local score_variable "irt_grade_final_control"
    if "`method'" == "chained_strict"         local score_variable "irt_chained_strict"
    if "`method'" == "direct_strict"          local score_variable "irt_direct_strict"
    if "`method'" == "pooled_strict_all"      local score_variable "irt_pooled_strict_all"
    if "`method'" == "pooled_strict_control"  local score_variable "irt_pooled_strict_control"
    if "`method'" == "grade_specific_strict"  local score_variable "irt_grade_specific_strict"
    if "`method'" == "grade_strict_control"   local score_variable "irt_grade_strict_control"
    if "`method'" == "pooled_andy_core"       local score_variable "irt_pooled_andy_core"
    if "`method'" == "pooled_broad"           local score_variable "irt_pooled_broad"
    if "`method'" == "dev_schools_final"      local score_variable "irt_dev_schools_final"
    if "`method'" == "chained_provisional"    local score_variable "irt_chained_provisional"
    if "`method'" == "direct_provisional"     local score_variable "irt_direct_provisional"
    if "`method'" == "ministry_sum" {
        if "`stable'" == "" local score_variable "score"
        else local score_variable "score_ministry_stable"
    }
    if "`method'" == "ministry_sum_same_sample" local score_variable "score"
    if "`score_variable'" == "" {
        di as error "Unknown score method: `method'"
        exit 198
    }
    confirm numeric variable `score_variable'

    if "`pooled'" == "" {
        capture confirm numeric variable student_id
        if !_rc generate long student_est = student_id
        else encode student_id, generate(student_est)
        capture confirm numeric variable pair_id
        if !_rc generate long pair_est = pair_id
        else encode pair_id, generate(pair_est)
        capture confirm numeric variable cd_etab
        if !_rc generate long school_est = cd_etab
        else encode cd_etab, generate(school_est)
    }
    else {
        egen long student_est = group(cohort_pool student_id)
        egen long pair_est = group(cohort_pool pair_id)
        egen long school_est = group(cohort_pool cd_etab)
    }

    foreach variable in overall_score arabic_score french_score math_score ///
                        score_baseline grade_base post_treat {
        capture drop `variable'
    }

    tempvar observed_twice
    bysort student_est: egen byte `observed_twice' = count(`score_variable')
    quietly count if `observed_twice' == 2
    if r(N) == 0 {
        capture drop `observed_twice'
        generate double overall_score = .
        generate double arabic_score  = .
        generate double french_score  = .
        generate double math_score    = .
        generate double score_baseline = .
        generate byte grade_base = .
        generate byte post_treat = .
        exit
    }
    keep if `observed_twice' == 2
    capture drop `observed_twice'

    /* Same-sample benchmark: retain the standardized sum score only for
       students with a primary IRT score in both waves. */
    if "`method'" == "ministry_sum_same_sample" {
        tempvar irt_observed_twice
        bysort student_est: egen byte `irt_observed_twice' = count(irt_primary)
        keep if `irt_observed_twice' == 2
        capture drop `irt_observed_twice'
    }
    isid student_est post
    generate double overall_score = `score_variable'
    generate double arabic_score  = `score_variable' if subject == 1
    generate double french_score  = `score_variable' if subject == 2
    generate double math_score    = `score_variable' if subject == 3
    bysort student_est: egen double score_baseline = max(cond(post == 0, `score_variable', .))
    bysort student_est: egen byte grade_base = max(cond(post == 0, grade, .))
    generate byte post_treat = post * treated
    assert inlist(post, 0, 1)
    assert inlist(treated, 0, 1)
end

capture program drop psp_estimate_headline_loaded
program define psp_estimate_headline_loaded
    syntax, METHOD(string) PANEL(string) EXPOSURE(integer) COHORT(integer) ///
        CONTROLS(string) POSTHANDLE(name) CONTROLHANDLE(name) ///
        [WEIGHT(name) ALLOWEMPTY MINCOHORTS(integer -1)]

    local order = 0
    foreach subject of global SUBJECTS {
        local ++order
        local outcome "`subject'_score"
        psp_subject_restriction, subject("`subject'")
        local subject_if "`r(restriction)'"

        /* Equalize cohort weight within the outcome actually being estimated.
           Weighting the stacked file before restricting to a subject gives a
           cohort more influence merely because its subject mix differs. */
        local analysis_weight
        if "`weight'" != "" {
            /* The delivered Ministry benchmark used weights computed on the
               full stacked cohort before restricting to an outcome. Preserve
               that exact historical specification only for ministry_sum so
               the benchmark is reproducible. For IRT methods, recompute the
               weights in the actual scored outcome sample; otherwise missing
               links would inadvertently change a cohort's total influence. */
            if "`method'" == "ministry_sum" {
                local analysis_weight "`weight'"
            }
            else {
                tempvar subject_eligible subject_cohort_n subject_weight
                generate byte `subject_eligible' = (`outcome' < .)
                if "`subject'" == "arabic" replace `subject_eligible' = `subject_eligible' & subject == 1
                if "`subject'" == "french" replace `subject_eligible' = `subject_eligible' & subject == 2
                if "`subject'" == "math"   replace `subject_eligible' = `subject_eligible' & subject == 3
                bysort cohort_pool: egen long `subject_cohort_n' = total(`subject_eligible')
                generate double `subject_weight' = 1 / `subject_cohort_n' if `subject_eligible' & `subject_cohort_n' > 0
                local analysis_weight "`subject_weight'"
            }
        }

        local insufficient = 0
        quietly count if `outcome' < . `subject_if'
        if r(N) == 0 local insufficient = 1
        if "`allowempty'" != "" & `mincohorts' > 0 {
            local scored_cohorts
            capture quietly levelsof cohort_pool if `outcome' < . `subject_if', ///
                local(scored_cohorts)
            local scored_cohort_n : word count `scored_cohorts'
            if `scored_cohort_n' < `mincohorts' local insufficient = 1
            if "`subject'" == "overall" {
                foreach scored_cohort of local scored_cohorts {
                    local scored_subjects
                    capture quietly levelsof subject if cohort_pool == `scored_cohort' ///
                        & `outcome' < ., local(scored_subjects)
                    local scored_subject_n : word count `scored_subjects'
                    if `scored_subject_n' < 3 local insufficient = 1
                    foreach scored_subject of local scored_subjects {
                        local subject_arms
                        capture quietly levelsof treated if cohort_pool == `scored_cohort' ///
                            & subject == `scored_subject' & `outcome' < ., ///
                            local(subject_arms)
                        local subject_arm_n : word count `subject_arms'
                        if `subject_arm_n' < 2 local insufficient = 1
                    }
                }
            }
            foreach scored_cohort of local scored_cohorts {
                local scored_arms
                capture quietly levelsof treated if cohort_pool == `scored_cohort' ///
                    & `outcome' < . `subject_if', local(scored_arms)
                local scored_arm_n : word count `scored_arms'
                if `scored_arm_n' < 2 local insufficient = 1
            }
        }
        else if "`allowempty'" != "" {
            if "`subject'" == "overall" {
                local scored_subjects
                capture quietly levelsof subject if `outcome' < ., local(scored_subjects)
                local scored_subject_n : word count `scored_subjects'
                if `scored_subject_n' < 3 local insufficient = 1
                foreach scored_subject of local scored_subjects {
                    local subject_arms
                    capture quietly levelsof treated if subject == `scored_subject' ///
                        & `outcome' < ., local(subject_arms)
                    local subject_arm_n : word count `subject_arms'
                    if `subject_arm_n' < 2 local insufficient = 1
                }
            }
            local scored_arms
            capture quietly levelsof treated if `outcome' < . `subject_if', ///
                local(scored_arms)
            local scored_arm_n : word count `scored_arms'
            if `scored_arm_n' < 2 local insufficient = 1
        }
        if `insufficient' {
            if "`allowempty'" == "" {
                di as error "Required headline cell has no complete score coverage: `method' `panel' `subject'"
                exit 2000
            }
            post `controlhandle' ("`method'") ("headline") ("`panel'`cohort'") ///
                ("`subject'") ("not_estimable_score_coverage")
            post `posthandle' ("`method'") ("`panel'") (`exposure') (`cohort') ///
                (`cohort' == 4) (`order') ("`subject'") ///
                (.) (.) (.) (.) (.) (.) (.)
            continue
        }

        local selection_option
        if "`analysis_weight'" != "" local selection_option "weight(`analysis_weight') cellmean"
        capture quietly psp_select_controls, outcome(`outcome') subject("`subject'") ///
            controls("`controls'") gradevar(grade) `selection_option'
        local selection_rc = _rc
        if `selection_rc' {
            if "`allowempty'" == "" exit `selection_rc'
            post `controlhandle' ("`method'") ("headline") ("`panel'`cohort'") ///
                ("`subject'") ("not_estimable_control_selection")
            post `posthandle' ("`method'") ("`panel'") (`exposure') (`cohort') ///
                (`cohort' == 4) (`order') ("`subject'") ///
                (.) (.) (.) (.) (.) (.) (.)
            continue
        }
        local selected "`r(selected)'"
        psp_post_interactions, controls("`selected'")
        local selected_post "`r(interactions)'"

        if "`analysis_weight'" == "" {
            capture quietly reghdfe `outcome' i.post#i.grade#i.pair_est ///
                i.post#i.grade i.post#i.pair_est `selected_post' ///
                post post_treat if `outcome' < . `subject_if', ///
                absorb(student_est) vce(cluster pair_est)
        }
        else if "`method'" == "ministry_sum" {
            /* Exact pooled specification used for the previously delivered
               standardized-sum-score table. */
            capture quietly reghdfe `outcome' `selected_post' post post_treat ///
                if `outcome' < . `subject_if' [aw=`analysis_weight'], ///
                absorb(student_est i.post#i.grade#i.pair_est) ///
                vce(cluster pair_est)
        }
        else {
            capture quietly reghdfe `outcome' i.post#i.grade#i.pair_est ///
                i.post#i.grade i.post#i.pair_est `selected_post' post post_treat ///
                if `outcome' < . `subject_if' [aw=`analysis_weight'], ///
                absorb(student_est) vce(cluster pair_est)
        }
        local regression_rc = _rc
        if `regression_rc' {
            if "`allowempty'" == "" exit `regression_rc'
            post `controlhandle' ("`method'") ("headline") ("`panel'`cohort'") ///
                ("`subject'") ("not_estimable_regression")
            post `posthandle' ("`method'") ("`panel'") (`exposure') (`cohort') ///
                (`cohort' == 4) (`order') ("`subject'") ///
                (.) (.) (.) (.) (.) (.) (.)
            continue
        }
        quietly psp_capture_effect
        if r(ok) != 1 {
            if "`allowempty'" == "" exit 498
            post `controlhandle' ("`method'") ("headline") ("`panel'`cohort'") ///
                ("`subject'") ("not_estimable_effect")
            post `posthandle' ("`method'") ("`panel'") (`exposure') (`cohort') ///
                (`cohort' == 4) (`order') ("`subject'") ///
                (.) (.) (.) (.) (.) (.) (.)
            continue
        }
        post `controlhandle' ("`method'") ("headline") ("`panel'`cohort'") ///
            ("`subject'") ("`selected'")
        post `posthandle' ("`method'") ("`panel'") (`exposure') (`cohort') ///
            (`cohort' == 4) (`order') ("`subject'") ///
            (r(b)) (r(se)) (r(p)) (r(n_students)) (r(n_schools)) ///
            (r(n_pairs)) (r(n_obs))
    }
end

capture program drop psp_load_panel
program define psp_load_panel
    syntax, FILE(string) METHOD(string) [STABLE]
    use "${PANEL_DIR}/`file'", clear
    psp_prepare_loaded_panel, method("`method'") `stable'
end

capture program drop psp_load_pool
program define psp_load_pool
    syntax, FILES(string) COHORTS(numlist) METHOD(string) [STABLE]

    local index = 0
    local pieces
    foreach file of local files {
        local ++index
        local cohort : word `index' of `cohorts'
        use "${PANEL_DIR}/`file'", clear
        generate byte cohort_pool = `cohort'
        tempfile piece`index'
        save `piece`index'', replace
        local pieces `pieces' `piece`index''
    }
    local first : word 1 of `pieces'
    use `first', clear
    local piece_count : word count `pieces'
    if `piece_count' > 1 {
        forvalues index = 2/`piece_count' {
            local next : word `index' of `pieces'
            append using `next'
        }
    }
    psp_prepare_loaded_panel, method("`method'") pooled `stable'

    bysort cohort_pool: egen long cohort_rows = count(student_est)
    generate double cohort_weight = 1 / cohort_rows
end

capture program drop psp_select_controls
program define psp_select_controls, rclass
    syntax, OUTCOME(name) SUBJECT(string) CONTROLS(string) GRADEVAR(name) ///
        [WEIGHT(name) CELLMEAN]

    psp_subject_restriction, subject("`subject'")
    local subject_if "`r(restriction)'"

    tempvar change residual control_mean
    sort student_est post
    by student_est: generate double `change' = `outcome'[2] - `outcome'[1] if _n == 2

    if "`cellmean'" == "" {
        quietly regress `change' i.`gradevar'##i.pair_est if treated == 0, vce(cluster pair_est)
        quietly predict double `residual', residuals
    }
    else {
        bysort pair_est `gradevar': egen double `control_mean' = ///
            mean(cond(treated == 0 & post == 1, `change', .))
        generate double `residual' = `change' - `control_mean'
    }

    local selected
    if strtrim("`controls'") != "" {
        if "`weight'" == "" {
            quietly pdslasso `residual' treated (`controls') ///
                if post == 1 & `outcome' < . `subject_if', cluster(pair_est)
        }
        else {
            quietly pdslasso `residual' treated (`controls') ///
                if post == 1 & `outcome' < . `subject_if' [aw=`weight'], ///
                cluster(pair_est)
        }
        local selected "`e(xselected)'"
    }
    return local selected "`selected'"
end

capture program drop psp_post_interactions
program define psp_post_interactions, rclass
    syntax, [CONTROLS(string)]
    local interactions
    foreach variable of local controls {
        capture confirm numeric variable `variable'
        if !_rc local interactions `interactions' c.`variable'#i.post
    }
    return local interactions "`interactions'"
end

capture program drop psp_sample_counts
program define psp_sample_counts, rclass
    tempvar student_tag school_tag pair_tag
    quietly egen byte `student_tag' = tag(student_est) if e(sample)
    quietly count if `student_tag' == 1
    return scalar n_students = r(N)
    /* school_est is deliberately cohort-qualified in pooled files and is an
       exact copy of the school code in single-cohort files. Counting cd_etab
       directly would merge different schools that reuse a code across cohorts. */
    quietly egen byte `school_tag' = tag(school_est) if e(sample)
    quietly count if `school_tag' == 1
    return scalar n_schools = r(N)
    quietly egen byte `pair_tag' = tag(pair_est) if e(sample)
    quietly count if `pair_tag' == 1
    return scalar n_pairs = r(N)
    quietly count if e(sample)
    return scalar n_obs = r(N)
end

capture program drop psp_capture_effect
program define psp_capture_effect, rclass
    capture local coefficient = _b[post_treat]
    if _rc | missing(_se[post_treat]) | _se[post_treat] <= 0 {
        return scalar ok = 0
        exit
    }
    return scalar ok = 1
    return scalar b = _b[post_treat]
    return scalar se = _se[post_treat]
    quietly test post_treat
    return scalar p = r(p)
    quietly psp_sample_counts
    return scalar n_students = r(n_students)
    return scalar n_schools = r(n_schools)
    return scalar n_pairs = r(n_pairs)
    return scalar n_obs = r(n_obs)
end
