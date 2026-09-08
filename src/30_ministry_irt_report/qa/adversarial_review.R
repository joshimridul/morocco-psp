#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(haven)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(tibble)
  library(tidyr)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(2L, 3L)) {
  stop("Usage: adversarial_review.R <paths.yml> <output_root> [success_marker]")
}
paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
out <- normalizePath(args[[2]], mustWork = TRUE)
est <- file.path(out, "estimates")
qa <- file.path(out, "qa")
dir.create(qa, recursive = TRUE, showWarnings = FALSE)

checks <- list()
add_check <- function(name, pass, detail, severity = "critical") {
  checks[[length(checks) + 1L]] <<- tibble(
    check = name, status = ifelse(isTRUE(pass), "pass", "fail"),
    severity = severity, detail = as.character(detail)
  )
}

read_new <- function(name) read_csv(file.path(est, paste0(name, ".csv")), show_col_types = FALSE)
new <- list(
  headline = read_new("headline"), stable = read_new("stable"),
  grade = read_new("grade"), heterogeneity = read_new("heterogeneity")
)
robustness <- read_new("measurement_robustness")

expected_rows <- c(headline = 64L, stable = 40L, grade = 344L, heterogeneity = 256L)
iwalk(new, ~ add_check(
  paste0(.y, "_row_count"), nrow(.x) == expected_rows[[.y]],
  paste0("observed=", nrow(.x), "; expected=", expected_rows[[.y]])
))

iwalk(new, function(x, name) {
  primary <- filter(x, score_method == "primary_irt", !is.na(b))
  add_check(paste0(name, "_primary_nonempty"), nrow(primary) > 0L,
            paste0("estimable primary cells=", nrow(primary)))
  add_check(paste0(name, "_finite_effects"),
            all(is.finite(primary$b)) && all(is.finite(primary$se)) && all(primary$se > 0),
            "all primary coefficients and standard errors finite; SEs positive")
  add_check(paste0(name, "_effect_range"), all(abs(primary$b) < 4),
            paste0("max |effect|=", round(max(abs(primary$b)), 4)), "warning")
  add_check(paste0(name, "_cluster_support"), all(primary$n_pairs >= 2),
            paste0("minimum matched-pair clusters=", min(primary$n_pairs)))
})

limited_cluster_cells <- imap_dfr(new, function(x, family) {
  x %>% filter(score_method == "primary_irt", !is.na(b), n_pairs < 20) %>%
    transmute(family = family, panel = if ("panel" %in% names(x)) panel else NA_character_,
              cohort, exposure, subject, n_pairs)
})
write_csv(limited_cluster_cells, file.path(qa, "limited_cluster_cells.csv"), na = "")
add_check(
  "small_cluster_inference", nrow(limited_cluster_cells) == 0L,
  paste0("primary result cells with fewer than 20 matched-pair clusters=",
         nrow(limited_cluster_cells), "; minimum=",
         min(map_dbl(new, ~ min(.x$n_pairs[.x$score_method == "primary_irt" & !is.na(.x$b)])))),
  "warning"
)

add_check("grade_adjusted_pvalues", {
  x <- filter(new$grade, !is.na(p))
  all(x$p_by >= x$p - 1e-14 & x$p_by <= 1)
}, "all BY p-values lie between raw p-values and one")

headline_retention <- new$headline %>%
  select(score_method, panel, cohort, subject_order, n_students) %>%
  tidyr::pivot_wider(names_from = score_method, values_from = n_students) %>%
  mutate(retention = primary_irt / ministry_sum)
add_check(
  "primary_headline_sample_retention", all(headline_retention$retention >= 0.95),
  paste0("minimum primary-IRT/sum-score student retention=",
         round(min(headline_retention$retention), 4),
         "; the preferred link-retention floor is intended to preserve every required Year 3 node"),
  "warning"
)

panel_registry <- read_csv(file.path(dirname(out), "07_ministry_multiyear_results",
                                     "ministry_analysis_panel_registry.csv"),
                           show_col_types = FALSE)
panel_coverage <- read_csv(file.path(dirname(out), "07_ministry_multiyear_results",
                                     "irt_panel_score_coverage.csv"),
                           show_col_types = FALSE)
add_check(
  "analysis_panel_source_status",
  all(panel_registry$canonicality_status == "verified"),
  paste0("panel registry status: ", paste(unique(panel_registry$canonicality_status), collapse = ", ")),
  "warning"
)
y1_baseline_missing <- panel_coverage %>%
  filter(score_method == "primary", wave == "baseline_Y1") %>%
  mutate(missing_score_n = panel_row_n - score_nonmissing_n)
write_csv(y1_baseline_missing, file.path(qa, "y1_baseline_score_join_coverage.csv"), na = "")
add_check(
  "y1_baseline_score_join_coverage",
  all(y1_baseline_missing$missing_score_n == 0L),
  paste0("missing delivered Year 1 baseline scores by panel: ",
         paste(y1_baseline_missing$panel_id, y1_baseline_missing$missing_score_n,
               sep = "=", collapse = "; ")),
  "warning"
)

panel_dir <- file.path(dirname(out), "07_ministry_multiyear_results", "analysis_inputs")
panel_files <- c("c1e1", "c2e1", "c3e1", "c1e2", "c2e2", "c1e3")
subject_composition <- map_dfr(panel_files, function(panel_id) {
  panel <- read_dta(file.path(panel_dir, paste0(panel_id, "_irt_panel.dta")))
  balanced <- panel %>% group_by(student_id) %>%
    summarise(primary_twice = sum(!is.na(irt_primary)) == 2L, .groups = "drop")
  panel %>% inner_join(balanced, by = "student_id") %>%
    filter(primary_twice, post == 1L) %>%
    count(treated, subject, name = "student_n") %>%
    group_by(treated) %>% mutate(subject_share = student_n / sum(student_n)) %>%
    ungroup() %>% mutate(panel_id = panel_id)
})
subject_composition_contrast <- subject_composition %>%
  select(panel_id, subject, treated, student_n, subject_share) %>%
  pivot_wider(names_from = treated, values_from = c(student_n, subject_share), names_prefix = "arm_") %>%
  mutate(absolute_share_difference = abs(subject_share_arm_1 - subject_share_arm_0))
write_csv(subject_composition_contrast,
          file.path(qa, "overall_subject_composition_balance.csv"), na = "")
add_check(
  "overall_subject_composition_balance",
  max(subject_composition_contrast$absolute_share_difference, na.rm = TRUE) <= 0.02,
  paste0("maximum treatment-control difference in subject share=",
         round(max(subject_composition_contrast$absolute_share_difference, na.rm = TRUE), 4)),
  "warning"
)
primary_grade_missing <- new$grade %>%
  filter(score_method == "primary_irt", is.na(b)) %>%
  select(panel, exposure, cohort, grade, subject)
write_csv(primary_grade_missing, file.path(qa, "primary_unestimable_grade_cells.csv"), na = "")
add_check(
  "primary_grade_cells_estimable", nrow(primary_grade_missing) == 8L,
  paste0("unestimable primary grade cells=", nrow(primary_grade_missing),
         "; expected: eight structural Cohort-2 Grade-1 cells, because that cohort entered in Grade 2"),
  "warning"
)

# Measurement-method appendix: full declared grid, finite estimates, and exact
# duplication of the corresponding main-table cells for the two shared methods.
expected_robustness_methods <- c(
  "primary_irt", "primary_wle", "subject_final_control", "grade_final_all",
  "grade_final_control", "pooled_strict_all", "pooled_strict_control",
  "grade_specific_strict", "grade_strict_control", "chained_strict",
  "direct_strict", "pooled_andy_core", "pooled_broad",
  "dev_schools_final", "chained_provisional", "direct_provisional",
  "ministry_sum_same_sample", "ministry_sum"
)
add_check(
  "measurement_robustness_row_count", nrow(robustness) == 216L,
  paste0("observed=", nrow(robustness), "; expected=216")
)
add_check(
  "measurement_robustness_method_grid",
  setequal(unique(robustness$score_method), expected_robustness_methods) &&
    all(table(robustness$score_method) == 12L),
  paste0("methods=", n_distinct(robustness$score_method),
         "; cells per method=", paste(sort(unique(as.integer(table(robustness$score_method)))), collapse = ","))
)

same_sample_tieout <- robustness %>%
  filter(score_method %in% c("primary_irt", "ministry_sum_same_sample")) %>%
  select(score_method, panel, exposure, cohort, subject_order, n_students) %>%
  pivot_wider(names_from = score_method, values_from = n_students)
add_check(
  "sum_score_same_sample_matches_primary",
  nrow(same_sample_tieout) == 12L &&
    all(same_sample_tieout$primary_irt == same_sample_tieout$ministry_sum_same_sample),
  paste0("matched cells=", sum(same_sample_tieout$primary_irt ==
                                same_sample_tieout$ministry_sum_same_sample),
         "/12; the benchmark must use exactly the primary IRT regression sample"),
  "critical"
)
add_check(
  "measurement_robustness_finite",
  {
    estimable <- filter(robustness, !is.na(b))
    all(is.finite(estimable$b)) && all(is.finite(estimable$se)) &&
      all(estimable$se > 0) && all(estimable$n_pairs >= 2)
  },
  {
    estimable <- filter(robustness, !is.na(b))
    paste0("estimable finite cells=", nrow(estimable), "/", nrow(robustness),
           "; minimum matched-pair clusters=", min(estimable$n_pairs))
  }
)

robustness_coverage <- robustness %>%
  group_by(score_method) %>%
  summarise(
    declared_cell_n = n(), estimable_cell_n = sum(!is.na(b)),
    missing_cell_n = sum(is.na(b)), .groups = "drop"
  )
write_csv(robustness_coverage, file.path(qa, "measurement_robustness_coverage.csv"), na = "")
add_check(
  "measurement_robustness_primary_benchmark_complete",
  robustness_coverage %>%
    filter(score_method %in% c("primary_irt", "ministry_sum")) %>%
    pull(estimable_cell_n) %>%
    { length(.) == 2L && all(. == 12L) },
  "primary IRT and Ministry sum-score benchmark each estimate all 12 headline cells"
)

headline_robustness_reference <- new$headline %>%
  filter(
    score_method %in% c("primary_irt", "ministry_sum"),
    (panel == "A" & cohort == 4L) |
      (panel == "B" & cohort == 4L) |
      (panel == "C" & cohort == 1L)
  ) %>%
  select(score_method, panel, exposure, cohort, subject_order,
         b_main = b, se_main = se, n_students_main = n_students)
robustness_tieout <- robustness %>%
  filter(score_method %in% c("primary_irt", "ministry_sum")) %>%
  inner_join(
    headline_robustness_reference,
    by = c("score_method", "panel", "exposure", "cohort", "subject_order")
  ) %>%
  mutate(b_difference = b - b_main, se_difference = se - se_main,
         student_difference = n_students - n_students_main)
write_csv(robustness_tieout, file.path(qa, "measurement_robustness_main_table_tieout.csv"), na = "")
add_check(
  "measurement_robustness_main_table_tieout",
  nrow(robustness_tieout) == 24L &&
    max(abs(robustness_tieout$b_difference)) < 1e-10 &&
    max(abs(robustness_tieout$se_difference)) < 1e-10 &&
    all(robustness_tieout$student_difference == 0),
  paste0("matched=", nrow(robustness_tieout), "/24; max |db|=",
         signif(max(abs(robustness_tieout$b_difference)), 3),
         "; max |dse|=", signif(max(abs(robustness_tieout$se_difference)), 3),
         "; student mismatches=", sum(robustness_tieout$student_difference != 0))
)

robustness_dispersion <- robustness %>%
  group_by(panel, exposure, cohort, subject_order, subject) %>%
  summarise(
    declared_method_n = n(), estimable_method_n = sum(!is.na(b)),
    minimum_effect = min(b, na.rm = TRUE), maximum_effect = max(b, na.rm = TRUE),
    effect_range = maximum_effect - minimum_effect, .groups = "drop"
  )
write_csv(robustness_dispersion, file.path(qa, "measurement_robustness_dispersion.csv"), na = "")
add_check(
  "measurement_robustness_effect_range", all(abs(robustness$b[!is.na(robustness$b)]) < 4),
  paste0("maximum |effect|=", round(max(abs(robustness$b), na.rm = TRUE), 4),
         "; maximum within-cell method range=", round(max(robustness_dispersion$effect_range), 4)),
  "warning"
)

# Independent tie-out: the new standardized-sum-score branch must reproduce
# the aggregate files that generated the two PDFs shared with the Ministry.
legacy_dir <- file.path(
  normalizePath(paths$y3_root, mustWork = TRUE),
  "5 - Data analysis/05_Endline/Analysis/Tables"
)
legacy <- list(
  headline = read_dta(file.path(legacy_dir, "student_performance_estimates.dta")),
  grade = read_dta(file.path(legacy_dir, "student_performance_by_grade_estimates.dta")) %>%
    filter(grade > 0),
  heterogeneity = read_dta(file.path(legacy_dir, "student_performance_heterogeneity_estimates.dta"))
)
parse_stable_tex <- function(path) {
  lines <- readLines(path, warn = FALSE)
  numeric_cells <- function(line) {
    fields <- strsplit(line, "&", fixed = TRUE)[[1]][-1]
    as.numeric(gsub(",", "", stringr::str_extract(fields, "-?[0-9,]+(?:\\.[0-9]+)?")))
  }
  effect_lines <- grep("^All students", lines)
  student_lines <- grep("^Number of Students", lines)
  school_lines <- grep("^Number of Schools", lines)
  if (length(effect_lines) != 2L || length(student_lines) != 2L || length(school_lines) != 2L) {
    stop("Could not parse delivered stable-sample LaTeX table")
  }
  build_panel <- function(cohort_value, effect_line, student_line, school_line, exposure_n) {
    b <- numeric_cells(lines[[effect_line]])
    se <- numeric_cells(lines[[effect_line + 1L]])
    students <- numeric_cells(lines[[student_line]])
    schools <- numeric_cells(lines[[school_line]])
    expected_n <- exposure_n * 4L
    if (any(lengths(list(b, se, students, schools)) != expected_n)) {
      stop("Unexpected cell count in delivered stable-sample LaTeX table")
    }
    tibble(
      cohort = cohort_value,
      exposure = rep(seq_len(exposure_n), each = 4L),
      subject_order = rep(seq_len(4L), times = exposure_n),
      b = b, se = se, n_students = students, n_schools = schools
    )
  }
  bind_rows(
    build_panel(1L, effect_lines[[1]], student_lines[[1]], school_lines[[1]], 3L),
    build_panel(2L, effect_lines[[2]], student_lines[[2]], school_lines[[2]], 2L)
  )
}
legacy$stable <- parse_stable_tex(file.path(
  legacy_dir, "table-prelim-ITT-3year-stable-sample.tex"
))

keys <- list(
  headline = c("panel", "cohort", "subject_order"),
  stable = c("cohort", "exposure", "subject_order"),
  grade = c("panel", "cohort", "grade", "subject_order"),
  heterogeneity = c("panel", "cohort", "subject_order", "group_order")
)

tieout_rows <- imap_dfr(legacy, function(reference, name) {
  candidate <- new[[name]] %>% filter(score_method == "ministry_sum")
  joined <- inner_join(
    candidate %>% select(all_of(keys[[name]]), b_new = b, se_new = se,
                           n_students_new = n_students, n_schools_new = n_schools),
    reference %>% select(all_of(keys[[name]]), b_ref = b, se_ref = se,
                           n_students_ref = n_students, n_schools_ref = n_schools),
    by = keys[[name]]
  )
  tibble(
    family = name,
    candidate_n = nrow(candidate), reference_n = nrow(reference), matched_n = nrow(joined),
    max_abs_b_diff = max(abs(joined$b_new - joined$b_ref), na.rm = TRUE),
    max_abs_se_diff = max(abs(joined$se_new - joined$se_ref), na.rm = TRUE),
    student_count_mismatch_n = sum(joined$n_students_new != joined$n_students_ref, na.rm = TRUE),
    school_count_mismatch_n = sum(joined$n_schools_new != joined$n_schools_ref, na.rm = TRUE)
  )
})
write_csv(tieout_rows, file.path(qa, "ministry_sum_score_tieout.csv"), na = "")

for (i in seq_len(nrow(tieout_rows))) {
  row <- tieout_rows[i, ]
  tolerance <- if (row$family == "stable") 0.00051 else 1e-8
  pass <- row$matched_n == row$candidate_n && row$matched_n == row$reference_n &&
    row$max_abs_b_diff < tolerance && row$max_abs_se_diff < tolerance &&
    row$student_count_mismatch_n == 0 &&
    row$school_count_mismatch_n == 0
  add_check(
    paste0("ministry_sum_tieout_", row$family), pass,
    paste0("matched=", row$matched_n, "/", row$reference_n,
           "; max |db|=", signif(row$max_abs_b_diff, 3),
           "; max |dse|=", signif(row$max_abs_se_diff, 3),
           "; student mismatches=", row$student_count_mismatch_n,
           "; school mismatches=", row$school_count_mismatch_n)
  )
}

# Exact design identities and no duplicated result cells.
add_check("headline_primary_cells", sum(new$headline$score_method == "primary_irt") == 32L,
          "32 cohort/exposure/outcome cells")
add_check("stable_primary_cells", sum(new$stable$score_method == "primary_irt") == 20L,
          "20 cohort/exposure/outcome cells")
add_check("heterogeneity_primary_cells", sum(new$heterogeneity$score_method == "primary_irt") == 128L,
          "128 cohort/exposure/outcome/subgroup cells")
add_check("grade_primary_cells", sum(new$grade$score_method == "primary_irt") == 172L,
          "172 cohort/exposure/outcome/grade cells, including structurally blank cells")

comparison_keys <- list(
  headline = c("panel", "exposure", "cohort", "subject"),
  stable = c("cohort", "exposure", "subject"),
  grade = c("panel", "exposure", "cohort", "grade", "subject"),
  heterogeneity = c("panel", "exposure", "cohort", "subject", "subgroup")
)
effect_comparison <- imap_dfr(new, function(x, family) {
  x %>%
    select(all_of(comparison_keys[[family]]), score_method, b) %>%
    tidyr::pivot_wider(names_from = score_method, values_from = b) %>%
    mutate(family = family, difference = primary_irt - ministry_sum, .before = 1)
})
write_csv(effect_comparison, file.path(qa, "irt_vs_sum_effect_comparison.csv"), na = "")
comparison_summary <- effect_comparison %>%
  filter(!is.na(primary_irt), !is.na(ministry_sum)) %>%
  group_by(family) %>%
  summarise(
    paired_cell_n = n(), correlation = cor(primary_irt, ministry_sum),
    mean_absolute_difference = mean(abs(difference)),
    maximum_absolute_difference = max(abs(difference)), .groups = "drop"
  )
write_csv(comparison_summary, file.path(qa, "irt_vs_sum_effect_comparison_summary.csv"), na = "")

check_table <- bind_rows(checks)
write_csv(check_table, file.path(qa, "adversarial_review_checks.csv"), na = "")
critical_fail <- sum(check_table$status == "fail" & check_table$severity == "critical")
warning_fail <- sum(check_table$status == "fail" & check_table$severity == "warning")
summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  check_n = nrow(check_table), pass_n = sum(check_table$status == "pass"),
  critical_fail_n = critical_fail, warning_fail_n = warning_fail,
  status = if (critical_fail == 0L) "pass" else "fail"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE),
           file.path(qa, "adversarial_review_summary.json"))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
if (critical_fail > 0L) stop("Adversarial regression review found critical failures")
if (length(args) == 3L) writeLines("regression_qa_complete", args[[3]])
