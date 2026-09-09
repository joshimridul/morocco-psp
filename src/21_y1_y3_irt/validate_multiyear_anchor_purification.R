#!/usr/bin/env Rscript

# Aggregate validation and synthesis for the multiyear anchor purification.

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: validate_multiyear_anchor_purification.R config/paths.local.yml")
paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
is_within <- function(path, root) {
  candidate <- normalizePath(path, mustWork = FALSE); boundary <- normalizePath(root, mustWork = FALSE)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_output <- function(path) {
  candidate <- normalizePath(path, mustWork = FALSE)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x) && !is_within(work_root, .x)))) stop("Output inside a read-only legacy root")
  candidate
}

root <- file.path(work_root, "outputs/y1_y3_irt/05_anchor_purification")
comparison_dir <- file.path(root, "comparison_only")
all_dir <- file.path(root, "all_students_blinded")
math_screen_dir <- file.path(root, "comparison_only_math_bridge5")
derived_dir <- file.path(work_root, "derived/y1_y3_irt")
model_dir <- file.path(work_root, "outputs/y1_y3_irt/04_joint_multigroup/subject_pooled_mixture_all_purified_strict")
core_model_dir <- file.path(work_root, "outputs/y1_y3_irt/04_joint_multigroup/subject_pooled_mixture_all_purified_andy_core")
math_model_dir <- file.path(work_root, "outputs/y1_y3_irt/04_joint_multigroup/subject_pooled_mixture_all_purified_andy_core_math_bridge5")
treatment_dir <- file.path(work_root, "outputs/y1_y3_irt/06_treatment_effect_sensitivity")

comparison_evidence <- read_csv(file.path(comparison_dir, "multiyear_anchor_dif_evidence.csv"), show_col_types = FALSE)
all_evidence <- read_csv(file.path(all_dir, "multiyear_anchor_dif_evidence.csv"), show_col_types = FALSE)
decisions <- read_csv(file.path(comparison_dir, "multiyear_anchor_link_decisions_with_targets.csv"), show_col_types = FALSE)
mapping <- read_csv(file.path(derived_dir, "multiyear_purified_targeted_occurrence_mapping.csv"), show_col_types = FALSE)
cohort_overrides <- read_csv(file.path(derived_dir, "multiyear_purified_cohort_key_overrides.csv"), show_col_types = FALSE)
paths_output <- read_csv(file.path(comparison_dir, "multiyear_targeted_purified_selected_paths.csv"), show_col_types = FALSE)
core_mapping <- read_csv(file.path(derived_dir, "multiyear_purified_andy_core_occurrence_mapping.csv"), show_col_types = FALSE)
core_paths <- read_csv(file.path(comparison_dir, "multiyear_andy_core_purified_selected_paths.csv"), show_col_types = FALSE)
model_summary <- read_csv(file.path(model_dir, "joint_model_summary.csv"), show_col_types = FALSE)
node_summary <- read_csv(file.path(model_dir, "joint_node_scoring_summary.csv"), show_col_types = FALSE)
core_model_summary <- read_csv(file.path(core_model_dir, "joint_model_summary.csv"), show_col_types = FALSE)
core_node_summary <- read_csv(file.path(core_model_dir, "joint_node_scoring_summary.csv"), show_col_types = FALSE)
core_parameters <- read_csv(file.path(core_model_dir, "joint_item_parameters.csv"), show_col_types = FALSE)
math_decisions <- read_csv(file.path(math_screen_dir, "multiyear_anchor_link_decisions.csv"), show_col_types = FALSE)
math_mapping <- read_csv(file.path(derived_dir, "multiyear_purified_andy_core_math_bridge5_occurrence_mapping.csv"), show_col_types = FALSE)
math_paths <- read_csv(file.path(comparison_dir, "multiyear_andy_core_math_bridge5_purified_selected_paths.csv"), show_col_types = FALSE)
math_model_summary <- read_csv(file.path(math_model_dir, "joint_model_summary.csv"), show_col_types = FALSE)
math_node_summary <- read_csv(file.path(math_model_dir, "joint_node_scoring_summary.csv"), show_col_types = FALSE)
math_parameters <- read_csv(file.path(math_model_dir, "joint_item_parameters.csv"), show_col_types = FALSE)
occurrences <- read_csv(file.path(work_root, "outputs/y1_y3_irt/01_multiyear_link_graph/multiyear_item_occurrence_manifest.csv"), show_col_types = FALSE)
core_reference <- occurrences %>%
  inner_join(core_mapping %>% select(node_id, item_id, purified_analysis_key, purified_direct_y1_anchor), by = c("node_id", "item_id")) %>%
  filter(purified_direct_y1_anchor == 1) %>%
  distinct(subject, purified_analysis_key, y1_discrimination_a, y1_difficulty_b)
core_fixed_parameter_fidelity <- core_parameters %>%
  filter(fixed_y1_anchor == 1) %>%
  inner_join(core_reference, by = c("subject", "analysis_key" = "purified_analysis_key")) %>%
  group_by(subject) %>%
  summarize(
    fixed_anchor_n = n(),
    maximum_absolute_discrimination_difference = max(abs(discrimination_a - y1_discrimination_a)),
    maximum_absolute_difficulty_difference = max(abs(difficulty_b - y1_difficulty_b)),
    .groups = "drop"
  )
math_reference <- occurrences %>%
  inner_join(
    math_mapping %>% select(node_id, item_id, purified_analysis_key, purified_direct_y1_anchor),
    by = c("node_id", "item_id")
  ) %>%
  filter(purified_direct_y1_anchor == 1) %>%
  distinct(subject, purified_analysis_key, y1_discrimination_a, y1_difficulty_b)
math_fixed_parameter_fidelity <- math_parameters %>%
  filter(fixed_y1_anchor == 1) %>%
  inner_join(math_reference, by = c("subject", "analysis_key" = "purified_analysis_key")) %>%
  group_by(subject) %>%
  summarize(
    fixed_anchor_n = n(),
    maximum_absolute_discrimination_difference = max(abs(discrimination_a - y1_discrimination_a)),
    maximum_absolute_difficulty_difference = max(abs(difficulty_b - y1_difficulty_b)),
    .groups = "drop"
  )

first_pass_flag <- function(data) {
  data %>% filter(iteration == 1) %>%
    mutate(rule_flag = inference_reliable == 1 & material_signal == 1 & statistical_signal == 1) %>%
    select(link_id, item_id, subject, link_type, rule_flag)
}
screen_comparison <- first_pass_flag(comparison_evidence)
screen_all <- first_pass_flag(all_evidence)
screen_match <- screen_comparison %>%
  inner_join(screen_all %>% select(link_id, item_id, all_rule_flag = rule_flag), by = c("link_id", "item_id"))
if (nrow(screen_match) != nrow(screen_comparison) || nrow(screen_match) != nrow(screen_all)) {
  stop("Comparison-only and all-student first-pass item-link universes differ")
}

screen_sensitivity <- bind_rows(
  screen_match %>% summarize(
    subject = "All", link_type = "All", item_link_n = n(),
    comparison_flag_n = sum(rule_flag), all_student_flag_n = sum(all_rule_flag),
    agreement_share = mean(rule_flag == all_rule_flag),
    flag_intersection_n = sum(rule_flag & all_rule_flag),
    flag_union_n = sum(rule_flag | all_rule_flag),
    flag_jaccard = flag_intersection_n / flag_union_n
  ),
  screen_match %>% group_by(subject, link_type) %>% summarize(
    item_link_n = n(), comparison_flag_n = sum(rule_flag), all_student_flag_n = sum(all_rule_flag),
    agreement_share = mean(rule_flag == all_rule_flag),
    flag_intersection_n = sum(rule_flag & all_rule_flag),
    flag_union_n = sum(rule_flag | all_rule_flag),
    flag_jaccard = if_else(flag_union_n > 0, flag_intersection_n / flag_union_n, NA_real_),
    .groups = "drop"
  )
)

strict_scores <- read_csv(
  file.path(derived_dir, "multiyear_irt_outcomes_joint_subject_pooled_mixture_all_strict_summary.csv"),
  show_col_types = FALSE
) %>%
  select(id_student_panel, year, wave, subject, administered_grade, strict_theta = theta_y1_published_z)
purified_scores <- read_csv(
  file.path(derived_dir, "multiyear_irt_outcomes_joint_subject_pooled_mixture_all_purified_strict.csv"),
  show_col_types = FALSE
) %>%
  select(id_student_panel, year, wave, subject, administered_grade,
         purified_theta = theta_y1_published_z, final_outcome_approved)
score_match <- strict_scores %>%
  inner_join(purified_scores, by = c("id_student_panel", "year", "wave", "subject", "administered_grade"))
score_sensitivity <- score_match %>%
  group_by(subject, year, wave, administered_grade) %>%
  summarize(
    student_n = n(), correlation = cor(strict_theta, purified_theta),
    mean_shift_purified_minus_strict = mean(purified_theta - strict_theta),
    rmse = sqrt(mean((purified_theta - strict_theta)^2)),
    .groups = "drop"
  ) %>% mutate(purification_profile = "broad")
core_scores <- read_csv(
  file.path(derived_dir, "multiyear_irt_outcomes_joint_subject_pooled_mixture_all_purified_andy_core.csv"),
  show_col_types = FALSE
) %>%
  select(id_student_panel, year, wave, subject, administered_grade,
         core_theta = theta_y1_published_z, core_raw_theta = theta_y1_metric,
         final_outcome_approved)
core_score_match <- strict_scores %>%
  inner_join(core_scores, by = c("id_student_panel", "year", "wave", "subject", "administered_grade"))
core_score_sensitivity <- core_score_match %>%
  group_by(subject, year, wave, administered_grade) %>%
  summarize(
    student_n = n(), correlation = cor(strict_theta, core_theta),
    mean_shift_purified_minus_strict = mean(core_theta - strict_theta),
    rmse = sqrt(mean((core_theta - strict_theta)^2)),
    .groups = "drop"
  ) %>% mutate(purification_profile = "andy_core")
math_scores <- read_csv(
  file.path(derived_dir, "multiyear_irt_outcomes_joint_subject_pooled_mixture_all_purified_andy_core_math_bridge5.csv"),
  show_col_types = FALSE
) %>%
  select(id_student_panel, year, wave, subject, administered_grade,
         math_theta = theta_y1_published_z, math_raw_theta = theta_y1_metric,
         final_outcome_approved)
math_score_match <- strict_scores %>%
  inner_join(math_scores, by = c("id_student_panel", "year", "wave", "subject", "administered_grade"))
math_score_sensitivity <- math_score_match %>%
  group_by(subject, year, wave, administered_grade) %>%
  summarize(
    student_n = n(), correlation = cor(strict_theta, math_theta),
    mean_shift_purified_minus_strict = mean(math_theta - strict_theta),
    rmse = sqrt(mean((math_theta - strict_theta)^2)),
    .groups = "drop"
  ) %>% mutate(purification_profile = "andy_core_math_bridge5")
score_sensitivity <- bind_rows(score_sensitivity, core_score_sensitivity, math_score_sensitivity) %>%
  arrange(purification_profile, subject, year, wave, as.integer(administered_grade))

treatment <- read_csv(file.path(treatment_dir, "treatment_effect_estimates.csv"), show_col_types = FALSE)
treatment_contrasts <- read_csv(file.path(treatment_dir, "outcome_treatment_effect_contrasts.csv"), show_col_types = FALSE)
plain_comparisons <- read_csv(file.path(treatment_dir, "irt_vs_plain_same_panel.csv"), show_col_types = FALSE)
ministry_headline <- read_csv(file.path(treatment_dir, "ministry_c3_headline_reconciliation.csv"), show_col_types = FALSE) %>%
  distinct(subject, ministry_estimate, ministry_std_error, ministry_n_students, ministry_n_schools)
ministry_grade <- read_csv(file.path(treatment_dir, "ministry_c3_grade_reconciliation.csv"), show_col_types = FALSE) %>%
  mutate(grade_scope = as.character(grade_scope)) %>%
  distinct(grade_scope, subject, ministry_estimate, ministry_std_error, ministry_n_students, ministry_n_schools)
treatment_headline <- treatment %>%
  filter(
    sample_variant == "listed_panel", pairing_role == "irt_target",
    score_method %in% c(
      "pooled_strict_all", "pooled_purified_strict_all",
      "pooled_purified_andy_core", "pooled_purified_math_bridge"
    ),
    cohort_scope == "Pooled_equal_weight", grade_scope == "All_grades"
  ) %>%
  select(score_method, subject, subjects_in_sample, estimate, std_error, conf_low, conf_high,
         p_value, n_students, n_pairs, estimation_status)
treatment_method_contrast <- treatment_contrasts %>%
  filter(
    sample_variant == "listed_panel",
    score_method %in% c(
      "pooled_strict_all_minus_pooled_purified_strict_all",
      "pooled_strict_all_minus_pooled_purified_andy_core",
      "pooled_strict_all_minus_pooled_purified_math_bridge"
    ),
    cohort_scope == "Pooled_equal_weight", grade_scope == "All_grades"
  ) %>%
  select(score_method, subject, subjects_in_sample, estimate_strict_minus_purified = estimate,
         std_error, n_students, n_pairs, estimation_status)
treatment_plain <- plain_comparisons %>%
  filter(
    sample_variant == "listed_panel",
    irt_method %in% c("pooled_purified_strict_all", "pooled_purified_andy_core", "pooled_purified_math_bridge"),
    cohort_scope == "Pooled_equal_weight", grade_scope == "All_grades"
  ) %>%
  select(irt_method, subject, plain_method, irt_estimate, plain_estimate,
         estimate_difference_irt_minus_plain, irt_n_students, same_regression_n)
purified_c3 <- treatment %>%
  filter(
    sample_variant == "listed_panel", pairing_role == "irt_target",
    score_method %in% c("pooled_purified_strict_all", "pooled_purified_andy_core", "pooled_purified_math_bridge"), cohort_scope == "3",
    estimation_status == "estimated_development_only", subject != "Overall"
  )
purified_ministry <- bind_rows(
  purified_c3 %>% filter(grade_scope == "All_grades") %>%
    select(score_method, subject, grade_scope, purified_estimate = estimate, purified_std_error = std_error,
           purified_n_students = n_students, purified_n_schools = n_schools) %>%
    inner_join(ministry_headline, by = "subject") %>% mutate(result_family = "headline"),
  purified_c3 %>% filter(grade_scope != "All_grades") %>%
    select(score_method, subject, grade_scope, purified_estimate = estimate, purified_std_error = std_error,
           purified_n_students = n_students, purified_n_schools = n_schools) %>%
    inner_join(ministry_grade, by = c("subject", "grade_scope")) %>% mutate(result_family = "grade")
) %>%
  mutate(
    difference_purified_minus_ministry = purified_estimate - ministry_estimate,
    coverage_status = case_when(
      result_family == "headline" & score_method == "pooled_purified_andy_core" & subject == "Arabic" ~
        "not directly comparable: purified score covers grades 3-6 only",
      result_family == "headline" & score_method == "pooled_purified_math_bridge" & subject == "Maths" ~
        "same six mathematics grades; four-anchor graph links remain provisional",
      result_family == "headline" & subject == "French" ~
        "same subject-grade coverage; sample and cleaning differ slightly",
      result_family == "grade" ~ "same subject-grade cell; sample and cleaning differ slightly",
      TRUE ~ "coverage requires review"
    )
  ) %>%
  select(result_family, score_method, subject, grade_scope, coverage_status, ministry_estimate, ministry_std_error,
         purified_estimate, purified_std_error, difference_purified_minus_ministry,
         ministry_n_students, purified_n_students, ministry_n_schools, purified_n_schools)

checks <- list()
add_check <- function(check, pass, detail) {
  checks[[length(checks) + 1L]] <<- tibble(check = check, pass = as.integer(isTRUE(pass)), detail = detail)
}
add_check("comparison_and_all_first_pass_universes_match", nrow(screen_match) == 5907, paste("rows", nrow(screen_match)))
add_check("treatment_never_used_as_dif_predictor", all(decisions$treatment_used_as_model_predictor == 0), "comparison assignment only restricts the primary sample")
add_check("no_final_anchor_approvals", all(decisions$final_link_item_approved == 0) && all(mapping$final_anchor_approved == 0) && all(cohort_overrides$final_anchor_approved == 0), "all decisions remain development-only")
add_check("mapping_unique_by_node_item", !anyDuplicated(mapping[c("node_id", "item_id")]), paste("mapping rows", nrow(mapping)))
add_check("targeted_frees_not_fixed_to_y1", all(mapping$purified_direct_y1_anchor[mapping$targeted_node_free == 1] == 0), paste("targeted rows", sum(mapping$targeted_node_free == 1)))
add_check("linked_paths_have_five_anchors", min(paths_output$path_minimum_anchor_n[paths_output$path_status == "linked_development_only"]) >= 5, paste("linked nodes", sum(paths_output$path_status == "linked_development_only")))
add_check("nonbinary_items_absent_from_dif", nrow(read_csv(file.path(comparison_dir, "multiyear_nonbinary_exclusions.csv"), show_col_types = FALSE)) == 0, "binary-only occurrence registry produced no late exclusions")
add_check("purified_scores_all_unapproved", all(purified_scores$final_outcome_approved == 0), paste("score rows", nrow(purified_scores)))
add_check("estimated_purified_scores_finite", all(is.finite(purified_scores$purified_theta)), "no nonfinite emitted scores")
add_check("two_of_three_subject_models_converged", sum(model_summary$converged == 1) == 2, paste(model_summary$subject[model_summary$converged == 1], collapse = ", "))
add_check("andy_core_mapping_unique_by_node_item", !anyDuplicated(core_mapping[c("node_id", "item_id")]), paste("mapping rows", nrow(core_mapping)))
add_check("andy_core_linked_paths_have_five_anchors", min(core_paths$path_minimum_anchor_n[core_paths$path_status == "linked_development_only"]) >= 5, paste("linked nodes", sum(core_paths$path_status == "linked_development_only")))
add_check("andy_core_all_subject_models_converged", all(core_model_summary$converged == 1), paste(core_model_summary$subject[core_model_summary$converged == 1], collapse = ", "))
add_check("andy_core_scores_all_unapproved_and_finite", all(core_scores$final_outcome_approved == 0) && all(is.finite(core_scores$core_theta)), paste("score rows", nrow(core_scores)))
add_check(
  "andy_core_fixed_y1_parameters_unchanged",
  sum(core_fixed_parameter_fidelity$fixed_anchor_n) == 255 &&
    max(core_fixed_parameter_fidelity$maximum_absolute_discrimination_difference) < 1e-12 &&
    max(core_fixed_parameter_fidelity$maximum_absolute_difficulty_difference) < 1e-12,
  paste("fixed anchors", sum(core_fixed_parameter_fidelity$fixed_anchor_n))
)
required_target_paths <- math_paths %>%
  filter(year == 3, wave %in% c("baseline", "endline"))
math_ministry_grade <- purified_ministry %>%
  filter(result_family == "grade", score_method == "pooled_purified_math_bridge", subject == "Maths")
add_check(
  "required_link_bridge_screen_is_treatment_blind",
  all(math_decisions$treatment_used_as_model_predictor == 0),
  "comparison assignment restricts the screen; treatment is never a DIF predictor"
)
add_check(
  "required_link_bridge_mapping_unique_by_node_item",
  !anyDuplicated(math_mapping[c("node_id", "item_id")]),
  paste("mapping rows", nrow(math_mapping))
)
add_check(
  "item_id_equivalence_confirmation_recorded",
  all(
    math_mapping$full_version_review_status ==
      "verified_by_project_lead_immutable_id_rule_2026_09_08"
  ) &&
    all(
      math_paths$full_version_review_status ==
        "verified_by_project_lead_immutable_id_rule_2026_09_08"
    ),
  "project-lead confirmation is propagated to every subject mapping and path"
)
add_check(
  "required_link_bridge_items_explicitly_flagged",
  sum(math_decisions$bridge_floor_retained == 1) > 0 &&
    sum(math_mapping$required_link_bridge == 1) > 0,
  paste(
    "item-link flags", sum(math_decisions$bridge_floor_retained == 1),
    "occurrence flags", sum(math_mapping$required_link_bridge == 1)
  )
)
add_check(
  "required_link_bridge_all_y3_grade_waves_linked",
  nrow(required_target_paths) == 36 &&
    all(required_target_paths$path_status == "linked_development_only") &&
    n_distinct(required_target_paths$subject) == 3 &&
    n_distinct(required_target_paths$administered_grade) == 6,
  paste("linked Year 3 subject-grade-wave nodes",
        sum(required_target_paths$path_status == "linked_development_only"), "/", nrow(required_target_paths))
)
add_check(
  "required_link_bridge_anchor_floor_respected",
  min(math_paths$path_minimum_anchor_n[math_paths$path_status == "linked_development_only"]) >= 4,
  "Every retained path edge has at least four exact-version anchors after targeted frees"
)
add_check(
  "required_link_bridge_all_subject_models_converged",
  all(math_model_summary$converged == 1),
  paste(math_model_summary$subject[math_model_summary$converged == 1], collapse = ", ")
)
add_check(
  "required_link_bridge_scores_all_unapproved_and_finite",
  all(math_scores$final_outcome_approved == 0) && all(is.finite(math_scores$math_theta)),
  paste("score rows", nrow(math_scores))
)
add_check(
  "required_link_bridge_fixed_y1_parameters_unchanged",
  sum(math_fixed_parameter_fidelity$fixed_anchor_n) == 255 &&
    max(math_fixed_parameter_fidelity$maximum_absolute_discrimination_difference) < 1e-12 &&
    max(math_fixed_parameter_fidelity$maximum_absolute_difficulty_difference) < 1e-12,
  paste("fixed anchors", sum(math_fixed_parameter_fidelity$fixed_anchor_n))
)
add_check(
  "math_bridge_ministry_all_six_grade_cells_estimated",
  nrow(math_ministry_grade) == 6 &&
    all(math_ministry_grade$purified_n_students > 0) &&
    max(abs(math_ministry_grade$difference_purified_minus_ministry)) < 0.061,
  paste(
    "cells", nrow(math_ministry_grade),
    "max absolute effect difference", round(max(abs(math_ministry_grade$difference_purified_minus_ministry)), 4)
  )
)
validation <- bind_rows(checks)

write_csv(screen_sensitivity, assert_output(file.path(comparison_dir, "screen_sample_sensitivity_summary.csv")), na = "")
write_csv(score_sensitivity, assert_output(file.path(comparison_dir, "purified_score_sensitivity_by_node.csv")), na = "")
write_csv(treatment_headline, assert_output(file.path(comparison_dir, "purified_treatment_effect_headline.csv")), na = "")
write_csv(treatment_method_contrast, assert_output(file.path(comparison_dir, "purified_treatment_method_contrast.csv")), na = "")
write_csv(treatment_plain, assert_output(file.path(comparison_dir, "purified_treatment_plain_comparison.csv")), na = "")
write_csv(purified_ministry, assert_output(file.path(comparison_dir, "purified_vs_ministry_c3.csv")), na = "")
write_csv(core_fixed_parameter_fidelity, assert_output(file.path(comparison_dir, "andy_core_fixed_y1_parameter_fidelity.csv")), na = "")
write_csv(math_fixed_parameter_fidelity, assert_output(file.path(comparison_dir, "math_bridge_fixed_y1_parameter_fidelity.csv")), na = "")
write_csv(validation, assert_output(file.path(comparison_dir, "anchor_purification_validation_checks.csv")), na = "")

overall_screen <- screen_sensitivity %>% filter(subject == "All", link_type == "All")
targeted_node_frees <- decisions %>%
  filter(robust_free, is.na(free_target_cohort) | free_target_cohort == "") %>%
  distinct(free_target_node, strict_item_version_id)
summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  validation_status = if (all(validation$pass == 1)) "pass" else "fail",
  validation_check_n = nrow(validation),
  comparison_first_pass_flag_n = overall_screen$comparison_flag_n,
  all_student_first_pass_flag_n = overall_screen$all_student_flag_n,
  item_link_classification_agreement = overall_screen$agreement_share,
  flagged_set_jaccard = overall_screen$flag_jaccard,
  final_iterative_pairwise_free_n = sum(decisions$robust_free),
  targeted_node_item_free_n = nrow(targeted_node_frees),
  targeted_cohort_item_free_n = nrow(cohort_overrides),
  linked_node_n = sum(paths_output$path_status == "linked_development_only"),
  target_wave_linked_node_n = sum(paths_output$path_status == "linked_development_only" & paths_output$wave %in% c("baseline", "endline")),
  converged_subjects = model_summary$subject[model_summary$converged == 1],
  nonconverged_subjects = model_summary$subject[model_summary$converged == 0],
  scored_node_n = sum(str_starts(node_summary$score_status, "scored_")),
  score_overlap_row_n = nrow(score_match),
  minimum_node_score_correlation = min(score_sensitivity$correlation),
  maximum_absolute_node_mean_shift = max(abs(score_sensitivity$mean_shift_purified_minus_strict)),
  maximum_node_rmse = max(score_sensitivity$rmse),
  andy_core = list(
    applied_node_item_free_n = sum(core_mapping$targeted_node_free == 1),
    linked_node_n = sum(core_paths$path_status == "linked_development_only"),
    target_wave_linked_node_n = sum(core_paths$path_status == "linked_development_only" & core_paths$wave %in% c("baseline", "endline")),
    converged_subjects = core_model_summary$subject[core_model_summary$converged == 1],
    scored_node_n = sum(str_starts(core_node_summary$score_status, "scored_")),
    score_overlap_row_n = nrow(core_score_match),
    minimum_node_score_correlation = min(core_score_sensitivity$correlation),
    maximum_absolute_node_mean_shift = max(abs(core_score_sensitivity$mean_shift_purified_minus_strict)),
    maximum_node_rmse = max(core_score_sensitivity$rmse)
  ),
  required_link_bridge = list(
    rule = "All subjects use consensus DIF; retain at least five anchors per screened link and permit four-anchor graph links after exact-version mapping",
    provisional_item_link_n = sum(math_decisions$bridge_floor_retained == 1),
    provisional_occurrence_n = sum(math_mapping$required_link_bridge == 1),
    linked_y3_subject_grade_wave_node_n = sum(required_target_paths$path_status == "linked_development_only"),
    converged_subjects = math_model_summary$subject[math_model_summary$converged == 1],
    scored_node_n = sum(str_starts(math_node_summary$score_status, "scored_")),
    score_overlap_row_n = nrow(math_score_match),
    minimum_node_score_correlation = min(math_score_sensitivity$correlation),
    maximum_absolute_node_mean_shift = max(abs(math_score_sensitivity$mean_shift_purified_minus_strict)),
    maximum_node_rmse = max(math_score_sensitivity$rmse),
    fixed_y1_anchor_n = sum(math_fixed_parameter_fidelity$fixed_anchor_n)
  ),
  treatment_result_scope = "The required-link bridge specification is designed to retain every Year 3 subject-grade-wave node; stricter and broader purification variants remain explicit sensitivity analyses.",
  status = "development_only_not_approved"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), assert_output(file.path(comparison_dir, "anchor_purification_validation_summary.json")))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
