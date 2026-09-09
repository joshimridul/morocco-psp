#!/usr/bin/env Rscript

# Independent, fail-closed validation of the measurement build. Checks are
# aggregate and no student identifier is written to the validation directory.

suppressPackageStartupMessages({
  library(digest)
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
if (length(args) != 2L) stop("Usage: validate_irt_pipeline_adversarial.R config/paths.local.yml config/irt_pipeline.yml")
local_config_path <- normalizePath(args[[1]], mustWork = TRUE)
paths <- yaml::read_yaml(local_config_path)$dropbox
analysis_config <- yaml::read_yaml(file.path(dirname(local_config_path), "analysis.yml"))
discrimination_upper_bound <- analysis_config$irt_optimization$estimated_discrimination_upper_bound
specification <- yaml::read_yaml(normalizePath(args[[2]], mustWork = TRUE))
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
output_root <- file.path(work_root, "outputs/y1_y3_irt")
derived_dir <- file.path(work_root, "derived/y1_y3_irt")

is_within <- function(path, root) {
  candidate <- normalizePath(path, mustWork = FALSE); boundary <- normalizePath(root, mustWork = FALSE)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_work_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) stop("Validation input outside work_root: ", candidate)
  candidate
}
assert_output <- function(path) {
  candidate <- normalizePath(path, mustWork = FALSE)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x) && !is_within(work_root, .x)))) stop("Output inside source root")
  candidate
}
read_work_csv <- function(path) read_csv(assert_work_input(path), show_col_types = FALSE)
sha256_file <- function(path) digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)

check_rows <- list()
add_check <- function(check_id, area, severity, passed, observed, expected, implication) {
  check_rows[[length(check_rows) + 1L]] <<- tibble(
    check_id = check_id, area = area, severity = severity,
    status = if (isTRUE(passed)) "pass" else if (severity == "warning") "warning" else "fail",
    observed = as.character(observed), expected = as.character(expected), implication = implication
  )
}

method_registry <- read_work_csv(file.path(output_root, "06_outcome_construction/measurement_method_registry.csv"))
primary <- read_work_csv(file.path(derived_dir, "multiyear_irt_outcomes_primary.csv"))
robustness <- read_work_csv(file.path(derived_dir, "multiyear_measurement_robustness_long.csv"))
primary_model <- read_work_csv(file.path(
  output_root, "04_joint_multigroup/subject_pooled_mixture_all_purified_andy_core_math_bridge5/joint_model_summary.csv"
))
primary_parameters <- read_work_csv(file.path(
  output_root, "04_joint_multigroup/subject_pooled_mixture_all_purified_andy_core_math_bridge5/joint_item_parameters.csv"
))
mapping <- read_work_csv(file.path(derived_dir, "multiyear_purified_andy_core_math_bridge5_occurrence_mapping.csv"))
occurrences <- read_work_csv(file.path(output_root, "01_multiyear_link_graph/multiyear_item_occurrence_manifest.csv"))
selected_paths <- read_work_csv(file.path(
  output_root, "05_anchor_purification/comparison_only/multiyear_andy_core_math_bridge5_purified_selected_paths.csv"
))
y2_registry <- read_work_csv(file.path(derived_dir, "y2_operational_item_registry.csv"))
y3_manifest <- read_work_csv(file.path(output_root, "01_link_design/y3_y1_anchor_manifest.csv"))
plain_checks <- read_work_csv(file.path(output_root, "06_outcome_construction/plain_scores/plain_score_standardization_checks.csv"))
plain_constants <- read_work_csv(file.path(output_root, "06_outcome_construction/plain_scores/plain_score_standardization_constants.csv"))
plain_scores <- read_work_csv(file.path(derived_dir, "y3_plain_standardized_scores_long.csv"))
plain_audit <- read_work_csv(file.path(output_root, "06_outcome_construction/plain_scores/plain_score_item_and_duplicate_audit.csv"))
node_pairwise <- read_work_csv(file.path(output_root, "06_outcome_construction/correlations/measurement_method_node_pairwise_diagnostics.csv"))
primary_diagnostics <- read_work_csv(file.path(
  output_root, "04_joint_multigroup/subject_pooled_mixture_all_purified_andy_core_math_bridge5/primary_diagnostic_summary.csv"
))
primary_duplicate_audit <- read_work_csv(file.path(
  output_root, "04_joint_multigroup/subject_pooled_mixture_all_purified_andy_core_math_bridge5/joint_duplicate_resolution_audit.csv"
))
pipeline_manifest <- read_work_csv(file.path(output_root, "00_pipeline/latest_pipeline_step_manifest.csv"))
frozen_hashes <- read_work_csv(file.path(output_root, "00_pipeline/frozen_y1_reference_hashes.csv"))
core_source_hashes <- read_work_csv(file.path(output_root, "00_pipeline/core_response_source_hashes.csv"))

# Configuration and scope checks.
add_check("CFG-001", "specification", "critical", isTRUE(specification$rules$binary_items_only), specification$rules$binary_items_only, TRUE, "Nonbinary items must not enter 2PL calibration.")
add_check("CFG-002", "specification", "critical", identical(specification$rules$treatment_used_for_item_selection, FALSE), specification$rules$treatment_used_for_item_selection, FALSE, "Treatment effects cannot determine item retention.")
add_check("CFG-003", "specification", "critical", isTRUE(specification$rules$preserve_y1_item_parameters), specification$rules$preserve_y1_item_parameters, TRUE, "Archived Year 1 parameters define the reference metric.")
add_check("CFG-004", "specification", "critical", identical(specification$rules$y1_reference_population, "endline_comparison"), specification$rules$y1_reference_population, "endline_comparison", "Year 1 baseline is not the standardization reference.")
add_check("SCOPE-001", "scope", "critical", !any(str_detect(pipeline_manifest$command, "src/22_treatment_effects|run_ministry|treatment_sensitivity")), sum(str_detect(pipeline_manifest$command, "src/22_treatment_effects|run_ministry|treatment_sensitivity")), 0, "This build must stop before regressions.")

# Frozen reference integrity and exact fixed-parameter fidelity.
y1_reference_paths <- file.path(
  work_root, "outputs/y1_y3_irt/00_y1_reference/ster_probe",
  c("y1_arabic_item_parameters.csv", "y1_french_item_parameters.csv", "y1_maths_item_parameters.csv")
)
current_hashes <- setNames(map_chr(y1_reference_paths, sha256_file), basename(y1_reference_paths))
recorded_hashes <- setNames(frozen_hashes$sha256, frozen_hashes$reference_file)
hash_match <- length(recorded_hashes) == 3L && all(current_hashes[names(recorded_hashes)] == recorded_hashes)
add_check("Y1-001", "lineage", "critical", hash_match, sum(current_hashes[names(recorded_hashes)] == recorded_hashes), 3, "Frozen Year 1 parameter files must not change during the build.")
core_source_paths <- map2_chr(core_source_hashes$root_alias, core_source_hashes$relative_path,
                              ~ normalizePath(file.path(paths[[.x]], .y), mustWork = TRUE))
core_current_hashes <- map_chr(core_source_paths, sha256_file)
add_check("LINEAGE-000", "lineage", "critical", all(core_current_hashes == core_source_hashes$sha256), sum(core_current_hashes == core_source_hashes$sha256), nrow(core_source_hashes), "All six core response sources must remain byte-identical throughout the run.")

archived_parameters <- bind_rows(
  read_work_csv(y1_reference_paths[[1]]) %>% mutate(subject = "Arabic"),
  read_work_csv(y1_reference_paths[[2]]) %>% mutate(subject = "French"),
  read_work_csv(y1_reference_paths[[3]]) %>% mutate(subject = "Maths")
) %>% transmute(
  subject, item_id, y1_discrimination_a = as.numeric(a),
  y1_difficulty_b = as.numeric(b)
)
direct_reference <- mapping %>% filter(purified_direct_y1_anchor == 1L) %>%
  select(item_id, subject, purified_analysis_key) %>%
  inner_join(archived_parameters, by = c("subject", "item_id")) %>%
  transmute(subject, analysis_key = purified_analysis_key,
            y1_discrimination_a, y1_difficulty_b) %>%
  distinct()
reference_consistency <- direct_reference %>% group_by(subject, analysis_key) %>%
  summarise(a_n = n_distinct(y1_discrimination_a), b_n = n_distinct(y1_difficulty_b), .groups = "drop")
fixed_check <- primary_parameters %>% filter(fixed_y1_anchor == 1L) %>%
  left_join(direct_reference, by = c("subject", "analysis_key")) %>%
  mutate(a_difference = abs(discrimination_a - y1_discrimination_a), b_difference = abs(difficulty_b - y1_difficulty_b))
fixed_expected <- c(Arabic = 104L, French = 85L, Maths = 66L)
fixed_observed <- primary_parameters %>% filter(fixed_y1_anchor == 1L) %>% count(subject) %>%
  deframe()
add_check("Y1-002", "parameter_fidelity", "critical", all(reference_consistency$a_n == 1L & reference_consistency$b_n == 1L), sum(reference_consistency$a_n > 1L | reference_consistency$b_n > 1L), 0, "Each frozen analysis key must map to one Year 1 parameter pair.")
add_check("Y1-003", "parameter_fidelity", "critical", all(fixed_observed[names(fixed_expected)] == fixed_expected), paste(fixed_observed, collapse = ";"), paste(fixed_expected, collapse = ";"), "All 255 archived fixed item parameters must be retained.")
add_check("Y1-004", "parameter_fidelity", "critical", nrow(fixed_check) > 0L && !any(is.na(fixed_check$y1_discrimination_a)) && max(fixed_check$a_difference) < 1e-10 && max(fixed_check$b_difference) < 1e-10, paste(max(fixed_check$a_difference, na.rm = TRUE), max(fixed_check$b_difference, na.rm = TRUE), sep = ";"), "both < 1e-10", "Estimated primary anchors must equal archived Year 1 parameters exactly.")

# Model convergence and construction checks.
add_check("FIT-001", "model", "critical", nrow(primary_model) == 3L && all(primary_model$converged == 1L), paste(nrow(primary_model), sum(primary_model$converged == 1L), sep = "/"), "3/3", "Every subject calibration must converge.")
add_check("FIT-002", "model", "critical", all(primary_model$calibration_status == "estimated_development_only") && all(is.na(primary_model$warning) | primary_model$warning == ""), sum(primary_model$calibration_status != "estimated_development_only"), 0, "Primary calibration must be warning-free.")
add_check("FIT-003", "model", "critical", all(primary_model$model_scope == "subject_pooled_mixture" & primary_model$sample_mode == "all" & primary_model$anchor_mode == "purified_andy_core_math_bridge5"), paste(unique(primary_model$model_scope), unique(primary_model$sample_mode), unique(primary_model$anchor_mode), sep = ";"), "subject_pooled_mixture;all;purified_andy_core_math_bridge5", "The saved primary outcome must implement the frozen primary specification.")
add_check("FIT-004", "model_diagnostics", "warning", nrow(primary_diagnostics) == 3L && all(primary_diagnostics$item_fit_tested_n > 0L) && all(primary_diagnostics$global_fit_node_n > 0L), paste(nrow(primary_diagnostics), sum(primary_diagnostics$item_fit_tested_n), sum(primary_diagnostics$global_fit_node_n), sep = "/"), "3 subjects/positive item checks/positive node checks", "Missing-data-compatible item fit and within-test global fit diagnostics must be produced for every subject.")
add_check("FIT-005", "model_diagnostics", "warning", all(primary_diagnostics$max_abs_q3 <= 0.20, na.rm = TRUE), max(primary_diagnostics$max_abs_q3, na.rm = TRUE), "<=0.20", "Large residual item-pair associations can indicate local dependence or an unmodeled testlet.")
add_check("FIT-006", "model_diagnostics", "warning", all(primary_diagnostics$item_fit_warning_n == 0L), paste(primary_diagnostics$subject, primary_diagnostics$item_fit_warning_n, sep = "=", collapse = ";"), 0, "Item-fit flags identify questions for review; they are not automatic exclusion rules.")
estimated_parameters <- primary_parameters %>% filter(fixed_y1_anchor == 0L)
at_discrimination_bound <- estimated_parameters %>%
  filter(discrimination_a >= discrimination_upper_bound - 1e-6)
add_check("FIT-007", "optimization", "critical", max(estimated_parameters$discrimination_a) <= discrimination_upper_bound + 1e-8, max(estimated_parameters$discrimination_a), paste0("<=", discrimination_upper_bound), "Freely estimated discrimination parameters must obey the declared finite bound; fixed Year 1 values are exempt and checked separately.")
add_check("FIT-008", "optimization", "warning", nrow(at_discrimination_bound) == 0L, nrow(at_discrimination_bound), 0, "Boundary estimates identify near-separated items. They do not alter fixed Year 1 parameters, but their count must be disclosed and the unbounded nonconvergence retained in the audit trail.")

primary_key <- paste(primary$id_student_panel, primary$year, primary$wave, primary$subject, primary$administered_grade, sep = "|")
robust_key <- paste(robustness$source_id, robustness$year, robustness$wave, robustness$subject, robustness$administered_grade, robustness$method_id, sep = "|")
add_check("DATA-001", "grain", "critical", !anyDuplicated(primary_key), sum(duplicated(primary_key)), 0, "Primary outcome grain is one student-node row.")
add_check("DATA-002", "grain", "critical", !anyDuplicated(robust_key), sum(duplicated(robust_key)), 0, "Robustness outcome grain is one student-node-method row.")
add_check("DATA-003", "completeness", "critical", !any(is.na(primary$primary_outcome)), sum(is.na(primary$primary_outcome)), 0, "The primary saved outcome cannot contain missing scores.")
treatment_fields <- names(primary)[str_detect(names(primary), regex("treat|control|assign|intervention|pioneer", ignore_case = TRUE))]
robust_treatment_fields <- names(robustness)[str_detect(names(robustness), regex("treat|control|assign|intervention|pioneer", ignore_case = TRUE))]
add_check("DATA-004", "leakage", "critical", length(treatment_fields) == 0L && length(robust_treatment_fields) == 0L, length(c(treatment_fields, robust_treatment_fields)), 0, "Treatment metadata must not leak into derived measurement outcomes.")
add_check("DATA-005", "status", "critical", all(primary$final_outcome_approved == 0L) && all(robustness$final_outcome_approved == 0L), sum(primary$final_outcome_approved != 0L) + sum(robustness$final_outcome_approved != 0L), 0, "Development outputs cannot silently claim final approval.")

target_nodes <- selected_paths %>% filter(year %in% c(2L, 3L), wave %in% c("baseline", "endline"), path_status == "linked_development_only") %>%
  transmute(node = paste(year, wave, subject, administered_grade, sep = "|")) %>% distinct()
scored_nodes <- primary %>% transmute(node = paste(year, wave, subject, administered_grade, sep = "|")) %>% distinct()
unscored <- anti_join(target_nodes, scored_nodes, by = "node")
add_check("DATA-006", "coverage", "critical", nrow(unscored) == 0L, nrow(unscored), 0, "Every linked baseline/endline node must receive a primary score.")
add_check("DATA-007", "coverage", "critical", all(c("Arabic", "French", "Maths") %in% unique(primary$subject)), paste(sort(unique(primary$subject)), collapse = ";"), "Arabic;French;Maths", "Subjects must remain separate and all be present.")
add_check("DATA-008", "deduplication", "critical", all(primary_duplicate_audit$source_row_n == primary_duplicate_audit$retained_row_n + primary_duplicate_audit$removed_duplicate_row_n), sum(primary_duplicate_audit$source_row_n - primary_duplicate_audit$retained_row_n - primary_duplicate_audit$removed_duplicate_row_n), 0, "Every removed duplicate row must be explicitly counted under the deterministic resolution rule.")
add_check("DATA-009", "person_scoring", "critical", all(is.finite(primary$theta_y1_published_z_wle)), sum(!is.finite(primary$theta_y1_published_z_wle)), 0, "Every preferred-model record must also receive the prespecified WLE sensitivity score.")

# Binary-item contract.
y2_occurrence <- occurrences %>% filter(year == 2L) %>%
  mutate(administered_grade = as.character(administered_grade)) %>%
  left_join(y2_registry %>% mutate(administered_grade = as.character(administered_grade)) %>%
              select(wave, subject, administered_grade, item_id, binary_irt_eligible),
            by = c("wave", "subject", "administered_grade", "item_id"))
add_check("ITEM-001", "response_format", "critical", !any(is.na(y2_occurrence$binary_irt_eligible)) && !any(y2_occurrence$binary_irt_eligible == 0L), sum(is.na(y2_occurrence$binary_irt_eligible) | y2_occurrence$binary_irt_eligible == 0L), 0, "No nonbinary Year 2 occurrence may enter the IRT graph.")
add_check("ITEM-002", "response_format", "critical", all(y3_manifest$item_type == "binary"), sum(y3_manifest$item_type != "binary"), 0, "The Year 3 IRT manifest must contain binary items only.")
plain_partition_valid <- all(
  plain_audit$included_binary_item_n + plain_audit$observed_nonbinary_item_n_excluded ==
    plain_audit$manifest_binary_item_n
)
add_check("ITEM-003", "response_format", "critical", plain_partition_valid, sum(!plain_partition_valid), 0, "Every manifest item must be classified, and any observed nonbinary item must be excluded from plain-score construction.")
has_testlet_registry <- any(c("stimulus_id", "testlet_id") %in% names(occurrences))
add_check("ITEM-004", "testlet_structure", "warning", has_testlet_registry, has_testlet_registry, TRUE, "No stimulus/testlet identifier is available in the harmonized occurrence registry; residual local-dependence diagnostics are reported, but substantive testlet verification remains a documentation gate.")

# Method registry and plain-score standardization.
missing_methods <- method_registry %>% filter(artifact_status == "missing")
add_check("GRID-001", "robustness_grid", "critical", nrow(missing_methods) == 0L, nrow(missing_methods), 0, "Every declared measurement specification must leave an auditable artifact.")
primary_registry <- method_registry %>% filter(method_id == specification$primary_method)
add_check("GRID-002", "robustness_grid", "critical", nrow(primary_registry) == 1L && primary_registry$eligible_for_comparison == 1L, paste(nrow(primary_registry), sum(primary_registry$eligible_for_comparison), sep = "/"), "1/1", "Primary method must be unique and eligible.")
provisional_registry <- method_registry %>% filter(anchor_mode == "provisional_id_quarantined" | anchor_mode == "provisional_id")
permissive_joint <- method_registry %>% filter(role == "deliberately_permissive_anchor_stress_test")
add_check("GRID-003", "robustness_grid", "critical", nrow(permissive_joint) == 1L && permissive_joint$eligible_for_comparison == 0L, paste(nrow(permissive_joint), sum(permissive_joint$eligible_for_comparison), sep = "/"), "1/0", "The deliberately permissive joint model must remain quarantined.")
add_check("SUM-001", "standardization", "critical", max(abs(plain_checks$achieved_mean)) < 1e-10, max(abs(plain_checks$achieved_mean)), "<1e-10", "Comparison-group standardized sum-score means must equal zero.")
add_check("SUM-002", "standardization", "critical", max(abs(plain_checks$achieved_sd - 1)) < 1e-10, max(abs(plain_checks$achieved_sd - 1)), "<1e-10", "Comparison-group standardized sum-score SDs must equal one.")
plain_code_recomputed <- plain_scores %>%
  filter(str_starts(method_id, "plain_code__")) %>%
  left_join(
    plain_constants %>%
      filter(score_method_base == "plain_code") %>%
      select(cohort, wave, subject, sample_variant, mean, sd),
    by = c("cohort", "wave", "subject", "sample_variant")
  )
plain_grade_recomputed <- plain_scores %>%
  filter(str_starts(method_id, "plain_report_grade__")) %>%
  left_join(
    plain_constants %>%
      filter(score_method_base == "plain_report_grade") %>%
      select(cohort, wave, subject, administered_grade, sample_variant, mean, sd),
    by = c("cohort", "wave", "subject", "administered_grade", "sample_variant")
  )
plain_recomputed <- bind_rows(plain_code_recomputed, plain_grade_recomputed) %>%
  mutate(recomputed_score = (raw_total - mean) / sd,
         absolute_difference = abs(score - recomputed_score))
add_check("SUM-003", "standardization", "critical", nrow(plain_recomputed) == nrow(plain_scores) && max(plain_recomputed$absolute_difference, na.rm = TRUE) < 1e-12, max(plain_recomputed$absolute_difference, na.rm = TRUE), "<1e-12", "Saved standardized sum scores must equal an independent reconstruction from raw totals and archived constants.")

# Correlation artifact integrity and interpretation warnings.
read_matrix <- function(name) {
  table <- read_work_csv(file.path(output_root, "06_outcome_construction/correlations", name))
  matrix_value <- as.matrix(table[, -1, drop = FALSE]); storage.mode(matrix_value) <- "double"
  rownames(matrix_value) <- table$method_id
  matrix_value
}
level_matrix <- read_matrix("correlation_matrix_y3_levels_within_node_pearson.csv")
change_matrix <- read_matrix("correlation_matrix_y3_changes_within_grade_pearson.csv")
matrix_integrity <- function(x) {
  identical(rownames(x), colnames(x)) && max(abs(x - t(x)), na.rm = TRUE) < 1e-12 &&
    max(abs(diag(x) - 1), na.rm = TRUE) < 1e-12 && all(x[is.finite(x)] >= -1 & x[is.finite(x)] <= 1)
}
add_check("COR-001", "correlations", "critical", matrix_integrity(level_matrix), nrow(level_matrix), "symmetric square matrix, unit diagonal, values in [-1,1]", "Level correlation matrix must be internally valid.")
add_check("COR-002", "correlations", "critical", matrix_integrity(change_matrix), nrow(change_matrix), "symmetric square matrix, unit diagonal, values in [-1,1]", "Change correlation matrix must be internally valid.")
primary_level <- level_matrix[specification$primary_method, setdiff(colnames(level_matrix), specification$primary_method)]
primary_change <- change_matrix[specification$primary_method, setdiff(colnames(change_matrix), specification$primary_method)]
add_check("COR-003", "correlations", "warning", min(primary_level, na.rm = TRUE) >= specification$correlation_warning_threshold, min(primary_level, na.rm = TRUE), paste0(">=", specification$correlation_warning_threshold), "Low values identify outcome constructions that need substantive inspection; they do not select items.")
add_check("COR-004", "correlations", "warning", min(primary_change, na.rm = TRUE) >= specification$correlation_warning_threshold, min(primary_change, na.rm = TRUE), paste0(">=", specification$correlation_warning_threshold), "Change scores are noisier; low values require interpretation before regressions.")
primary_chained_nodes <- node_pairwise %>% filter(
  (left_method == specification$primary_method & right_method == "chained__strict_summary") |
    (right_method == specification$primary_method & left_method == "chained__strict_summary")
) %>% mutate(
  primary_mean = if_else(left_method == specification$primary_method, mean_left, mean_right),
  chained_mean = if_else(left_method == specification$primary_method, mean_right, mean_left),
  primary_sd = if_else(left_method == specification$primary_method, sd_left, sd_right),
  chained_sd = if_else(left_method == specification$primary_method, sd_right, sd_left),
  absolute_mean_shift = abs(primary_mean - chained_mean),
  sd_ratio = primary_sd / chained_sd
)
add_check("SCALE-001", "scale_linking", "warning", min(primary_chained_nodes$pearson, na.rm = TRUE) >= 0.99, min(primary_chained_nodes$pearson, na.rm = TRUE), ">=0.99", "Within-node rankings should remain nearly identical across the primary and strict chained links.")
add_check("SCALE-002", "scale_linking", "warning", max(primary_chained_nodes$absolute_mean_shift, na.rm = TRUE) <= 0.50, max(primary_chained_nodes$absolute_mean_shift, na.rm = TRUE), "<=0.50", "Large location shifts are absorbed by the regression's node-specific time effects but must still be disclosed for descriptive scale comparisons.")
add_check("SCALE-003", "scale_linking", "warning", all(primary_chained_nodes$sd_ratio >= 0.80 & primary_chained_nodes$sd_ratio <= 1.25, na.rm = TRUE), paste(range(primary_chained_nodes$sd_ratio, na.rm = TRUE), collapse = ";"), "[0.80,1.25]", "Scale-factor differences do not mechanically cancel in difference-in-differences and therefore require treatment-effect robustness checks.")

# Known external confirmation is reported as a warning, not silently resolved.
y3_sources <- read_work_csv(file.path(work_root, "outputs/y3_ministry/00_readiness/y3_source_registry.csv"))
y2_sources <- read_work_csv(file.path(output_root, "00_y2_sources/y2_source_registry.csv"))
unconfirmed_sources <- sum(y3_sources$candidate_status == "candidate" & y3_sources$canonicality_status != "confirmed_canonical") +
  sum(y2_sources$exists == TRUE & y2_sources$canonical_confirmed != 1L)
add_check("LINEAGE-001", "canonicality", "warning", unconfirmed_sources == 0L, unconfirmed_sources, 0, "Hashes are verified, but collaborator confirmation of canonical source roles remains a separate decision gate.")

checks <- bind_rows(check_rows)
critical_fail_n <- sum(checks$status == "fail")
warning_n <- sum(checks$status == "warning")
confidence <- case_when(
  critical_fail_n > 0L ~ "low",
  warning_n > 0L ~ "medium",
  TRUE ~ "high"
)
out_dir <- assert_output(file.path(output_root, "08_adversarial_validation"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(checks, file.path(out_dir, "adversarial_validation_checks.csv"), na = "")
writeLines(capture.output(sessionInfo()), file.path(out_dir, "software_session_info.txt"))

report_lines <- c(
  "# Adversarial validation of the IRT outcome build",
  "",
  paste0("Generated: ", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  "",
  paste0("Overall confidence: **", confidence, "**. Critical failures: ", critical_fail_n, "; warnings: ", warning_n, "."),
  "",
  "This review attacks lineage, specification completeness, response-format eligibility, fixed Year 1 parameter fidelity, model convergence, student-node grain, coverage, treatment leakage, plain-score standardization, correlation-matrix integrity, and the measurement/regression boundary.",
  "",
  "| Check | Area | Severity | Status | Observed | Expected |",
  "|---|---|---|---|---:|---|",
  apply(checks, 1, function(row) paste0("| ", row[["check_id"]], " | ", row[["area"]], " | ", row[["severity"]], " | ", row[["status"]], " | ", str_replace_all(row[["observed"]], "\\|", "/"), " | ", str_replace_all(row[["expected"]], "\\|", "/"), " |")),
  "",
  "## Interpretation",
  "",
  if (critical_fail_n == 0L) "No implemented construction error was found by the automated adversarial checks." else "At least one critical construction error remains; do not use the outcome file.",
  "Warnings are decision gates or sensitivity signals, not automatic item exclusions. In particular, source-role confirmation and any low change-score correlations must be resolved or disclosed before the outcome is frozen for regressions.",
  "The permissive item-ID-only concurrent model is intentionally quarantined and cannot become a preferred result through this pipeline.",
  "No treatment regression is part of this build."
)
writeLines(report_lines, file.path(out_dir, "ADVERSARIAL_VALIDATION_REPORT.md"))

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), check_n = nrow(checks),
  pass_n = sum(checks$status == "pass"), warning_n = warning_n, critical_fail_n = critical_fail_n,
  confidence = confidence, primary_method = specification$primary_method,
  primary_row_n = nrow(primary), robustness_row_n = nrow(robustness),
  regression_executed = 0L, status = if (critical_fail_n == 0L) "passed_with_documented_warnings" else "failed"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "adversarial_validation_summary.json"))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
if (critical_fail_n > 0L) stop("Adversarial validation found ", critical_fail_n, " critical failure(s)")
