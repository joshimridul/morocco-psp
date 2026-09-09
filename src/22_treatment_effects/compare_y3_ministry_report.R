#!/usr/bin/env Rscript

# Reconcile aggregate Cohort 3 one-year estimates with the two PDFs shared
# with the Ministry. Reported Ministry coefficients are transcribed at their
# published table grain; no student-level data or identifiers are written.

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("Usage: compare_y3_ministry_report.R config/paths.local.yml")
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

assert_work_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) stop("Input is outside work_root")
  candidate
}

assert_output <- function(path) {
  candidate <- normalizePath(path, mustWork = FALSE)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) {
    stop("Output must be below work_root")
  }
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x) && !is_within(work_root, .x)))) {
    stop("Output resolves inside a read-only source root")
  }
  candidate
}

out_dir <- assert_output(file.path(
  work_root,
  "outputs/y1_y3_irt/06_treatment_effect_sensitivity"
))
estimate_path <- assert_work_input(file.path(out_dir, "treatment_effect_estimates.csv"))
estimates <- read_csv(estimate_path, show_col_types = FALSE)

methods <- c(
  "plain_code", "plain_report_grade", "chained_strict",
  "pooled_strict_all", "pooled_strict_comparison",
  "pooled_purified_math_bridge"
)

ministry_headline <- tribble(
  ~subject, ~ministry_estimate, ~ministry_std_error, ~ministry_n_students,
  "Overall", 0.403, 0.049, 11528L,
  "Arabic", 0.250, 0.046, 3908L,
  "French", 0.466, 0.083, 3895L,
  "Maths", 0.497, 0.041, 3767L
) %>%
  mutate(
    ministry_n_schools = 145L,
    ministry_source = "Year 3 Preliminary Results, Table 1, Panel A, Cohort 3",
    comparison_scope = paste(
      "same Cohort 3 one-year exposure window; score, covariate, sample-support,",
      "and cleaning rules are not fully identical"
    )
  )

new_headline <- estimates %>%
  filter(
    sample_variant == "listed_panel",
    cohort_scope == "3",
    grade_scope == "All_grades",
    score_method %in% methods,
    pairing_role == "irt_target" |
      (estimand_sample == "full_plain_panel" & pairing_role == "standalone_plain")
  ) %>%
  select(
    subject, score_method,
    new_estimate = estimate,
    new_std_error = std_error,
    new_n_students = n_students,
    new_n_schools = n_schools,
    new_n_pairs = n_pairs,
    estimation_status
  )

headline_reconciliation <- suppressWarnings(
  inner_join(ministry_headline, new_headline, by = "subject")
) %>%
  mutate(
    estimate_difference_new_minus_ministry =
      new_estimate - ministry_estimate,
    absolute_estimate_difference =
      abs(estimate_difference_new_minus_ministry),
    student_n_difference_new_minus_ministry =
      new_n_students - ministry_n_students
  ) %>%
  arrange(subject, score_method)

ministry_grade <- tribble(
  ~grade_scope, ~subject, ~ministry_estimate, ~ministry_std_error, ~ministry_n_students,
  "1", "Overall", 0.508, 0.095, 1812L,
  "1", "Arabic", 0.324, 0.110, 612L,
  "1", "French", 0.836, 0.155, 624L,
  "1", "Maths", 0.348, 0.080, 609L,
  "2", "Overall", 0.473, 0.059, 1966L,
  "2", "Arabic", 0.304, 0.047, 656L,
  "2", "French", 0.473, 0.115, 655L,
  "2", "Maths", 0.603, 0.089, 657L,
  "3", "Overall", 0.432, 0.050, 1948L,
  "3", "Arabic", 0.247, 0.044, 655L,
  "3", "French", 0.566, 0.096, 643L,
  "3", "Maths", 0.547, 0.082, 651L,
  "4", "Overall", 0.380, 0.039, 1947L,
  "4", "Arabic", 0.133, 0.066, 664L,
  "4", "French", 0.442, 0.051, 643L,
  "4", "Maths", 0.480, 0.070, 640L,
  "5", "Overall", 0.381, 0.044, 1989L,
  "5", "Arabic", 0.208, 0.061, 671L,
  "5", "French", 0.259, 0.059, 670L,
  "5", "Maths", 0.694, 0.084, 648L,
  "6", "Overall", 0.235, 0.043, 1866L,
  "6", "Arabic", 0.214, 0.067, 649L,
  "6", "French", 0.222, 0.059, 660L,
  "6", "Maths", 0.232, 0.070, 561L
) %>%
  mutate(
    ministry_n_schools = 145L,
    ministry_source = "Grade-Specific Effects, Table 1, Cohort 3",
    comparison_scope = paste(
      "same Cohort 3 one-year exposure and baseline-grade cell; score, covariate,",
      "sample-support, and cleaning rules are not fully identical"
    )
  )

new_grade <- estimates %>%
  filter(
    sample_variant == "listed_panel",
    cohort_scope == "3",
    grade_scope != "All_grades",
    score_method %in% methods,
    pairing_role == "irt_target" |
      (estimand_sample == "full_plain_panel" & pairing_role == "standalone_plain")
  ) %>%
  select(
    grade_scope, subject, score_method,
    new_estimate = estimate,
    new_std_error = std_error,
    new_n_students = n_students,
    new_n_schools = n_schools,
    new_n_pairs = n_pairs,
    estimation_status
  )

grade_reconciliation <- suppressWarnings(
  left_join(ministry_grade, new_grade, by = c("grade_scope", "subject"))
) %>%
  mutate(
    estimate_difference_new_minus_ministry =
      new_estimate - ministry_estimate,
    absolute_estimate_difference =
      abs(estimate_difference_new_minus_ministry),
    student_n_difference_new_minus_ministry =
      new_n_students - ministry_n_students
  ) %>%
  arrange(as.integer(grade_scope), subject, score_method)

grade_summary <- grade_reconciliation %>%
  group_by(score_method) %>%
  summarise(
    ministry_cell_n = n(),
    estimated_cell_n = sum(estimation_status == "estimated_development_only", na.rm = TRUE),
    mean_difference = mean(estimate_difference_new_minus_ministry, na.rm = TRUE),
    mean_absolute_difference = mean(absolute_estimate_difference, na.rm = TRUE),
    maximum_absolute_difference = max(absolute_estimate_difference, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(mean_absolute_difference)

write_csv(
  headline_reconciliation,
  assert_output(file.path(out_dir, "ministry_c3_headline_reconciliation.csv")),
  na = ""
)
write_csv(
  grade_reconciliation,
  assert_output(file.path(out_dir, "ministry_c3_grade_reconciliation.csv")),
  na = ""
)
write_csv(
  grade_summary,
  assert_output(file.path(out_dir, "ministry_c3_grade_reconciliation_summary.csv")),
  na = ""
)

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  status = "aggregate_reconciliation_development_only",
  directly_comparable_ministry_block =
    "Cohort 3 one-year exposure in Table 1 of both Ministry PDFs",
  noncomparable_blocks = paste(
    "Cohort 1 and Cohort 2 Ministry estimates use their original pre-program",
    "baselines; the current diagnostic uses the Year 3 baseline for every cohort."
  ),
  main_report_pdf =
    "exchange-with-ministry/report-shared-with-ministry/PSP__Morocco_Primary_Schools_Year3_Preliminary Results.pdf",
  grade_report_pdf =
    "exchange-with-ministry/report-shared-with-ministry/PSP___Morocco_Primary_Schools_by_grade.pdf",
  headline_rows = nrow(headline_reconciliation),
  grade_rows = nrow(grade_reconciliation),
  grade_summary = grade_summary,
  finding = paste(
    "The subject-by-cohort-by-wave plain standardization reproduces the published",
    "Cohort 3 grade cells much more closely than within-grade standardization,",
    "supporting the production do-file as the operational rule."
  ),
  student_level_output_written = FALSE,
  final_outcome_approved = FALSE
)
writeLines(
  toJSON(summary, pretty = TRUE, auto_unbox = TRUE, na = "null"),
  assert_output(file.path(out_dir, "ministry_reconciliation_summary.json"))
)

print(headline_reconciliation %>%
  filter(subject == "Overall") %>%
  select(
    score_method, ministry_estimate, new_estimate,
    estimate_difference_new_minus_ministry,
    ministry_n_students, new_n_students
  ), n = Inf)
print(grade_summary, n = Inf)
