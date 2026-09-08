#!/usr/bin/env Rscript

# Compare every reconstructed IRT result with the exact aggregate sum-score
# result objects underlying the Ministry PDFs. No student records are exported.

suppressPackageStartupMessages({
  library(digest)
  library(dplyr)
  library(haven)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: compare_ministry_multiyear_irt_results.R config/paths.local.yml")
paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
normalize_for_guard <- function(path) normalizePath(path, mustWork = FALSE)
is_within <- function(path, root) {
  candidate <- normalize_for_guard(path); boundary <- normalize_for_guard(root)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_source <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Input outside source roots")
  candidate
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
sha256_file <- function(path) digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)

out_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/07_ministry_multiyear_results"))
table_root <- file.path(paths$y3_root, "5 - Data analysis/05_Endline/Analysis/Tables")

specs <- tribble(
  ~table_name, ~new_file, ~reference_file, ~key_fields,
  "headline", "ministry_headline_irt_estimates.csv", "student_performance_estimates.dta", c("panel", "exposure", "cohort", "pooled", "subject_order", "subject"),
  "grade", "ministry_grade_irt_estimates.csv", "student_performance_by_grade_estimates.dta", c("panel", "exposure", "cohort", "pooled", "subject_order", "grade", "subject"),
  "heterogeneity", "ministry_heterogeneity_irt_estimates.csv", "student_performance_heterogeneity_estimates.dta", c("panel", "cohort", "pooled", "subject_order", "group_order", "subject", "subgroup")
) %>%
  mutate(
    new_path = map_chr(new_file, ~ assert_work_input(file.path(out_dir, .x))),
    reference_path = map_chr(reference_file, ~ assert_source(file.path(table_root, .x)))
  )

significance_band <- function(p) case_when(
  is.na(p) ~ "not_estimated",
  p < 0.01 ~ "p_lt_0_01",
  p < 0.05 ~ "p_lt_0_05",
  p < 0.10 ~ "p_lt_0_10",
  TRUE ~ "p_ge_0_10"
)

comparison_rows <- list(); tie_rows <- list(); reference_registry <- list()
for (index in seq_len(nrow(specs))) {
  spec <- specs[index, ]
  keys <- spec$key_fields[[1]]
  current <- read_csv(spec$new_path[[1]], show_col_types = FALSE)
  if (spec$table_name[[1]] == "grade") {
    current <- current %>%
      group_by(score_method, exposure, cohort) %>%
      mutate(
        p_raw = p,
        p = if (all(is.na(p_raw))) p_raw else p.adjust(p_raw, method = "BY")
      ) %>%
      ungroup()
    write_csv(
      current,
      assert_output(file.path(out_dir, "ministry_grade_irt_estimates_with_by_p.csv")),
      na = ""
    )
  }
  reference <- read_dta(spec$reference_path[[1]]) %>%
    mutate(across(where(is.labelled), zap_labels)) %>%
    as_tibble()

  if (spec$table_name[[1]] == "grade") {
    reference <- reference %>% filter(subject_order > 0, grade > 0)
  }

  if (spec$table_name[[1]] == "headline" && !"exposure" %in% names(reference)) {
    reference <- reference %>% mutate(exposure = recode(panel, A = 1, B = 2, C = 3))
  }
  if (spec$table_name[[1]] == "heterogeneity" && !"exposure" %in% names(reference)) {
    reference <- reference %>% mutate(exposure = recode(panel, A = 1, B = 2, C = 3))
    keys <- c("panel", "exposure", "cohort", "pooled", "subject_order", "group_order", "subject", "subgroup")
  }
  reference_p_field <- if (spec$table_name[[1]] == "grade") "p_by" else "p"
  missing_current <- setdiff(c(keys, "b", "se", "p", "n_students", "n_schools"), names(current))
  missing_reference <- setdiff(c(keys, "b", "se", reference_p_field, "n_students", "n_schools"), names(reference))
  if (length(missing_current) || length(missing_reference)) {
    stop("Missing comparison fields for ", spec$table_name[[1]], ": current=",
         paste(missing_current, collapse = ","), "; reference=", paste(missing_reference, collapse = ","))
  }
  reference <- reference %>%
    transmute(
      across(all_of(keys)), ministry_b = b, ministry_se = se,
      ministry_p = .data[[reference_p_field]],
      ministry_n_students = n_students, ministry_n_schools = n_schools
    )
  if (anyDuplicated(reference[keys])) stop("Duplicate Ministry reference keys for ", spec$table_name[[1]])

  joined <- current %>%
    left_join(reference, by = keys) %>%
    mutate(
      table_name = spec$table_name[[1]],
      delta_b = b - ministry_b,
      abs_delta_b = abs(delta_b),
      delta_se = se - ministry_se,
      student_n_difference = n_students - ministry_n_students,
      school_n_difference = n_schools - ministry_n_schools,
      same_sign = if_else(!is.na(b) & !is.na(ministry_b), sign(b) == sign(ministry_b), NA),
      irt_significance_band = significance_band(p),
      ministry_significance_band = significance_band(ministry_p),
      same_significance_band = irt_significance_band == ministry_significance_band,
      result_status = case_when(
        is.na(ministry_b) ~ "missing_ministry_reference",
        is.na(b) ~ "irt_not_estimated",
        TRUE ~ "compared"
      )
    )
  comparison_rows[[spec$table_name[[1]]]] <- joined

  tie <- joined %>%
    filter(score_method == "ministry_sum") %>%
    summarise(
      table_name = spec$table_name[[1]],
      expected_reference_cell_n = nrow(reference),
      joined_reference_cell_n = sum(!is.na(ministry_b)),
      estimate_max_abs_difference = max(abs_delta_b, na.rm = TRUE),
      se_max_abs_difference = max(abs(delta_se), na.rm = TRUE),
      student_n_max_abs_difference = max(abs(student_n_difference), na.rm = TRUE),
      school_n_max_abs_difference = max(abs(school_n_difference), na.rm = TRUE),
      exact_to_stored_precision = estimate_max_abs_difference < 1e-10 &
        se_max_abs_difference < 1e-10 & student_n_max_abs_difference == 0 &
        school_n_max_abs_difference == 0
    )
  tie_rows[[spec$table_name[[1]]]] <- tie
  reference_registry[[spec$table_name[[1]]]] <- tibble(
    table_name = spec$table_name[[1]],
    reference_file = spec$reference_file[[1]],
    reference_sha256 = sha256_file(spec$reference_path[[1]]),
    reference_role = "exact_aggregate_object_underlying_ministry_pdf"
  )
}

stable_path <- assert_work_input(file.path(out_dir, "ministry_stable_irt_estimates.csv"))
stable_reference_path <- assert_source(file.path(table_root, "table-prelim-ITT-3year-stable-sample.tex"))
stable_reference <- tribble(
  ~cohort, ~exposure, ~subject_order, ~subject, ~ministry_b, ~ministry_se, ~ministry_n_students, ~ministry_n_schools,
  1L, 1L, 1L, "overall", 0.964, 0.057, 3711, 86,
  1L, 1L, 2L, "arabic", 0.514, 0.086, 1213, 83,
  1L, 1L, 3L, "french", 1.506, 0.107, 1204, 83,
  1L, 1L, 4L, "math", 0.888, 0.081, 1294, 85,
  1L, 2L, 1L, "overall", 0.566, 0.059, 3920, 86,
  1L, 2L, 2L, "arabic", 0.299, 0.104, 1283, 85,
  1L, 2L, 3L, "french", 0.880, 0.072, 1299, 84,
  1L, 2L, 4L, "math", 0.538, 0.085, 1338, 85,
  1L, 3L, 1L, "overall", 0.441, 0.069, 3932, 86,
  1L, 3L, 2L, "arabic", 0.167, 0.063, 1286, 85,
  1L, 3L, 3L, "french", 0.729, 0.078, 1300, 84,
  1L, 3L, 4L, "math", 0.530, 0.121, 1346, 86,
  2L, 1L, 1L, "overall", 0.514, 0.101, 1486, 30,
  2L, 1L, 2L, "arabic", 0.304, 0.151, 464, 29,
  2L, 1L, 3L, "french", 0.671, 0.140, 500, 30,
  2L, 1L, 4L, "math", 0.435, 0.107, 522, 30,
  2L, 2L, 1L, "overall", 0.474, 0.073, 1577, 32,
  2L, 2L, 2L, "arabic", 0.231, 0.103, 488, 31,
  2L, 2L, 3L, "french", 0.552, 0.086, 533, 32,
  2L, 2L, 4L, "math", 0.569, 0.067, 556, 32
) %>%
  mutate(
    ministry_p = NA_real_,
    panel = recode(as.character(exposure), `1` = "A", `2` = "B", `3` = "C"),
    pooled = 0L
  )
stable_current <- read_csv(stable_path, show_col_types = FALSE) %>%
  mutate(panel = recode(as.character(exposure), `1` = "A", `2` = "B", `3` = "C"), pooled = 0L)
stable_joined <- stable_current %>%
  left_join(stable_reference, by = c("cohort", "exposure", "subject_order", "subject", "panel", "pooled")) %>%
  mutate(
    table_name = "stable",
    delta_b = b - ministry_b,
    abs_delta_b = abs(delta_b),
    delta_se = se - ministry_se,
    student_n_difference = n_students - ministry_n_students,
    school_n_difference = n_schools - ministry_n_schools,
    same_sign = if_else(!is.na(b) & !is.na(ministry_b), sign(b) == sign(ministry_b), NA),
    irt_significance_band = significance_band(p),
    ministry_significance_band = "pdf_reported",
    same_significance_band = NA,
    result_status = case_when(
      is.na(ministry_b) ~ "missing_ministry_reference",
      is.na(b) ~ "irt_not_estimated",
      TRUE ~ "compared"
    )
  )
comparison_rows$stable <- stable_joined
tie_rows$stable <- stable_joined %>%
  filter(score_method == "ministry_sum") %>%
  summarise(
    table_name = "stable",
    expected_reference_cell_n = nrow(stable_reference),
    joined_reference_cell_n = sum(!is.na(ministry_b)),
    estimate_max_abs_difference = max(abs_delta_b, na.rm = TRUE),
    se_max_abs_difference = max(abs(delta_se), na.rm = TRUE),
    student_n_max_abs_difference = max(abs(student_n_difference), na.rm = TRUE),
    school_n_max_abs_difference = max(abs(school_n_difference), na.rm = TRUE),
    exact_to_stored_precision = estimate_max_abs_difference <= 0.0005 &
      se_max_abs_difference <= 0.0005 & student_n_max_abs_difference == 0 &
      school_n_max_abs_difference == 0
  )
reference_registry$stable <- tibble(
  table_name = "stable",
  reference_file = basename(stable_reference_path),
  reference_sha256 = sha256_file(stable_reference_path),
  reference_role = "values_transcribed_from_ministry_stable_sample_table"
)

comparisons <- bind_rows(comparison_rows)
tieout <- bind_rows(tie_rows)
registry <- bind_rows(reference_registry)

# Use the score generated in the same run as the non-IRT benchmark. This is
# identical to the saved Ministry object for headline, grade, and heterogeneity
# results. It is deliberately separate for the stable table because the saved
# coefficient rows do not reproduce even though its sample counts do.
comparison_keys <- c(
  "table_name", "panel", "exposure", "cohort", "pooled", "subject_order",
  "grade", "group_order", "subject", "subgroup"
)
same_run_sum <- comparisons %>%
  filter(score_method == "ministry_sum") %>%
  transmute(
    across(all_of(comparison_keys)),
    same_sample_sum_b = b,
    same_sample_sum_se = se,
    same_sample_sum_p = p,
    same_sample_sum_n_students = n_students,
    same_sample_sum_n_schools = n_schools
  )
if (anyDuplicated(same_run_sum[comparison_keys])) stop("Duplicate same-run sum-score comparison keys")
comparisons <- comparisons %>%
  left_join(same_run_sum, by = comparison_keys) %>%
  mutate(
    delta_same_sample_sum_b = b - same_sample_sum_b,
    abs_delta_same_sample_sum_b = abs(delta_same_sample_sum_b),
    same_sample_sum_same_sign = if_else(
      !is.na(b) & !is.na(same_sample_sum_b), sign(b) == sign(same_sample_sum_b), NA
    ),
    same_sample_sum_significance_band = significance_band(same_sample_sum_p),
    same_sample_sum_same_significance_band =
      irt_significance_band == same_sample_sum_significance_band
  )
irt_comparisons <- comparisons %>% filter(score_method != "ministry_sum")

summaries <- irt_comparisons %>%
  group_by(table_name, score_method) %>%
  summarise(
    ministry_cell_n = n(),
    compared_cell_n = sum(result_status == "compared"),
    irt_not_estimated_cell_n = sum(result_status == "irt_not_estimated"),
    mean_absolute_effect_difference = mean(abs_delta_same_sample_sum_b, na.rm = TRUE),
    median_absolute_effect_difference = median(abs_delta_same_sample_sum_b, na.rm = TRUE),
    maximum_absolute_effect_difference = max(abs_delta_same_sample_sum_b, na.rm = TRUE),
    effect_correlation = cor(b, same_sample_sum_b, use = "complete.obs"),
    same_sign_share = mean(same_sample_sum_same_sign, na.rm = TRUE),
    same_significance_band_share = mean(same_sample_sum_same_significance_band, na.rm = TRUE),
    median_student_n_ratio = median(n_students / same_sample_sum_n_students, na.rm = TRUE),
    .groups = "drop"
  )

cell_dispersion <- irt_comparisons %>%
  group_by(table_name, across(any_of(c(
    "panel", "exposure", "cohort", "pooled", "subject_order", "grade",
    "group_order", "subject", "subgroup"
  )))) %>%
  summarise(
    irt_method_estimated_n = sum(!is.na(b)),
    irt_effect_min = if (all(is.na(b))) NA_real_ else min(b, na.rm = TRUE),
    irt_effect_max = if (all(is.na(b))) NA_real_ else max(b, na.rm = TRUE),
    irt_effect_range = irt_effect_max - irt_effect_min,
    ministry_b = first(ministry_b),
    .groups = "drop"
  )

for (table_value in unique(comparisons$table_name)) {
  write_csv(
    comparisons %>% filter(table_name == table_value),
    assert_output(file.path(out_dir, paste0("ministry_", table_value, "_irt_comparison.csv"))), na = ""
  )
}
write_csv(summaries, assert_output(file.path(out_dir, "ministry_irt_comparison_summary.csv")), na = "")
write_csv(tieout, assert_output(file.path(out_dir, "ministry_sum_score_reference_tieout.csv")), na = "")
write_csv(registry, assert_output(file.path(out_dir, "ministry_result_reference_registry.csv")), na = "")
write_csv(cell_dispersion, assert_output(file.path(out_dir, "ministry_irt_cell_method_dispersion.csv")), na = "")

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  comparison_table_n = n_distinct(comparisons$table_name),
  score_method_n = n_distinct(irt_comparisons$score_method),
  total_irt_ministry_cell_n = nrow(irt_comparisons),
  compared_cell_n = sum(irt_comparisons$result_status == "compared"),
  unestimated_irt_cell_n = sum(irt_comparisons$result_status == "irt_not_estimated"),
  stored_sum_score_reference_tieout_all_exact = all(tieout$exact_to_stored_precision[tieout$table_name != "stable"]),
  stable_sample_counts_exact = all(
    tieout$student_n_max_abs_difference[tieout$table_name == "stable"] == 0 &
      tieout$school_n_max_abs_difference[tieout$table_name == "stable"] == 0
  ),
  stable_reference_estimates_reproduce = isTRUE(tieout$exact_to_stored_precision[tieout$table_name == "stable"]),
  status = "development_only_not_approved"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE),
           assert_output(file.path(out_dir, "ministry_multiyear_comparison_summary.json")))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
