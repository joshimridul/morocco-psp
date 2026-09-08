#!/usr/bin/env Rscript

# Aggregate-only validation for the Year 3 IRT treatment-effect sensitivity.

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
if (length(args) != 1) {
  stop("Usage: validate_y3_irt_treatment_sensitivity.R config/paths.local.yml")
}

paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
source_roots <- normalizePath(
  c(paths$y1_root, paths$y2_root, paths$y3_root),
  mustWork = TRUE
)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)

is_within <- function(path, root) {
  candidate <- normalizePath(path, mustWork = FALSE)
  boundary <- normalizePath(root, mustWork = FALSE)
  identical(candidate, boundary) ||
    startsWith(candidate, paste0(boundary, .Platform$file.sep))
}

assert_output <- function(path) {
  candidate <- normalizePath(path, mustWork = FALSE)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) {
    stop("Validation output must be below work_root")
  }
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) {
    stop("Validation output resolves inside a source root")
  }
  candidate
}

out_dir <- file.path(
  work_root,
  "outputs/y1_y3_irt/06_treatment_effect_sensitivity"
)
required_files <- c(
  estimates = "treatment_effect_estimates.csv",
  contrasts = "outcome_treatment_effect_contrasts.csv",
  comparisons = "irt_vs_plain_same_panel.csv",
  dispersion = "strict_core_effect_dispersion.csv",
  plain_contrast = "plain_standardization_contrast.csv",
  sample_audit = "analysis_sample_audit.csv",
  overlap = "irt_method_panel_overlap.csv",
  item_audit = "plain_score_binary_item_audit.csv",
  constants = "plain_score_standardization_constants.csv",
  standardization_checks = "plain_score_standardization_checks.csv",
  principal = "principal_pooled_overall_comparison.csv",
  principal_contrasts = "principal_pooled_overall_contrasts.csv",
  ministry_headline = "ministry_c3_headline_reconciliation.csv",
  ministry_grade = "ministry_c3_grade_reconciliation.csv",
  ministry_grade_summary = "ministry_c3_grade_reconciliation_summary.csv",
  ministry_summary = "ministry_reconciliation_summary.json",
  summary = "run_summary.json"
)
paths_to_validate <- set_names(file.path(out_dir, required_files), names(required_files))
if (any(!file.exists(paths_to_validate))) {
  stop(
    "Missing sensitivity outputs: ",
    paste(names(paths_to_validate)[!file.exists(paths_to_validate)], collapse = ", ")
  )
}

json_names <- c("summary", "ministry_summary")
tables <- map(paths_to_validate[!names(paths_to_validate) %in% json_names], function(path) {
  read_csv(path, show_col_types = FALSE)
})
summary <- fromJSON(paths_to_validate[["summary"]], simplifyVector = TRUE)
ministry_summary <- fromJSON(
  paths_to_validate[["ministry_summary"]],
  simplifyVector = TRUE
)

checks <- list()
add_check <- function(name, passed, detail) {
  checks[[length(checks) + 1L]] <<- tibble(
    check = name,
    passed = as.integer(isTRUE(passed)),
    detail = as.character(detail)
  )
}

for (table_name in names(tables)) {
  direct_identifier_columns <- names(tables[[table_name]])[
    str_detect(names(tables[[table_name]]), regex(
      "^(id_student_panel|student_id|student_name|school_name|telephone|phone)$",
      ignore_case = TRUE
    ))
  ]
  add_check(
    paste0("no_direct_identifiers_", table_name),
    length(direct_identifier_columns) == 0,
    if (length(direct_identifier_columns)) {
      paste(direct_identifier_columns, collapse = ",")
    } else {
      "aggregate columns only"
    }
  )
}

estimated <- tables$estimates %>%
  filter(estimation_status == "estimated_development_only")
add_check(
  "estimated_rows_are_finite",
  nrow(estimated) > 0 && all(is.finite(estimated$estimate)) &&
    all(is.finite(estimated$std_error)) && all(estimated$std_error >= 0),
  paste("estimated rows:", nrow(estimated))
)
estimated_contrasts <- tables$contrasts %>%
  filter(estimation_status == "estimated_development_only")
add_check(
  "estimated_contrasts_are_finite",
  nrow(estimated_contrasts) > 0 && all(is.finite(estimated_contrasts$estimate)) &&
    all(is.finite(estimated_contrasts$std_error)) &&
    all(estimated_contrasts$std_error >= 0),
  paste("estimated contrast rows:", nrow(estimated_contrasts))
)
add_check(
  "all_outputs_unapproved",
  all(tables$estimates$final_outcome_approved == 0L) &&
    all(tables$contrasts$final_outcome_approved == 0L) &&
    identical(summary$final_outcome_approved, FALSE),
  "all treatment-effect rows remain development-only"
)
add_check(
  "nonbinary_items_excluded",
  all(tables$item_audit$included_binary_item_n <= tables$item_audit$manifest_item_n) &&
    summary$scoring$nonbinary_rule ==
      "all non-binary items excluded before score construction",
  paste(
    "observed nonbinary item occurrences excluded:",
    sum(tables$item_audit$excluded_observed_nonbinary_item_n)
  )
)
add_check(
  "standardization_control_means_zero",
  max(abs(tables$standardization_checks$achieved_control_mean), na.rm = TRUE) < 1e-10,
  paste(
    "max absolute mean:",
    signif(max(abs(tables$standardization_checks$achieved_control_mean), na.rm = TRUE), 4)
  )
)
add_check(
  "standardization_control_sds_one",
  max(abs(tables$standardization_checks$achieved_control_sd - 1), na.rm = TRUE) < 1e-10,
  paste(
    "max absolute SD deviation:",
    signif(max(abs(tables$standardization_checks$achieved_control_sd - 1), na.rm = TRUE), 4)
  )
)
add_check(
  "same_panel_comparisons_have_same_n",
  all(tables$comparisons$same_regression_n),
  paste("comparison rows:", nrow(tables$comparisons))
)

expected_irt_methods <- c(
  "direct_strict", "direct_provisional", "chained_strict",
  "chained_provisional", "pooled_strict_all",
  "pooled_strict_comparison", "pooled_strict_school_development",
  "grade_specific_strict_all", "pooled_purified_strict_all",
  "pooled_purified_andy_core", "pooled_purified_math_bridge"
)
observed_principal_irt <- tables$principal %>%
  filter(pairing_role == "irt_target") %>%
  pull(score_method)
add_check(
  "all_expected_irt_methods_in_principal_table",
  setequal(expected_irt_methods, observed_principal_irt),
  paste("observed:", paste(sort(observed_principal_irt), collapse = ","))
)
add_check(
  "both_plain_standardizations_in_principal_table",
  all(c("plain_code", "plain_report_grade") %in% tables$principal$score_method),
  paste("principal rows:", nrow(tables$principal))
)

core_pairs <- tables$overlap %>%
  filter(
    sample_variant == "listed_panel",
    left_method %in% c("chained_strict", "pooled_strict_all", "pooled_strict_comparison"),
    right_method %in% c("chained_strict", "pooled_strict_all", "pooled_strict_comparison")
  )
add_check(
  "strict_core_uses_identical_student_panels",
  nrow(core_pairs) == 6 && all(core_pairs$identical_panel),
  paste("strict core overlap rows:", nrow(core_pairs))
)

add_check(
  "registered_source_hashes_verified",
  nrow(as.data.frame(summary$source_registry_verification)) == 2,
  "baseline and endline hashes matched the source registry at run time"
)
add_check(
  "no_student_level_output_written",
  identical(summary$student_level_output_written, FALSE) &&
    identical(summary$data_written_to_github, FALSE),
  "aggregate work_root outputs only"
)
plain_code_reconciliation <- tables$ministry_grade_summary %>%
  filter(score_method == "plain_code")
plain_grade_reconciliation <- tables$ministry_grade_summary %>%
  filter(score_method == "plain_report_grade")
add_check(
  "ministry_c3_plain_code_grade_reconciliation",
  nrow(plain_code_reconciliation) == 1 &&
    plain_code_reconciliation$estimated_cell_n == 24 &&
    plain_code_reconciliation$mean_absolute_difference < 0.025 &&
    plain_code_reconciliation$maximum_absolute_difference < 0.060,
  paste(
    "MAE:", round(plain_code_reconciliation$mean_absolute_difference, 4),
    "max:", round(plain_code_reconciliation$maximum_absolute_difference, 4)
  )
)
add_check(
  "ministry_reconciliation_favors_do_file_standardization",
  nrow(plain_grade_reconciliation) == 1 &&
    plain_code_reconciliation$mean_absolute_difference <
      plain_grade_reconciliation$mean_absolute_difference,
  paste(
    "do-file MAE:", round(plain_code_reconciliation$mean_absolute_difference, 4),
    "within-grade MAE:", round(plain_grade_reconciliation$mean_absolute_difference, 4)
  )
)
add_check(
  "ministry_comparison_scope_is_explicit",
  str_detect(
    ministry_summary$directly_comparable_ministry_block,
    fixed("Cohort 3 one-year exposure")
  ) && str_detect(
    ministry_summary$noncomparable_blocks,
    fixed("original pre-program")
  ),
  "Cohort 3 is direct; Cohorts 1 and 2 are explicitly noncomparable"
)

validation <- bind_rows(checks)
validation_status <- if (all(validation$passed == 1L)) "pass" else "fail"
write_csv(
  validation,
  assert_output(file.path(out_dir, "validation_checks.csv")),
  na = ""
)
writeLines(
  toJSON(
    list(
      created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      validation_status = validation_status,
      check_n = nrow(validation),
      passed_n = sum(validation$passed),
      failed_n = sum(validation$passed == 0L),
      development_only = TRUE
    ),
    pretty = TRUE,
    auto_unbox = TRUE
  ),
  assert_output(file.path(out_dir, "validation_summary.json"))
)

print(validation, n = Inf)
if (validation_status != "pass") stop("Treatment-effect sensitivity validation failed")
