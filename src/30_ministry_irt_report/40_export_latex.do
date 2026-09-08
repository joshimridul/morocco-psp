version 19.0

/* All publication tables are written by Stata from aggregate result files. */

capture program drop psp_latex_value
program define psp_latex_value, rclass
    syntax, STAT(string) [PVAR(name)]
    quietly count
    if r(N) == 0 {
        return local text ""
        exit
    }
    quietly summarize `stat', meanonly
    if r(N) == 0 | missing(r(mean)) {
        return local text ""
        exit
    }
    if "`stat'" == "b" {
        local out = strtrim(string(r(mean), "%9.3f"))
        quietly summarize `pvar', meanonly
        if r(mean) < .01 local out "`out'$^{***}$"
        else if r(mean) < .05 local out "`out'$^{**}$"
        else if r(mean) < .10 local out "`out'$^{*}$"
        capture quietly summarize n_pairs, meanonly
        if !_rc & r(N) > 0 & r(mean) < 20 local out "`out'$^{\dagger}$"
    }
    else if "`stat'" == "se" {
        local out = "(" + strtrim(string(r(mean), "%9.3f")) + ")"
    }
    else if inlist("`stat'", "p", "p_by") {
        local out = "[" + strtrim(string(r(mean), "%9.3f")) + "]"
    }
    else local out = strtrim(string(r(mean), "%12.0fc"))
    return local text "`out'"
end

capture program drop psp_method_label
program define psp_method_label, rclass
    syntax, METHOD(string)
    local label "`method'"
    if "`method'" == "primary_irt"            local label "Preferred anchors, all students, subject models (EAP)"
    if "`method'" == "primary_wle"            local label "Same item model, WLE scores"
    if "`method'" == "subject_final_control"  local label "Preferred anchors, comparison-school calibration"
    if "`method'" == "grade_final_all"        local label "Preferred anchors, separate grade models"
    if "`method'" == "grade_final_control"    local label "Preferred anchors, grade models, comparison schools"
    if "`method'" == "pooled_strict_all"      local label "Conservative anchors, subject models"
    if "`method'" == "pooled_strict_control"  local label "Conservative anchors, comparison-school calibration"
    if "`method'" == "grade_specific_strict"  local label "Conservative anchors, separate grade models"
    if "`method'" == "grade_strict_control"   local label "Conservative anchors, grade models, comparison schools"
    if "`method'" == "chained_strict"         local label "Sequential links, conservative anchors"
    if "`method'" == "direct_strict"          local label "Direct Year 1 links, conservative anchors"
    if "`method'" == "pooled_andy_core"       local label "Targeted DIF rule without the link-retention floor"
    if "`method'" == "pooled_broad"           local label "More item parameters allowed to differ"
    if "`method'" == "dev_schools_final"      local label "Calibration in a predetermined school subset"
    if "`method'" == "chained_provisional"    local label "Sequential links, broader anchor definition"
    if "`method'" == "direct_provisional"     local label "Direct Year 1 links, broader anchor definition"
    if "`method'" == "ministry_sum_same_sample" local label "Earlier sum score, same students as preferred IRT"
    if "`method'" == "ministry_sum"           local label "Earlier sum score, full available sample"
    return local text "`label'"
end

capture program drop psp_result_cell
program define psp_result_cell, rclass
    syntax, STAT(string) COHORT(integer) SUBJECT(integer) ///
        [PANEL(string) EXPOSURE(integer -1) GRADE(integer -1) GROUP(integer -1) PVAR(name)]
    preserve
        keep if score_method == "primary_irt" & cohort == `cohort' & subject_order == `subject'
        if "`panel'" != "" keep if panel == "`panel'"
        if `exposure' >= 0 keep if exposure == `exposure'
        if `grade' >= 0 keep if grade == `grade'
        if `group' >= 0 keep if group_order == `group'
        quietly psp_latex_value, stat("`stat'") pvar(`pvar')
        local value "`r(text)'"
    restore
    return local text "`value'"
end

capture program drop psp_robustness_stack
program define psp_robustness_stack, rclass
    syntax, METHOD(string) PANEL(string) SUBJECT(integer) STAT(string)
    preserve
        keep if score_method == "`method'" & panel == "`panel'" ///
            & subject_order == `subject'
        quietly count
        if r(N) == 0 {
            if "`stat'" == "b" local value "--"
            else local value ""
        }
        else {
            quietly summarize b, meanonly
            if r(N) == 0 | missing(r(mean)) {
                if "`stat'" == "b" local value "--"
                else local value ""
            }
            else {
                quietly psp_latex_value, stat("`stat'") pvar(p)
                local value "`r(text)'"
            }
        }
    restore
    return local text "`value'"
end

capture program drop psp_write_wide_header
program define psp_write_wide_header
    syntax, HANDLE(name) BLOCKS(integer) [NUMBERS]
    if `blocks' == 4 {
        file write `handle' " & \multicolumn{4}{c}{Cohort 1 (2023/24)} & \multicolumn{4}{c}{Cohort 2 (2024/25)} & \multicolumn{4}{c}{Cohort 3 (2025/26)} & \multicolumn{4}{c}{Cohorts Pooled} \\" _n
        file write `handle' "\cmidrule(lr){2-5} \cmidrule(lr){6-9} \cmidrule(lr){10-13} \cmidrule(lr){14-17}" _n
        file write `handle' " & Overall & Arabic & French & Math & Overall & Arabic & French & Math & Overall & Arabic & French & Math & Overall & Arabic & French & Math \\" _n
    }
    else if `blocks' == 3 {
        file write `handle' " & \multicolumn{4}{c}{Cohort 1 (2023/24)} & \multicolumn{4}{c}{Cohort 2 (2024/25)} & \multicolumn{4}{c}{Cohorts Pooled} \\" _n
        file write `handle' "\cmidrule(lr){2-5} \cmidrule(lr){6-9} \cmidrule(lr){10-13}" _n
        file write `handle' " & Overall & Arabic & French & Math & Overall & Arabic & French & Math & Overall & Arabic & French & Math \\" _n
    }
    else {
        file write `handle' " & \multicolumn{4}{c}{Cohort 1 (2023/24)} \\" _n
        file write `handle' "\cmidrule(lr){2-5}" _n
        file write `handle' " & Overall & Arabic & French & Math \\" _n
    }
    if "`numbers'" != "" {
        local column_n = 4 * `blocks'
        file write `handle' ""
        forvalues column = 1/`column_n' {
            file write `handle' " & (`column')"
        }
        file write `handle' " \\" _n
    }
end

/* Table 1: headline effects. */
use "${EST}/headline.dta", clear
tempname tex
file open `tex' using "${TABLES}/01_headline.tex", write replace text
file write `tex' "\begin{table}[H]\centering" _n
file write `tex' "\caption{Students' Performance After 3-Year Rollout}" _n
file write `tex' "\label{tab:headline}" _n
file write `tex' "\resizebox{\linewidth}{!}{%" _n
file write `tex' "\begin{tabular}{l*{16}{c}}\toprule" _n
psp_write_wide_header, handle(`tex') blocks(4) numbers
file write `tex' "\midrule" _n
foreach panel in A B C {
    if "`panel'" == "A" local panel_title "Panel A: 1-Year Exposure"
    if "`panel'" == "B" local panel_title "Panel B: 2-Year Exposure"
    if "`panel'" == "C" local panel_title "Panel C: 3-Year Exposure"
    file write `tex' "\multicolumn{17}{l}{\textit{`panel_title'}} \\[2pt]" _n
    foreach stat in b se p {
        if "`stat'" == "b" file write `tex' "All students"
        else file write `tex' ""
        forvalues cohort = 1/4 {
            forvalues subject = 1/4 {
                quietly psp_result_cell, stat("`stat'") cohort(`cohort') ///
                    subject(`subject') panel("`panel'") pvar(p)
                file write `tex' " & `r(text)'"
            }
        }
        file write `tex' " \\" _n
    }
    file write `tex' "\addlinespace" _n
    foreach stat in n_students n_schools {
        if "`stat'" == "n_students" file write `tex' "Number of Students"
        else file write `tex' "Number of Schools"
        forvalues cohort = 1/4 {
            forvalues subject = 1/4 {
                quietly psp_result_cell, stat("`stat'") cohort(`cohort') ///
                    subject(`subject') panel("`panel'") pvar(p)
                file write `tex' " & `r(text)'"
            }
        }
        file write `tex' " \\" _n
    }
    file write `tex' "\addlinespace[8pt]" _n
}
file write `tex' "\bottomrule\end{tabular}}" _n
file write `tex' "\TableNote{Student fixed-effects matched difference-in-differences estimates. The outcome is the primary subject-specific concurrent IRT score on the fixed Year 1 published scale; Year 1 scores and item parameters are unchanged. Overall stacks the three subject samples. All models include matched-pair-by-grade trends and post interactions with double-selected baseline controls. Standard errors clustered by matched pair are in parentheses; p-values are in brackets. Pooled estimates give each cohort equal total weight within the outcome sample. In pooled columns, Number of Schools counts school-by-cohort estimation units; a school identifier observed in two cohorts is counted once per cohort because treatment status and follow-up differ. The preferred anchor rule retains a transparent minimum number of verified anchors on links needed to score the complete Year 3 grade panel; stricter link rules are reported as robustness checks.}" _n
file write `tex' "\end{table}" _n
file close `tex'

/* Table 2: stable samples. */
use "${EST}/stable.dta", clear
tempname tex
file open `tex' using "${TABLES}/02_stable.tex", write replace text
file write `tex' "\begin{table}[H]\centering\caption{Students Performance After 3 Years with Stable Samples}\label{tab:stable}" _n
file write `tex' "\resizebox{\linewidth}{!}{\begin{tabular}{l*{12}{c}}\toprule" _n
file write `tex' " & \multicolumn{4}{c}{1-Year Exposure} & \multicolumn{4}{c}{2-Year Exposure} & \multicolumn{4}{c}{3-Year Exposure} \\" _n
file write `tex' "\cmidrule(lr){2-5}\cmidrule(lr){6-9}\cmidrule(lr){10-13}" _n
file write `tex' " & Overall & Arabic & French & Math & Overall & Arabic & French & Math & Overall & Arabic & French & Math \\" _n
file write `tex' " & (1) & (2) & (3) & (4) & (5) & (6) & (7) & (8) & (9) & (10) & (11) & (12) \\" _n
file write `tex' "\midrule" _n
forvalues cohort = 1/2 {
    if `cohort' == 1 local label "Panel A: Cohort 1 (2023/24)"
    else local label "Panel B: Cohort 2 (2024/25)"
    file write `tex' "\multicolumn{13}{l}{\textit{`label'}} \\[2pt]" _n
    foreach stat in b se p {
        if "`stat'" == "b" file write `tex' "All students"
        else file write `tex' ""
        forvalues exposure = 1/3 {
            forvalues subject = 1/4 {
                quietly psp_result_cell, stat("`stat'") cohort(`cohort') ///
                    subject(`subject') exposure(`exposure') pvar(p)
                file write `tex' " & `r(text)'"
            }
        }
        file write `tex' " \\" _n
    }
    foreach stat in n_students n_schools {
        if "`stat'" == "n_students" file write `tex' "\addlinespace Number of Students"
        else file write `tex' "Number of Schools"
        forvalues exposure = 1/3 {
            forvalues subject = 1/4 {
                quietly psp_result_cell, stat("`stat'") cohort(`cohort') ///
                    subject(`subject') exposure(`exposure') pvar(p)
                file write `tex' " & `r(text)'"
            }
        }
        file write `tex' " \\" _n
    }
    file write `tex' "\addlinespace[8pt]" _n
}
file write `tex' "\bottomrule\end{tabular}}" _n
file write `tex' "\TableNote{The stable sample fixes each cohort's matched-pair support to that available at its final observed exposure, following the Ministry report definition. Estimation and inference otherwise follow Table~\ref{tab:headline}.}" _n
file write `tex' "\end{table}" _n
file close `tex'

/* Tables 3 and 4: heterogeneity. */
use "${EST}/heterogeneity.dta", clear
foreach type in gender baseline {
    if "`type'" == "gender" {
        local number 03
        local groups "1 2"
        local caption "Heterogeneity in Students' Performance by Gender"
        local label "tab:gender"
        local note "Female and male subsamples are defined using the recorded student gender."
    }
    else {
        local number 04
        local groups "3 5"
        local caption "Heterogeneity in Students' Performance by Baseline Performance"
        local label "tab:baseline"
        local note "Lowest- and highest-baseline-performance groups use the subject-specific ranked groups supplied in the analysis design files; Overall uses the overall baseline ranking. Ties can make these groups differ slightly from exactly 25 percent of the sample."
    }
    tempname tex
    file open `tex' using "${TABLES}/`number'_`type'.tex", write replace text
    file write `tex' "\begin{table}[H]\centering\caption{`caption'}\label{`label'}" _n
    file write `tex' "\resizebox{\linewidth}{!}{\begin{tabular}{l*{16}{c}}\toprule" _n
    psp_write_wide_header, handle(`tex') blocks(4) numbers
    file write `tex' "\midrule" _n
    foreach panel in A B C {
        if "`panel'" == "A" local panel_title "Panel A: 1-Year Exposure"
        if "`panel'" == "B" local panel_title "Panel B: 2-Year Exposure"
        if "`panel'" == "C" local panel_title "Panel C: 3-Year Exposure"
        file write `tex' "\multicolumn{17}{l}{\textit{`panel_title'}} \\[2pt]" _n
        foreach group of local groups {
            if `group' == 1 local row "Female"
            if `group' == 2 local row "Male"
            if `group' == 3 local row "Lowest baseline score group"
            if `group' == 5 local row "Highest baseline score group"
            foreach stat in b se p {
                if "`stat'" == "b" file write `tex' "`row'"
                else file write `tex' ""
                forvalues cohort = 1/4 {
                    forvalues subject = 1/4 {
                        quietly psp_result_cell, stat("`stat'") cohort(`cohort') ///
                            subject(`subject') panel("`panel'") group(`group') pvar(p)
                        file write `tex' " & `r(text)'"
                    }
                }
                file write `tex' " \\" _n
            }
            foreach stat in n_students n_schools {
                if "`stat'" == "n_students" file write `tex' "\addlinespace Number of Students"
                else file write `tex' "Number of Schools"
                forvalues cohort = 1/4 {
                    forvalues subject = 1/4 {
                        quietly psp_result_cell, stat("`stat'") cohort(`cohort') ///
                            subject(`subject') panel("`panel'") group(`group') pvar(p)
                        file write `tex' " & `r(text)'"
                    }
                }
                file write `tex' " \\" _n
            }
            file write `tex' "\addlinespace[5pt]" _n
        }
        file write `tex' "\addlinespace[5pt]" _n
    }
    file write `tex' "\bottomrule\end{tabular}}" _n
    file write `tex' "\TableNote{`note' Outcomes and estimation otherwise follow Table~\ref{tab:headline}. In pooled columns, Number of Schools counts school-by-cohort estimation units. P-values are unadjusted, matching the Ministry report. Some subgroup cells have as few as 10 matched-pair clusters, so their conventional cluster-robust inference should be interpreted cautiously.}" _n
    file write `tex' "\end{table}" _n
    file close `tex'
}

/* Tables 5--7: baseline-grade effects. */
use "${EST}/grade.dta", clear
forvalues exposure = 1/3 {
    if `exposure' == 1 {
        local number 05
        local blocks 4
        local cohorts "1 2 3 4"
        local span 17
        local columns 16
        local word "One"
        local plural ""
    }
    if `exposure' == 2 {
        local number 06
        local blocks 3
        local cohorts "1 2 4"
        local span 13
        local columns 12
        local word "Two"
        local plural "s"
    }
    if `exposure' == 3 {
        local number 07
        local blocks 1
        local cohorts "1"
        local span 5
        local columns 4
        local word "Three"
        local plural "s"
    }
    tempname tex
    file open `tex' using "${TABLES}/`number'_grade_`exposure'year.tex", write replace text
    file write `tex' "\begin{table}[H]\centering\caption{Grade-Specific Effects on Student Performance After `word' Year`plural'}\label{tab:grade`exposure'}" _n
    if `exposure' < 3 file write `tex' "\resizebox{\linewidth}{!}{\begin{tabular}{l*{`columns'}{c}}\toprule" _n
    else file write `tex' "\begin{tabular}{l*{`columns'}{c}}\toprule" _n
    psp_write_wide_header, handle(`tex') blocks(`blocks')
    file write `tex' "\midrule" _n
    local max_grade = 7 - `exposure'
    forvalues grade = 1/`max_grade' {
        foreach stat in b se p_by n_students n_schools {
            if "`stat'" == "b" file write `tex' "Grade `grade'"
            else if "`stat'" == "n_students" file write `tex' "Number of Students"
            else if "`stat'" == "n_schools" file write `tex' "Number of Schools"
            else file write `tex' ""
            foreach cohort of local cohorts {
                forvalues subject = 1/4 {
                    quietly psp_result_cell, stat("`stat'") cohort(`cohort') ///
                        subject(`subject') exposure(`exposure') grade(`grade') pvar(p_by)
                    file write `tex' " & `r(text)'"
                }
            }
            file write `tex' " \\" _n
        }
        file write `tex' "\addlinespace[5pt]" _n
    }
    if `exposure' < 3 file write `tex' "\bottomrule\end{tabular}}" _n
    else file write `tex' "\bottomrule\end{tabular}" _n
    file write `tex' "\TableNote{Grade is defined at baseline. Student and school counts refer to each grade-specific regression; in pooled columns, Number of Schools counts school-by-cohort estimation units. Benjamini--Yekutieli adjusted p-values are in brackets and determine stars; adjustment is within each exposure-by-cohort family across grades and outcomes. Pooled estimates give each available cohort equal total weight within the grade-by-outcome sample. Blank cells are structural when a cohort was not observed in that entry grade. Outcomes and other estimation details follow Table~\ref{tab:headline}.}" _n
    file write `tex' "\end{table}" _n
    file close `tex'
}

/* Table 8: measurement-method robustness for the headline estimands. */
use "${EST}/measurement_robustness.dta", clear
tempname tex
file open `tex' using "${TABLES}/08_measurement_robustness.tex", write replace text
file write `tex' "\begin{table}[H]\centering\scriptsize" _n
file write `tex' "\caption{Robustness of Headline Effects to Measurement Method}" _n
file write `tex' "\label{tab:measurement_robustness}" _n
file write `tex' "\renewcommand{\arraystretch}{0.98}" _n
file write `tex' "\resizebox{\linewidth}{!}{%" _n
file write `tex' "\begin{tabular}{l*{12}{c}}\toprule" _n
file write `tex' " & \multicolumn{4}{c}{One Year of Exposure} & \multicolumn{4}{c}{Two Years of Exposure} & \multicolumn{4}{c}{Three Years of Exposure} \\" _n
file write `tex' "\cmidrule(lr){2-5}\cmidrule(lr){6-9}\cmidrule(lr){10-13}" _n
file write `tex' "Method & Overall & Arabic & French & Math & Overall & Arabic & French & Math & Overall & Arabic & French & Math \\\midrule" _n
foreach method of global ROBUSTNESS_METHODS {
    if "`method'" == "primary_irt" {
        file write `tex' "\multicolumn{13}{l}{\textit{Models that estimate all tests together}} \\[2pt]" _n
    }
    if "`method'" == "chained_strict" {
        file write `tex' "\addlinespace[2pt]\multicolumn{13}{l}{\textit{Other ways of linking tests and estimating item characteristics}} \\[1pt]" _n
    }
    if "`method'" == "chained_provisional" {
        file write `tex' "\addlinespace[2pt]\multicolumn{13}{l}{\textit{Broader definitions of an anchor and the earlier Ministry score}} \\[1pt]" _n
    }
    quietly psp_method_label, method("`method'")
    local label "`r(text)'"

    foreach stat in b se {
        if "`stat'" == "b" file write `tex' "`label'"
        else file write `tex' ""
        foreach panel in A B C {
            forvalues subject = 1/4 {
                quietly psp_robustness_stack, method("`method'") ///
                    panel("`panel'") subject(`subject') stat("`stat'")
                file write `tex' " & `r(text)'"
            }
        }
        file write `tex' " \\" _n
    }
    file write `tex' "\addlinespace[1pt]" _n
}
file write `tex' "\bottomrule\end{tabular}}" _n
file write `tex' "\TableNote{Each cell reports the treatment effect, with its standard error immediately below in parentheses. Standard errors allow for correlation within matched school pairs. A dash means that the method could not produce scores for all groups needed in that column, or that the regression could not be estimated with the available scores. All other aspects of the regression are the same as in Table~\ref{tab:headline}. The one- and two-year columns combine all cohorts observed for the stated number of years and give each cohort equal weight. Only Cohort 1 is observed for three years. The WLE routine returned finite scores for every record but reported iteration-limit warnings for 95 of 56,183 response patterns, so that row is a scoring stress test; the preferred EAP score is unaffected. Appendix~\ref{app:irt} explains what each method changes.}" _n
file write `tex' "\end{table}" _n
file close `tex'

/* Table 9: sample retained by each measurement method. */
capture program drop psp_robustness_retention
program define psp_robustness_retention, rclass
    syntax, METHOD(string) PANEL(string) SUBJECT(integer)
    preserve
        quietly summarize n_students if score_method == "primary_irt" & ///
            panel == "`panel'" & subject_order == `subject', meanonly
        local primary_n = r(mean)
        quietly summarize n_students if score_method == "`method'" & ///
            panel == "`panel'" & subject_order == `subject', meanonly
        if r(N) == 0 | missing(r(mean)) | missing(`primary_n') | `primary_n' <= 0 {
            local value "--"
        }
        else local value = strtrim(string(100 * r(mean) / `primary_n', "%9.1f"))
    restore
    return local text "`value'"
end

tempname tex
file open `tex' using "${TABLES}/09_measurement_sample_retention.tex", write replace text
file write `tex' "\begin{table}[H]\centering\scriptsize\caption{Sample Retained by Measurement Method (Percent of Primary IRT Sample)}\label{tab:measurement_samples}" _n
file write `tex' "\resizebox{\linewidth}{!}{\begin{tabular}{l*{12}{c}}\toprule" _n
file write `tex' " & \multicolumn{4}{c}{One Year} & \multicolumn{4}{c}{Two Years} & \multicolumn{4}{c}{Three Years} \\" _n
file write `tex' "\cmidrule(lr){2-5}\cmidrule(lr){6-9}\cmidrule(lr){10-13}" _n
file write `tex' "Method & Overall & Arabic & French & Math & Overall & Arabic & French & Math & Overall & Arabic & French & Math \\\midrule" _n
foreach method of global ROBUSTNESS_METHODS {
    quietly psp_method_label, method("`method'")
    file write `tex' "`r(text)'"
    foreach panel in A B C {
        forvalues subject = 1/4 {
            quietly psp_robustness_retention, method("`method'") panel("`panel'") subject(`subject')
            file write `tex' " & `r(text)'"
        }
    }
    file write `tex' " \\" _n
}
file write `tex' "\bottomrule\end{tabular}}" _n
file write `tex' "\PlainTableNote{Entries are unique-student counts as a percentage of the corresponding primary IRT regression sample. Values above 100 indicate that the alternative can score students whose test has no retained link to Year 1. The same-sample sum-score row is exactly 100 by construction.}" _n
file write `tex' "\end{table}" _n
file close `tex'

/* Table 10: weak mathematics links and the resulting scale sensitivity. */
preserve
    import delimited using "${WORK}/outputs/y1_y3_irt/05_anchor_purification/comparison_only/multiyear_andy_core_math_bridge5_purified_selected_paths.csv", clear varnames(1)
    keep if year == 3 & subject == "Maths" & inlist(wave, "baseline", "endline")
    rename administered_grade grade
    keep wave grade path_status root_direct_anchor_n path_minimum_anchor_n
    tempfile math_links
    save `math_links', replace

    import delimited using "${WORK}/outputs/y1_y3_irt/06_outcome_construction/correlations/measurement_method_node_pairwise_diagnostics.csv", clear varnames(1)
    keep if year == 3 & subject == "Maths" & left_method == "concurrent_subject_all_final" & right_method == "chained__strict_summary"
    rename administered_grade grade
    generate double mean_shift = mean_left - mean_right
    generate double sd_ratio = sd_left / sd_right
    keep wave grade common_n pearson mean_shift sd_ratio
    merge 1:1 wave grade using `math_links', assert(2 3) nogen
    generate byte wave_order = cond(wave == "baseline", 1, 2)
    sort wave_order grade

    tempname tex
    file open `tex' using "${TABLES}/10_math_link_diagnostics.tex", write replace text
    file write `tex' "\begin{table}[H]\centering\caption{Year 3 Mathematics Links and Scale Sensitivity}\label{tab:mathlinks}" _n
    file write `tex' "\resizebox{\linewidth}{!}{\begin{tabular}{lrrrrrrr}\toprule Round & Grade & Direct Y1 anchors & Weakest link & Common scores & Correlation & Mean difference & SD ratio \\\midrule" _n
    quietly count
    forvalues row = 1/`r(N)' {
        local round = proper(wave[`row'])
        local grade = strtrim(string(grade[`row'], "%9.0f"))
        local direct = strtrim(string(root_direct_anchor_n[`row'], "%9.0f"))
        local weakest = cond(missing(path_minimum_anchor_n[`row']), "--", strtrim(string(path_minimum_anchor_n[`row'], "%9.0f")))
        local common = cond(missing(common_n[`row']), "--", strtrim(string(common_n[`row'], "%12.0fc")))
        local corr = cond(missing(pearson[`row']), "--", strtrim(string(pearson[`row'], "%9.3f")))
        local shift = cond(missing(mean_shift[`row']), "--", strtrim(string(mean_shift[`row'], "%9.3f")))
        local ratio = cond(missing(sd_ratio[`row']), "--", strtrim(string(sd_ratio[`row'], "%9.3f")))
        file write `tex' "`round' & `grade' & `direct' & `weakest' & `common' & `corr' & `shift' & `ratio' \\" _n
    }
    file write `tex' "\bottomrule\end{tabular}}" _n
    file write `tex' "\PlainTableNote{Direct anchors are accepted binary questions shared with the fixed Year 1 bank. Weakest link is the smallest anchor count along the selected path. Correlation, mean difference, and SD ratio compare the primary concurrent score with conservative sequential linking among students scored by both methods; the ratio is primary SD divided by sequential SD. A dash means that sequential linking did not score the group. High correlations show nearly identical rankings even where the scale origin or unit differs.}" _n
    file write `tex' "\end{table}" _n
    file close `tex'
restore

/* Table 11: primary IRT model diagnostics. */
preserve
    import delimited using "${WORK}/outputs/y1_y3_irt/04_joint_multigroup/subject_pooled_mixture_all_purified_andy_core_math_bridge5/joint_model_summary.csv", clear varnames(1)
    /* Stata truncates the 36-character CSV header to its 32-character
       variable-name limit. Rename it immediately to a stable local name. */
    keep subject estimated_discrimination_upper_b
    rename estimated_discrimination_upper_b discrimination_cap
    tempfile optimization_limits
    save `optimization_limits', replace

    import delimited using "${WORK}/outputs/y1_y3_irt/04_joint_multigroup/subject_pooled_mixture_all_purified_andy_core_math_bridge5/joint_item_parameters.csv", clear varnames(1)
    merge m:1 subject using `optimization_limits', assert(3) nogen
    keep if fixed_y1_anchor == 0
    generate byte discrimination_at_cap = discrimination_a >= discrimination_cap - 0.000001
    collapse (sum) discrimination_at_cap, by(subject)
    tempfile boundary_counts
    save `boundary_counts', replace

    import delimited using "${WORK}/outputs/y1_y3_irt/04_joint_multigroup/subject_pooled_mixture_all_purified_andy_core_math_bridge5/primary_diagnostic_summary.csv", clear varnames(1)
    merge 1:1 subject using `boundary_counts', assert(3) nogen
    tempname tex
    file open `tex' using "${TABLES}/11_primary_irt_diagnostics.tex", write replace text
    file write `tex' "\begin{table}[H]\centering\caption{Primary IRT Model Diagnostics}\label{tab:irtdiagnostics}" _n
    file write `tex' "\resizebox{\linewidth}{!}{\begin{tabular}{lrrrrrrr}\toprule Subject & Items tested & Item-fit warnings & Discriminations at cap & Nodes checked & Maximum $|Q3|$ & Maximum RMSEA & Maximum SRMSR \\\midrule" _n
    quietly count
    forvalues row = 1/`r(N)' {
        local subject_label = subject[`row']
        if "`subject_label'" == "Maths" local subject_label "Mathematics"
        local items = strtrim(string(item_fit_tested_n[`row'], "%9.0f"))
        local warnings = strtrim(string(item_fit_warning_n[`row'], "%9.0f"))
        local capped = strtrim(string(discrimination_at_cap[`row'], "%9.0f"))
        local nodes = strtrim(string(global_fit_node_n[`row'], "%9.0f"))
        local q3 = cond(missing(max_abs_q3[`row']), "--", strtrim(string(max_abs_q3[`row'], "%9.3f")))
        local rmsea = cond(missing(global_fit_rmsea[`row']), "--", strtrim(string(global_fit_rmsea[`row'], "%9.3f")))
        local srmsr = cond(missing(global_fit_srmsr[`row']), "--", strtrim(string(global_fit_srmsr[`row'], "%9.3f")))
        file write `tex' "`subject_label' & `items' & `warnings' & `capped' & `nodes' & `q3' & `rmsea' & `srmsr' \\" _n
    }
    file write `tex' "\bottomrule\end{tabular}}" _n
    file write `tex' "\PlainTableNote{The discrimination cap is 10 and applies only to freely estimated Year 2--3 parameters; fixed Year 1 parameters are unchanged. Item fit uses a missing-data-compatible limited-information statistic; warnings indicate a Holm-adjusted p-value below 0.05 or item RMSEA above 0.06. Global fit and Q3 residual correlations are calculated separately within each administered test because a pooled incomplete-booklet response matrix contains structural missingness. The table reports the maximum diagnostic value across successfully checked tests. Absolute Q3 above 0.20 is flagged for review. These are warnings, not automatic item exclusions.}" _n
    file write `tex' "\end{table}" _n
    file close `tex'
restore

di as result "Eleven IRT LaTeX tables written to ${TABLES}"
