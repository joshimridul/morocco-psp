#!/usr/bin/env Rscript

# Validate development IRT outcomes without exposing student identifiers.
# All written comparisons are aggregate at the wave-subject-grade node level.

suppressPackageStartupMessages({
  library(dplyr)
  library(haven)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(tidyr)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: validate_irt_sensitivity.R config/paths.local.yml")
paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
normalize_for_guard <- function(path) normalizePath(path, mustWork = FALSE)
is_within <- function(path, root) {
  candidate <- normalize_for_guard(path); boundary <- normalize_for_guard(root)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x) && !is_within(work_root, .x)))) stop("Output inside legacy root")
  candidate
}

derived <- file.path(work_root, "derived/y1_y3_irt")
output_root <- file.path(work_root, "outputs/y1_y3_irt")
run_specs <- tribble(
  ~run_id, ~method, ~outcome_file, ~model_file, ~required_converged_n,
  "direct_strict", "node_direct", "y3_irt_outcomes_strict_summary.dta", "02_y3_direct_scoring/strict_summary/y3_direct_fixed_anchor_model_summary.csv", 20L,
  "direct_provisional", "node_direct", "y3_irt_outcomes_provisional_id.dta", "02_y3_direct_scoring/provisional_id/y3_direct_fixed_anchor_model_summary.csv", 24L,
  "chained_strict", "node_chained", "y3_irt_outcomes_chained_strict_summary.dta", "03_chained_scoring/strict_summary/multiyear_chained_model_summary.csv", 37L,
  "chained_provisional", "node_chained", "y3_irt_outcomes_chained_provisional_id.dta", "03_chained_scoring/provisional_id/multiyear_chained_model_summary.csv", 38L,
  "pooled_strict_all", "subject_pooled_mixture", "y3_irt_outcomes_joint_subject_pooled_mixture_all_strict_summary.dta", "04_joint_multigroup/subject_pooled_mixture_all_strict_summary/joint_model_summary.csv", 3L,
  "pooled_strict_comparison", "subject_pooled_mixture_comparison_only", "y3_irt_outcomes_joint_subject_pooled_mixture_comparison_only_strict_summary.dta", "04_joint_multigroup/subject_pooled_mixture_comparison_only_strict_summary/joint_model_summary.csv", 3L,
  "pooled_strict_school_development", "subject_pooled_mixture_school_holdout", "y3_irt_outcomes_joint_subject_pooled_mixture_development_schools_strict_summary.dta", "04_joint_multigroup/subject_pooled_mixture_development_schools_strict_summary/joint_model_summary.csv", 1L,
  "grade_specific_strict_all", "grade_specific_mixture", "y3_irt_outcomes_joint_grade_specific_mixture_all_strict_summary.dta", "04_joint_multigroup/grade_specific_mixture_all_strict_summary/joint_model_summary.csv", 17L,
  "pooled_provisional_all", "subject_pooled_mixture", "y3_irt_outcomes_joint_subject_pooled_mixture_all_provisional_id.dta", "04_joint_multigroup/subject_pooled_mixture_all_provisional_id/joint_model_summary.csv", 3L
) %>%
  mutate(outcome_path = file.path(derived, outcome_file), model_path = file.path(output_root, model_file))

model_registry <- list(); outcome_qa <- list(); outcome_cache <- list()
for (index in seq_len(nrow(run_specs))) {
  spec <- run_specs[index, ]
  model <- read_csv(spec$model_path[[1]], show_col_types = FALSE)
  converged_n <- if ("converged" %in% names(model)) sum(model$converged == 1, na.rm = TRUE) else 0L
  warning_n <- if ("calibration_status" %in% names(model)) sum(model$calibration_status == "estimated_with_warning", na.rm = TRUE) else 0L
  model_eligible <- converged_n >= spec$required_converged_n[[1]]
  run_status <- case_when(
    !model_eligible ~ "quarantined_nonconverged_model",
    converged_n < nrow(model) ~ "development_sensitivity_partial_coverage",
    warning_n > 0 ~ "development_sensitivity_with_warning",
    TRUE ~ "development_sensitivity_clean_fit"
  )
  model_registry[[spec$run_id[[1]]]] <- tibble(
    run_id = spec$run_id[[1]], method = spec$method[[1]],
    model_row_n = nrow(model), converged_model_or_node_n = converged_n,
    required_converged_n = spec$required_converged_n[[1]], warning_n = warning_n,
    model_use_status = run_status, eligible_for_score_comparison = as.integer(model_eligible),
    final_outcome_approved = 0L
  )

  outcome_error <- ""
  outcome <- tryCatch(
    read_dta(spec$outcome_path[[1]]),
    error = function(error) {
      outcome_error <<- conditionMessage(error)
      NULL
    }
  )
  if (is.null(outcome)) {
    outcome_qa[[spec$run_id[[1]]]] <- tibble(
      run_id = spec$run_id[[1]], outcome_row_n = 0L, scored_node_n = 0L,
      duplicate_student_node_key_n = NA_integer_, missing_theta_n = NA_integer_,
      treatment_like_output_column_n = NA_integer_, all_rows_unapproved = NA_integer_,
      outcome_artifact_readable = 0L, outcome_read_error = outcome_error,
      structural_qa_pass = 0L, model_use_status = run_status
    )
    next
  }
  key <- paste(outcome$id_student_panel, outcome$wave, outcome$subject, outcome$administered_grade, sep = "|")
  treatment_columns <- names(outcome)[str_detect(names(outcome), regex("treat|control|assign|intervention|pioneer", ignore_case = TRUE))]
  qa_pass <- sum(duplicated(key)) == 0 && sum(is.na(outcome$theta_y1_metric)) == 0 &&
    length(treatment_columns) == 0 && all(outcome$final_outcome_approved == 0)
  outcome_qa[[spec$run_id[[1]]]] <- tibble(
    run_id = spec$run_id[[1]], outcome_row_n = nrow(outcome),
    scored_node_n = n_distinct(paste(outcome$wave, outcome$subject, outcome$administered_grade)),
    duplicate_student_node_key_n = sum(duplicated(key)),
    missing_theta_n = sum(is.na(outcome$theta_y1_metric)),
    treatment_like_output_column_n = length(treatment_columns),
    all_rows_unapproved = as.integer(all(outcome$final_outcome_approved == 0)),
    outcome_artifact_readable = 1L, outcome_read_error = "",
    structural_qa_pass = as.integer(qa_pass),
    model_use_status = run_status
  )
  if (model_eligible) {
    validation_split_value <- if ("validation_split" %in% names(outcome)) {
      as.character(outcome$validation_split)
    } else {
      rep("not_applicable", nrow(outcome))
    }
    outcome_cache[[spec$run_id[[1]]]] <- outcome %>%
      transmute(
        id_student_panel = as.character(id_student_panel), wave, subject,
        administered_grade = as.character(administered_grade),
        theta = theta_y1_metric,
        validation_split = validation_split_value
      )
  }
}

comparison_specs <- tribble(
  ~reference_run, ~comparison_run,
  "chained_strict", "direct_strict",
  "chained_strict", "direct_provisional",
  "chained_strict", "chained_provisional",
  "chained_strict", "pooled_strict_all",
  "chained_strict", "pooled_strict_comparison",
  "chained_strict", "grade_specific_strict_all",
  "chained_strict", "pooled_strict_school_development",
  "pooled_strict_all", "pooled_strict_school_development",
  "pooled_strict_all", "pooled_strict_comparison"
)
comparison_rows <- list()
for (index in seq_len(nrow(comparison_specs))) {
  reference_name <- comparison_specs$reference_run[index]
  comparison_name <- comparison_specs$comparison_run[index]
  if (is.null(outcome_cache[[reference_name]]) || is.null(outcome_cache[[comparison_name]])) next
  reference <- outcome_cache[[reference_name]] %>%
    select(-validation_split) %>% rename(theta_reference = theta)
  comparison <- outcome_cache[[comparison_name]] %>%
    rename(theta_comparison = theta)
  joined <- inner_join(
    reference, comparison,
    by = c("id_student_panel", "wave", "subject", "administered_grade")
  )
  if (comparison_name == "pooled_strict_school_development") {
    joined <- joined %>% filter(validation_split == "validation")
  }
  aggregate <- joined %>%
    group_by(wave, subject, administered_grade) %>%
    summarise(
      common_student_n = n(),
      score_correlation = cor(theta_reference, theta_comparison),
      mean_difference_comparison_minus_reference = mean(theta_comparison - theta_reference),
      sd_difference_comparison_minus_reference = sd(theta_comparison) - sd(theta_reference),
      rmse = sqrt(mean((theta_comparison - theta_reference)^2)),
      .groups = "drop"
    ) %>%
    mutate(
      reference_run = reference_name, comparison_run = comparison_name,
      correlation_below_0_98_warning = as.integer(score_correlation < 0.98),
      absolute_mean_difference_above_0_25_warning = as.integer(abs(mean_difference_comparison_minus_reference) > 0.25),
      rmse_above_0_35_warning = as.integer(rmse > 0.35),
      thresholds_are_warning_flags_only = 1L
    ) %>%
    select(reference_run, comparison_run, everything())
  comparison_rows[[paste(reference_name, comparison_name, sep = "|")]] <- aggregate
}
sensitivity <- bind_rows(comparison_rows)

# Fixed-parameter fidelity for the chained models.
occurrences <- read_csv(file.path(output_root, "01_multiyear_link_graph/multiyear_item_occurrence_manifest.csv"), show_col_types = FALSE)
y2_registry <- read_csv(file.path(derived, "y2_operational_item_registry.csv"), show_col_types = FALSE) %>%
  mutate(administered_grade = as.character(administered_grade))
y2_occurrence_check <- occurrences %>%
  filter(year == 2L) %>%
  mutate(administered_grade = as.character(administered_grade)) %>%
  left_join(
    y2_registry %>%
      select(wave, subject, administered_grade, item_id, binary_irt_eligible),
    by = c("wave", "subject", "administered_grade", "item_id")
  )
binary_contract <- tibble(
  registered_y2_node_item_n = nrow(y2_registry),
  binary_irt_eligible_y2_node_item_n = sum(y2_registry$binary_irt_eligible == 1),
  nonbinary_excluded_y2_node_item_n = sum(y2_registry$binary_irt_eligible == 0),
  modeled_variable_y2_node_item_n = nrow(y2_occurrence_check),
  modeled_y2_node_item_missing_registry_n = sum(is.na(y2_occurrence_check$binary_irt_eligible)),
  modeled_nonbinary_y2_node_item_n = sum(y2_occurrence_check$binary_irt_eligible == 0, na.rm = TRUE),
  binary_response_contract_pass = as.integer(
    sum(is.na(y2_occurrence_check$binary_irt_eligible)) == 0 &&
      sum(y2_occurrence_check$binary_irt_eligible == 0, na.rm = TRUE) == 0
  ),
  scoring_contract = "Observed 1 is correct; observed 0 and tagged .a are incorrect; untagged system missing remains missing; observed values outside {0,1} are excluded from 2PL IRT."
)
if (binary_contract$binary_response_contract_pass[[1]] != 1L) {
  stop("The multi-year occurrence manifest violates the binary response contract")
}
fidelity_rows <- list()
for (mode in c("strict_summary", "provisional_id")) {
  model_path <- file.path(output_root, "03_chained_scoring", mode, "multiyear_chained_model_summary.csv")
  parameter_path <- file.path(output_root, "03_chained_scoring", mode, "multiyear_chained_item_parameters.csv")
  models <- read_csv(model_path, show_col_types = FALSE)
  parameters <- read_csv(parameter_path, show_col_types = FALSE)
  fixed <- parameters %>% filter(fixed_anchor == 1) %>%
    left_join(models %>% select(model_id, parent_node_id), by = "model_id")
  direct <- fixed %>% filter(anchor_source == "fixed_y1_reference") %>%
    left_join(
      occurrences %>% select(node_id, item_id, y1_discrimination_a, y1_difficulty_b) %>% distinct(),
      by = c("model_id" = "node_id", "item_id")
    )
  bridge <- fixed %>% filter(anchor_source == "fixed_parent_bridge_parameters") %>%
    left_join(
      parameters %>% select(parent_node_id = model_id, item_id, parent_a = discrimination_a, parent_b = difficulty_b),
      by = c("parent_node_id", "item_id")
    )
  fidelity_rows[[paste(mode, "direct", sep = "|")]] <- tibble(
    anchor_mode = mode, anchor_source = "fixed_y1_reference", fixed_parameter_row_n = nrow(direct),
    unmatched_reference_parameter_n = sum(is.na(direct$y1_discrimination_a)),
    max_abs_discrimination_difference = max(abs(direct$discrimination_a - direct$y1_discrimination_a), na.rm = TRUE),
    max_abs_difficulty_difference = max(abs(direct$difficulty_b - direct$y1_difficulty_b), na.rm = TRUE)
  )
  fidelity_rows[[paste(mode, "bridge", sep = "|")]] <- tibble(
    anchor_mode = mode, anchor_source = "fixed_parent_bridge_parameters", fixed_parameter_row_n = nrow(bridge),
    unmatched_reference_parameter_n = sum(is.na(bridge$parent_a)),
    max_abs_discrimination_difference = max(abs(bridge$discrimination_a - bridge$parent_a), na.rm = TRUE),
    max_abs_difficulty_difference = max(abs(bridge$difficulty_b - bridge$parent_b), na.rm = TRUE)
  )
}
fidelity <- bind_rows(fidelity_rows)

out_dir <- assert_output(file.path(output_root, "05_validation"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(bind_rows(model_registry), file.path(out_dir, "irt_model_run_registry.csv"), na = "")
write_csv(bind_rows(outcome_qa), file.path(out_dir, "irt_outcome_structural_qa.csv"), na = "")
write_csv(sensitivity, file.path(out_dir, "irt_node_score_sensitivity.csv"), na = "")
write_csv(fidelity, file.path(out_dir, "irt_fixed_parameter_fidelity.csv"), na = "")
write_csv(binary_contract, file.path(out_dir, "irt_binary_response_contract.csv"), na = "")

blocking_issues <- tribble(
  ~issue_id, ~severity, ~status, ~issue, ~scientific_consequence, ~provisional_action,
  "IRT-LINK-001", "high", "open", "Three strict Year 3 mathematics nodes have no automated path with at least five anchors per edge.", "A complete Year 3 common-scale outcome cannot yet be constructed from strict automated version evidence.", "Leave the nodes unscored and complete manual version review or redesign the path.",
  "IRT-VERSION-001", "high", "open", "Prompt-summary hashes do not establish full prompt, stimulus, options, key/rubric, administration, scoring, layout, and exposure invariance.", "Undetected item drift can move scale locations and bias longitudinal comparisons.", "Complete the selected-path version review queue before approving anchors.",
  "IRT-SOURCE-001", "high", "requires_collaborator_confirmation", "Canonical Year 2 and Year 3 response and item-map sources are not confirmed.", "A later canonical-source change could alter responses, form membership, or scoring.", "Confirm the exact registered hashes before freezing outcomes.",
  "IRT-MODEL-001", "high", "open", "All three pooled provisional-ID subject models hit the iteration cap.", "The ID-only pooled specification is not a valid scoring sensitivity result.", "Quarantine the run and resolve version conflicts instead of increasing iterations mechanically.",
  "IRT-PATH-001", "high", "open", "Strict chained and pooled model locations differ materially on long-path lower-grade Arabic and mathematics nodes.", "Matched-DiD effect magnitudes could depend on the link path even when student rankings are stable.", "Resolve selected anchor versions and compare alternate defensible paths before freezing the metric.",
  "IRT-MGROUP-001", "medium", "open", "The unrestricted cohort-level multi-group fits exceeded the bounded run window.", "The efficient pooled-mixture model does not fully replace a model with free cohort-specific latent distributions during item calibration.", "Retry the implemented multi-group specification after reducing only scientifically redundant grouping or using a documented high-compute run.",
  "IRT-DIF-001", "medium", "pending_measurement_freeze", "Treatment-related DIF has not been run on a frozen item and anchor system.", "Treatment-related item drift remains an untested causal-measurement sensitivity.", "Run treatment DIF only after treatment-blind item and anchor rules are locked.",
  "IRT-HOLDOUT-001", "medium", "open", "The strict school-development pooled French and mathematics calibrations hit the iteration cap.", "Out-of-sample score stability is currently available for Arabic only.", "Resolve the French and mathematics calibrations or use a pre-specified cohort-held-out alternative before freezing scores."
)
write_csv(blocking_issues, file.path(out_dir, "irt_blocking_issues.csv"), na = "")

strict_pair <- sensitivity %>% filter(reference_run == "chained_strict", comparison_run %in% c("pooled_strict_all", "pooled_strict_comparison"))
summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  run_n = nrow(run_specs),
  structurally_clean_outcome_run_n = sum(bind_rows(outcome_qa)$structural_qa_pass == 1),
  quarantined_run_n = sum(bind_rows(model_registry)$eligible_for_score_comparison == 0),
  sensitivity_node_comparison_n = nrow(sensitivity),
  sensitivity_correlation_warning_n = sum(sensitivity$correlation_below_0_98_warning, na.rm = TRUE),
  sensitivity_location_warning_n = sum(sensitivity$absolute_mean_difference_above_0_25_warning, na.rm = TRUE),
  sensitivity_rmse_warning_n = sum(sensitivity$rmse_above_0_35_warning, na.rm = TRUE),
  strict_chained_vs_pooled_min_correlation = min(strict_pair$score_correlation, na.rm = TRUE),
  fixed_parameter_max_abs_difference = max(
    fidelity$max_abs_discrimination_difference,
    fidelity$max_abs_difficulty_difference,
    na.rm = TRUE
  ),
  binary_response_contract_pass = binary_contract$binary_response_contract_pass[[1]] == 1L,
  nonbinary_y2_node_items_excluded_n = binary_contract$nonbinary_excluded_y2_node_item_n[[1]],
  overall_assessment = "needs_revision_before_final_outcome_freeze",
  final_outcome_approved = FALSE,
  blocking_reasons = c(
    "three strict Year 3 mathematics nodes lack a five-item fully automated link path",
    "full item-version and exposure review is incomplete",
    "canonical Year 2 and Year 3 sources are not collaborator-confirmed",
    "the pooled provisional-ID specification did not converge",
    "school-held-out pooled French and mathematics did not converge",
    "treatment-related DIF remains a post-freeze sensitivity"
  ),
  blocking_issue_n = nrow(blocking_issues),
  note = "Numerical thresholds are warning flags, not automatic item or model decisions."
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "irt_validation_summary.json"))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
