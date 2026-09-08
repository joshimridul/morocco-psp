#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: validate_ministry_multiyear_irt_results.R config/paths.local.yml")
paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
normalize_for_guard <- function(path) normalizePath(path, mustWork = FALSE)
is_within <- function(path, root) {
  candidate <- normalize_for_guard(path); boundary <- normalize_for_guard(root)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_work_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) stop("Input outside work_root")
  candidate
}
assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Output inside source root")
  candidate
}

out_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/07_ministry_multiyear_results"))
files <- c(
  headline = "ministry_headline_irt_estimates.csv",
  grade = "ministry_grade_irt_estimates.csv",
  heterogeneity = "ministry_heterogeneity_irt_estimates.csv",
  stable = "ministry_stable_irt_estimates.csv"
)
tables <- map(files, ~ read_csv(assert_work_input(file.path(out_dir, .x)), show_col_types = FALSE))
method_registry <- read_csv(assert_work_input(file.path(out_dir, "irt_score_method_registry.csv")), show_col_types = FALSE)
expected_methods <- c("ministry_sum", paste0("irt_", method_registry$score_method))

checks <- list()
add_check <- function(id, pass, observed, expected, note = "") {
  checks[[id]] <<- tibble(
    check_id = id, pass = as.integer(isTRUE(pass)),
    observed = as.character(observed), expected = as.character(expected), note = note
  )
}

expected_rows <- c(
  headline = 32L * length(expected_methods),
  grade = 172L * length(expected_methods),
  heterogeneity = 128L * length(expected_methods),
  stable = 20L * length(expected_methods)
)
for (table_name in names(tables)) {
  data <- tables[[table_name]]
  add_check(
    paste0(table_name, "_row_count"), nrow(data) == expected_rows[[table_name]],
    nrow(data), expected_rows[[table_name]]
  )
  add_check(
    paste0(table_name, "_method_set"), setequal(unique(data$score_method), expected_methods),
    paste(sort(unique(data$score_method)), collapse = ";"),
    paste(sort(expected_methods), collapse = ";")
  )
  forbidden <- intersect(names(data), c(
    "student_id", "student_id_num", "id_student", "id_student_panel",
    "massar", "massar_code", "cd_etab", "school_id", "pair_id"
  ))
  add_check(
    paste0(table_name, "_aggregate_only_columns"), length(forbidden) == 0,
    paste(forbidden, collapse = ";"), "no record-level identifiers"
  )
  invalid_se_n <- sum(!is.na(data$b) & (is.na(data$se) | data$se <= 0))
  add_check(
    paste0(table_name, "_estimated_coefficients_have_positive_se"),
    invalid_se_n == 0L, invalid_se_n, 0,
    "Omitted/non-estimable coefficients must remain missing, not zero."
  )
}

headline_key <- c("score_method", "panel", "exposure", "cohort", "pooled", "subject_order", "subject")
grade_key <- c(headline_key, "grade")
het_key <- c(headline_key, "group_order", "subgroup")
stable_key <- c("score_method", "cohort", "exposure", "subject_order", "subject")
duplicate_counts <- c(
  headline = sum(duplicated(tables$headline[headline_key])),
  grade = sum(duplicated(tables$grade[grade_key])),
  heterogeneity = sum(duplicated(tables$heterogeneity[het_key])),
  stable = sum(duplicated(tables$stable[stable_key]))
)
for (table_name in names(duplicate_counts)) {
  add_check(paste0(table_name, "_unique_keys"), duplicate_counts[[table_name]] == 0,
            duplicate_counts[[table_name]], 0)
}

y1_dispersion <- tables$headline %>%
  filter(panel == "A", cohort == 1L, pooled == 0L, score_method != "ministry_sum") %>%
  group_by(subject) %>%
  summarise(effect_range = max(b) - min(b), se_range = max(se) - min(se), .groups = "drop")
add_check(
  "delivered_y1_effects_identical_across_methods",
  max(y1_dispersion$effect_range, y1_dispersion$se_range) < 1e-12,
  max(y1_dispersion$effect_range, y1_dispersion$se_range), 0,
  "Every method substitutes the same unchanged delivered Y1 score in C1E1."
)

binary_contract <- read_csv(assert_work_input(file.path(
  work_root, "outputs/y1_y3_irt/05_validation/irt_binary_response_contract.csv"
)), show_col_types = FALSE)
add_check(
  "nonbinary_items_excluded_from_irt",
  binary_contract$binary_response_contract_pass[[1]] == 1L &&
    binary_contract$modeled_nonbinary_y2_node_item_n[[1]] == 0L,
  binary_contract$modeled_nonbinary_y2_node_item_n[[1]], 0,
  paste(binary_contract$nonbinary_excluded_y2_node_item_n[[1]], "nonbinary Year 2 occurrences excluded")
)

tieout <- read_csv(assert_work_input(file.path(out_dir, "ministry_sum_score_reference_tieout.csv")), show_col_types = FALSE)
core_tieout <- tieout %>% filter(table_name != "stable")
add_check(
  "core_ministry_sum_score_tieout",
  all(core_tieout$exact_to_stored_precision == 1L),
  paste(core_tieout$table_name[core_tieout$exact_to_stored_precision != 1L], collapse = ";"),
  "all headline, grade, and heterogeneity aggregate objects"
)
stable_tieout <- tieout %>% filter(table_name == "stable")
add_check(
  "stable_sample_counts_exact",
  nrow(stable_tieout) == 1L &&
    stable_tieout$student_n_max_abs_difference[[1]] == 0 &&
    stable_tieout$school_n_max_abs_difference[[1]] == 0,
  if (nrow(stable_tieout) == 1L) paste(
    stable_tieout$student_n_max_abs_difference[[1]],
    stable_tieout$school_n_max_abs_difference[[1]], sep = ";"
  ) else nrow(stable_tieout),
  "0;0",
  paste(
    "The saved stable-table coefficient rows are a non-reproducing legacy artifact;",
    "IRT comparisons use the recomputed same-sample sum score."
  )
)

coverage <- read_csv(assert_work_input(file.path(out_dir, "irt_panel_score_coverage.csv")), show_col_types = FALSE)
provisional_coverage <- coverage %>% filter(score_method == "chained_provisional")
add_check(
  "provisional_chained_later_wave_coverage",
  min(provisional_coverage$score_coverage) > 0.99,
  min(provisional_coverage$score_coverage), ">0.99",
  "Remaining missingness is in unchanged delivered Y1 baseline scores, not unlinked Y2/Y3 nodes."
)

result <- bind_rows(checks)
write_csv(result, assert_output(file.path(out_dir, "ministry_multiyear_validation_checks.csv")), na = "")
summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  check_n = nrow(result),
  passed_check_n = sum(result$pass == 1L),
  failed_check_n = sum(result$pass != 1L),
  all_checks_pass = all(result$pass == 1L),
  status = "development_only_not_approved"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE),
           assert_output(file.path(out_dir, "ministry_multiyear_validation_summary.json")))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
if (!summary$all_checks_pass) quit(status = 1L)
