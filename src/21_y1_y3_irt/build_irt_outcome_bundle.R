#!/usr/bin/env Rscript

# Assemble primary and robustness outcomes after estimation. The script creates
# no treatment estimates. Student identifiers appear only in derived files
# below work_root; aggregate model/correlation diagnostics are written to the
# output directory.

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
if (length(args) != 2L) {
  stop("Usage: build_irt_outcome_bundle.R config/paths.local.yml config/irt_pipeline.yml")
}
paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
specification <- yaml::read_yaml(normalizePath(args[[2]], mustWork = TRUE))
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
derived_dir <- file.path(work_root, "derived/y1_y3_irt")
output_root <- file.path(work_root, "outputs/y1_y3_irt")

is_within <- function(path, root) {
  candidate <- normalizePath(path, mustWork = FALSE); boundary <- normalizePath(root, mustWork = FALSE)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_work_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) stop("Input outside work_root: ", candidate)
  candidate
}
assert_output <- function(path) {
  candidate <- normalizePath(path, mustWork = FALSE)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Output inside source root")
  candidate
}

anchor_label <- function(anchor_mode) {
  case_when(
    anchor_mode == "purified_andy_core_math_bridge5" ~ "final_purified_math_bridge5",
    anchor_mode == "purified_andy_core" ~ "andy_core",
    anchor_mode == "purified_strict" ~ "broad_purification",
    anchor_mode == "strict_summary" ~ "strict_summary",
    anchor_mode == "provisional_id" ~ "provisional_id_stress_test",
    TRUE ~ anchor_mode
  )
}

joint_grid <- tidyr::crossing(
  anchor_mode = unlist(specification$joint_factorial$anchor_modes),
  sample_mode = unlist(specification$joint_factorial$sample_modes),
  model_scope = unlist(specification$joint_factorial$model_scopes)
) %>% mutate(role = "admissible_factorial", declared_eligible = 1L)
additional <- map_dfr(specification$additional_joint_runs, ~ tibble(
  anchor_mode = .x$anchor_mode, sample_mode = .x$sample_mode, model_scope = .x$model_scope,
  role = .x$role, declared_eligible = as.integer(isTRUE(.x$eligible))
))
joint_specs <- bind_rows(joint_grid, additional) %>% distinct(anchor_mode, sample_mode, model_scope, .keep_all = TRUE) %>%
  mutate(
    run_id = paste(model_scope, sample_mode, anchor_mode, sep = "_"),
    method_id = if_else(
      anchor_mode == "purified_andy_core_math_bridge5" & sample_mode == "all" & model_scope == "subject_pooled_mixture",
      specification$primary_method,
      paste("concurrent", str_remove(model_scope, "_mixture$"), sample_mode, anchor_label(anchor_mode), sep = "__")
    ),
    method_family = "concurrent_2pl",
    outcome_path = file.path(derived_dir, paste0("multiyear_irt_outcomes_joint_", run_id, ".csv")),
    model_path = file.path(output_root, "04_joint_multigroup", run_id, "joint_model_summary.csv")
  )

direct_specs <- tibble(anchor_mode = unlist(specification$node_link_runs$direct)) %>% mutate(
  sample_mode = "all", model_scope = "node_direct", role = "direct_fixed_y1_sensitivity", declared_eligible = 1L,
  run_id = paste0("direct_", anchor_mode), method_id = paste("direct", anchor_label(anchor_mode), sep = "__"),
  method_family = "direct_fixed_y1_2pl",
  outcome_path = file.path(derived_dir, paste0("y3_irt_outcomes_", anchor_mode, ".csv")),
  model_path = file.path(output_root, "02_y3_direct_scoring", anchor_mode, "y3_direct_fixed_anchor_model_summary.csv")
)
chained_specs <- tibble(anchor_mode = unlist(specification$node_link_runs$chained)) %>% mutate(
  sample_mode = "all", model_scope = "node_chained", role = "selected_path_sensitivity", declared_eligible = 1L,
  run_id = paste0("chained_", anchor_mode), method_id = paste("chained", anchor_label(anchor_mode), sep = "__"),
  method_family = "chained_fixed_anchor_2pl",
  outcome_path = file.path(derived_dir, paste0("multiyear_irt_outcomes_chained_", anchor_mode, ".csv")),
  model_path = file.path(output_root, "03_chained_scoring", anchor_mode, "multiyear_chained_model_summary.csv")
)
irt_specs <- bind_rows(joint_specs, direct_specs, chained_specs) %>%
  mutate(primary_method = as.integer(method_id == specification$primary_method))

read_one_method <- function(spec) {
  if (!file.exists(spec$outcome_path[[1]]) || !file.exists(spec$model_path[[1]])) {
    return(list(
      registry = spec %>% transmute(
        method_id, method_family, role, anchor_mode, sample_mode, model_scope, declared_eligible,
        primary_method, artifact_status = "missing", model_row_n = 0L, converged_n = 0L,
        warning_n = 0L, outcome_row_n = 0L, scored_node_n = 0L, eligible_for_comparison = 0L
      ), outcome = NULL
    ))
  }
  outcome <- read_csv(assert_work_input(spec$outcome_path[[1]]), show_col_types = FALSE)
  model <- read_csv(assert_work_input(spec$model_path[[1]]), show_col_types = FALSE)
  if (!"year" %in% names(outcome)) outcome$year <- 3L
  if (!"theta_y1_published_z" %in% names(outcome)) stop("Missing published-Y1 z score: ", spec$method_id[[1]])
  converged_n <- if ("converged" %in% names(model)) sum(model$converged == 1L, na.rm = TRUE) else 0L
  warning_n <- if ("calibration_status" %in% names(model)) sum(model$calibration_status == "estimated_with_warning", na.rm = TRUE) else 0L
  key <- paste(outcome$id_student_panel, outcome$year, outcome$wave, outcome$subject, outcome$administered_grade, sep = "|")
  if (anyDuplicated(key)) stop("Duplicate student-node keys in ", spec$method_id[[1]])
  treatment_like <- names(outcome)[str_detect(names(outcome), regex("treat|control|assign|intervention|pioneer", ignore_case = TRUE))]
  if (length(treatment_like)) stop("Treatment-like columns in outcome ", spec$method_id[[1]])
  eligible <- spec$declared_eligible[[1]] == 1L && converged_n > 0L && nrow(outcome) > 0L
  if (spec$primary_method[[1]] == 1L) {
    eligible <- eligible && nrow(model) == 3L && converged_n == 3L && warning_n == 0L
  }
  artifact_status <- case_when(
    spec$declared_eligible[[1]] == 0L ~ "estimated_but_quarantined_by_design",
    converged_n == 0L ~ "quarantined_no_converged_model",
    converged_n < nrow(model) ~ "partial_model_coverage",
    warning_n > 0L ~ "estimated_with_warning",
    TRUE ~ "clean_fit"
  )
  robust <- outcome %>% transmute(
    source_id = as.character(id_student_panel), year = as.integer(year), wave = as.character(wave),
    cohort = as.character(cohort), subject = as.character(subject),
    administered_grade = as.character(administered_grade), method_id = spec$method_id[[1]],
    score_family = spec$method_family[[1]], sample_variant = spec$sample_mode[[1]],
    score = as.numeric(theta_y1_published_z), raw_total = NA_real_, observed_item_n = NA_integer_,
    binary_item_n = NA_integer_, scale_status = as.character(scale_status),
    final_outcome_approved = as.integer(final_outcome_approved)
  ) %>% filter(!is.na(score))
  list(
    registry = spec %>% transmute(
      method_id, method_family, role, anchor_mode, sample_mode, model_scope, declared_eligible,
      primary_method, artifact_status = artifact_status, model_row_n = nrow(model),
      converged_n = converged_n, warning_n = warning_n, outcome_row_n = nrow(robust),
      scored_node_n = n_distinct(paste(robust$year, robust$wave, robust$subject, robust$administered_grade)),
      eligible_for_comparison = as.integer(eligible)
    ), outcome = if (eligible) robust else NULL
  )
}

read_results <- map(seq_len(nrow(irt_specs)), ~ read_one_method(irt_specs[.x, ]))
registry <- bind_rows(map(read_results, "registry"))
irt_outcomes <- bind_rows(map(read_results, "outcome"))

# Score-estimator sensitivity using the same fitted primary item and node
# models. WLE changes only the person-score estimator; it does not recalibrate
# items or alter the anchor set.
wle_source_path <- irt_specs %>%
  filter(method_id == specification$primary_method) %>%
  pull(outcome_path)
wle_source <- read_csv(assert_work_input(wle_source_path), show_col_types = FALSE)
if (!"theta_y1_published_z_wle" %in% names(wle_source)) {
  stop("Primary joint run did not export WLE sensitivity scores")
}
wle_outcome <- wle_source %>%
  transmute(
    source_id = as.character(id_student_panel), year = as.integer(year),
    wave = as.character(wave), cohort = as.character(cohort),
    subject = as.character(subject), administered_grade = as.character(administered_grade),
    method_id = "concurrent_subject_all_final_wle",
    score_family = "concurrent_2pl_wle", sample_variant = "all",
    score = as.numeric(theta_y1_published_z_wle), raw_total = NA_real_,
    observed_item_n = NA_integer_, binary_item_n = NA_integer_,
    scale_status = "release_candidate_joint_y1_metric_wle_sensitivity",
    final_outcome_approved = 0L
  ) %>%
  filter(is.finite(score))
wle_registry <- tibble(
  method_id = "concurrent_subject_all_final_wle",
  method_family = "concurrent_2pl_wle", role = "person_score_estimator_sensitivity",
  anchor_mode = "purified_andy_core_math_bridge5", sample_mode = "all",
  model_scope = "subject_pooled_mixture", declared_eligible = 1L,
  primary_method = 0L, artifact_status = "clean_fit_reuses_primary_item_model",
  model_row_n = 3L, converged_n = 3L, warning_n = 0L,
  outcome_row_n = nrow(wle_outcome),
  scored_node_n = n_distinct(paste(wle_outcome$year, wle_outcome$wave,
                                   wle_outcome$subject, wle_outcome$administered_grade)),
  eligible_for_comparison = as.integer(nrow(wle_outcome) > 0L)
)
registry <- bind_rows(registry, wle_registry)
irt_outcomes <- bind_rows(irt_outcomes, wle_outcome)

plain_path <- assert_work_input(file.path(derived_dir, "y3_plain_standardized_scores_long.csv"))
plain <- read_csv(plain_path, show_col_types = FALSE) %>%
  mutate(
    source_id = as.character(source_id), year = as.integer(year), cohort = as.character(cohort),
    administered_grade = as.character(administered_grade), final_outcome_approved = as.integer(final_outcome_approved)
  )
plain_registry <- plain %>% group_by(method_id, score_family, sample_variant) %>%
  summarise(outcome_row_n = n(), scored_node_n = n_distinct(paste(year, wave, subject, administered_grade)), .groups = "drop") %>%
  transmute(
    method_id, method_family = score_family, role = "non_irt_benchmark", anchor_mode = "not_applicable",
    sample_mode = sample_variant, model_scope = "standardized_sum", declared_eligible = 1L,
    primary_method = 0L, artifact_status = "clean_deterministic_score", model_row_n = NA_integer_,
    converged_n = NA_integer_, warning_n = 0L, outcome_row_n, scored_node_n, eligible_for_comparison = 1L
  )
registry <- bind_rows(registry, plain_registry)
robustness <- bind_rows(irt_outcomes, plain)

if (any(robustness$final_outcome_approved != 0L)) stop("A development score is incorrectly marked approved")
robust_key <- paste(robustness$source_id, robustness$year, robustness$wave, robustness$subject,
                    robustness$administered_grade, robustness$method_id, sep = "|")
if (anyDuplicated(robust_key)) stop("Duplicate keys in robustness bundle")

primary_spec <- irt_specs %>% filter(method_id == specification$primary_method)
if (nrow(primary_spec) != 1L) stop("Primary method is not uniquely declared")
if (registry$eligible_for_comparison[match(specification$primary_method, registry$method_id)] != 1L) stop("Primary method failed eligibility gates")
primary_source <- read_csv(assert_work_input(primary_spec$outcome_path[[1]]), show_col_types = FALSE) %>%
  mutate(
    primary_method = specification$primary_method,
    primary_outcome = theta_y1_published_z,
    primary_scale_definition = "subject-specific 2PL z-standardized to archived Year 1 endline comparison distribution"
  )
primary_key <- paste(primary_source$id_student_panel, primary_source$year, primary_source$wave,
                     primary_source$subject, primary_source$administered_grade, sep = "|")
if (anyDuplicated(primary_key) || any(is.na(primary_source$primary_outcome))) stop("Invalid primary outcome keys or scores")
primary_wle_source <- primary_source %>%
  filter(is.finite(theta_y1_published_z_wle)) %>%
  mutate(
    theta_y1_metric = theta_y1_metric_wle,
    se_theta_y1_metric = se_theta_y1_metric_wle,
    theta_y1_published_z = theta_y1_published_z_wle,
    se_theta_y1_published_z = se_theta_y1_published_z_wle,
    primary_method = "concurrent_subject_all_final_wle",
    primary_outcome = theta_y1_published_z_wle,
    primary_scale_definition = paste0(
      "WLE person-score sensitivity using the primary subject-specific 2PL item bank; ",
      "z-standardized to archived Year 1 endline comparison distribution"
    )
  )

out_dir <- assert_output(file.path(output_root, "06_outcome_construction"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(assert_output(derived_dir), recursive = TRUE, showWarnings = FALSE)
write_csv(registry, file.path(out_dir, "measurement_method_registry.csv"), na = "")
write_csv(primary_source, file.path(derived_dir, "multiyear_irt_outcomes_primary.csv"), na = "")
write_dta(primary_source, file.path(derived_dir, "multiyear_irt_outcomes_primary.dta"), version = 15)
write_csv(primary_wle_source, file.path(derived_dir, "multiyear_irt_outcomes_primary_wle.csv"), na = "")
write_dta(primary_wle_source, file.path(derived_dir, "multiyear_irt_outcomes_primary_wle.dta"), version = 15)
write_csv(robustness, file.path(derived_dir, "multiyear_measurement_robustness_long.csv"), na = "")
write_dta(robustness, file.path(derived_dir, "multiyear_measurement_robustness_long.dta"), version = 15)

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), primary_method = specification$primary_method,
  primary_row_n = nrow(primary_source),
  primary_node_n = n_distinct(paste(primary_source$year, primary_source$wave, primary_source$subject, primary_source$administered_grade)),
  declared_method_n = nrow(registry), comparison_eligible_method_n = sum(registry$eligible_for_comparison == 1L),
  quarantined_method_n = sum(registry$eligible_for_comparison == 0L), robustness_row_n = nrow(robustness),
  treatment_fields_exported = 0L, regression_executed = 0L,
  status = "measurement_outcomes_built_regressions_not_run"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "outcome_bundle_summary.json"))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
