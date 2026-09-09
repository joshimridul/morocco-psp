version 15.0

/*
  Add the preferred IRT score to the already-loaded historical combined
  Ministry data. The original duplicate exclusions, raw-score construction,
  and control merges must already have run. Invoke this immediately before the
  original `tempfile data` / `save `data'' lines, and therefore before baseline
  scores, quartiles, or regression panels are constructed.

  Usage:
    do "<repo>/src/30_ministry_irt_report/apply_irt_to_ministry_loaded_data.do" ///
       "<work_root>/outputs/y1_y3_irt/07_ministry_multiyear_results/analysis_inputs/ministry_irt_score_merge.dta"

  This changes only the dataset in memory and never saves over the source file.
*/

args irt_merge_file
if `"`irt_merge_file'"' == "" {
    di as error "Provide the path to ministry_irt_score_merge.dta"
    exit 198
}

confirm file `"`irt_merge_file'"'
confirm variable id_student_panel wave subject grade
isid id_student_panel wave

merge 1:1 id_student_panel wave using `"`irt_merge_file'"', ///
    keep(master match) generate(_merge_irt_primary)
assert subject == irt_subject if _merge_irt_primary == 3
assert grade == irt_grade if _merge_irt_primary == 3

capture confirm variable score
if _rc generate double score = .
capture confirm variable arabic_score
if _rc generate double arabic_score = .
capture confirm variable french_score
if _rc generate double french_score = .
capture confirm variable math_score
if _rc generate double math_score = .

replace score = irt_primary
replace arabic_score = irt_primary if subject == 1
replace french_score = irt_primary if subject == 2
replace math_score = irt_primary if subject == 3

label variable irt_primary "Preferred IRT score: fixed Year 1 endline comparison scale"
drop irt_subject irt_grade irt_source_panel_n
tabulate _merge_irt_primary

