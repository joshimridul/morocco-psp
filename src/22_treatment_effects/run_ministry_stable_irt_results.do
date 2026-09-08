version 19.0
clear all
set more off
set varabbrev off
set seed 20260720

/* Stable-student/school sensitivity corresponding to Ministry Table 2. */
args work_root
if `"`work_root'"' == "" exit 198
global panel_dir `"`work_root'/outputs/y1_y3_irt/07_ministry_multiyear_results/analysis_inputs"'
global out_dir   `"`work_root'/outputs/y1_y3_irt/07_ministry_multiyear_results"'
capture mkdir "$out_dir/logs"
capture log close _all
log using "$out_dir/logs/ministry_stable_irt_results.log", text replace

foreach command in reghdfe pdslasso unique {
    capture which `command'
    if _rc exit 199
}

global methods "ministry_sum irt_chained_strict irt_pooled_strict_all irt_pooled_strict_control irt_grade_specific_strict irt_chained_provisional"
global subjects "overall arabic french math"
global pupil_c1 "female repeated tayssir grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global pupil_c2 "female grade1 grade2 grade3 grade4 grade5 grade6 score_baseline"
global school_controls "n_teachers urban regional_dev total_enrolled7_sum perc_female perc_tayssir avg_score7_mu perc_ssbenef"

tempfile results controls_file
tempname post_results post_controls
postfile `post_results' str32 score_method byte cohort byte exposure byte subject_order ///
    str8 subject double(b se p n_students n_schools n_pairs n_obs) using `results', replace
postfile `post_controls' str32 score_method str8 panel_id str8 subject str244 controls ///
    using `controls_file', replace

capture program drop estimate_stable
program define estimate_stable
    syntax, FILE(string) PANELID(string) COHORT(integer) EXPOSURE(integer) ///
        METHOD(string) POSTRESULTS(name) POSTCONTROLS(name)

    use "$panel_dir/`file'", clear
    keep if stable_sample == 1
    tempvar analysis_score n_score
    if "`method'" == "ministry_sum" generate double `analysis_score' = score
    else generate double `analysis_score' = `method'
    encode student_id, generate(student_est)
    bysort student_est: egen byte `n_score' = count(`analysis_score')
    keep if `n_score' == 2
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
    generate byte post_treat = post * treated

    local available_controls
    foreach variable in ${pupil_c`cohort'} $school_controls {
        capture confirm numeric variable `variable'
        if !_rc local available_controls `available_controls' `variable'
    }

    local order = 0
    foreach sub of global subjects {
        local ++order
        local outcome "`sub'_score"
        local subject_if
        if "`sub'" == "arabic" local subject_if "& subject == 1"
        if "`sub'" == "french" local subject_if "& subject == 2"
        if "`sub'" == "math"   local subject_if "& subject == 3"

        tempvar change residual
        sort student_est post
        by student_est: generate double `change' = `outcome'[2] - `outcome'[1] if _n == 2
        quietly regress `change' i.grade##i.pair_id if treated == 0, ///
            vce(cluster pair_id)
        quietly predict double `residual', residuals
        quietly pdslasso `residual' treated (`available_controls') ///
            if post == 1 & `outcome' < . `subject_if', cluster(pair_id)
        local selected "`e(xselected)'"
        post `postcontrols' ("`method'") ("`panelid'") ("`sub'") ("`selected'")

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

        tempvar tag_student tag_school tag_pair
        quietly egen byte `tag_student' = tag(student_est) if e(sample)
        quietly count if `tag_student' == 1
        local n_students = r(N)
        quietly egen byte `tag_school' = tag(cd_etab) if e(sample)
        quietly count if `tag_school' == 1
        local n_schools = r(N)
        quietly egen byte `tag_pair' = tag(pair_id) if e(sample)
        quietly count if `tag_pair' == 1
        local n_pairs = r(N)
        quietly count if e(sample)
        local n_obs = r(N)

        post `postresults' ("`method'") (`cohort') (`exposure') (`order') ///
            ("`sub'") (`b') (`se') (`p') (`n_students') (`n_schools') ///
            (`n_pairs') (`n_obs')
        drop `change' `residual'
    }
end

foreach method of global methods {
    estimate_stable, file("c1e1_irt_panel.dta") panelid("c1e1") cohort(1) exposure(1) ///
        method("`method'") postresults(`post_results') postcontrols(`post_controls')
    estimate_stable, file("c1e2_irt_panel.dta") panelid("c1e2") cohort(1) exposure(2) ///
        method("`method'") postresults(`post_results') postcontrols(`post_controls')
    estimate_stable, file("c1e3_irt_panel.dta") panelid("c1e3") cohort(1) exposure(3) ///
        method("`method'") postresults(`post_results') postcontrols(`post_controls')
    estimate_stable, file("c2e1_irt_panel.dta") panelid("c2e1") cohort(2) exposure(1) ///
        method("`method'") postresults(`post_results') postcontrols(`post_controls')
    estimate_stable, file("c2e2_irt_panel.dta") panelid("c2e2") cohort(2) exposure(2) ///
        method("`method'") postresults(`post_results') postcontrols(`post_controls')
}

postclose `post_results'
postclose `post_controls'
use `results', clear
sort score_method cohort exposure subject_order
export delimited using "$out_dir/ministry_stable_irt_estimates.csv", replace
save "$out_dir/ministry_stable_irt_estimates.dta", replace
use `controls_file', clear
sort score_method panel_id subject
export delimited using "$out_dir/ministry_stable_irt_selected_controls.csv", replace
di as result "MINISTRY STABLE-SAMPLE IRT RESULTS COMPLETE"
log close
