#!/usr/bin/env Rscript

# Build aggregate, Ministry-facing comparison views from the validated result
# grid. This script never reads or writes record-level data.

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tidyr)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("Usage: build_ministry_multiyear_irt_report.R config/paths.local.yml")
}

paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
normalize_for_guard <- function(path) normalizePath(path, mustWork = FALSE)
is_within <- function(path, root) {
  candidate <- normalize_for_guard(path)
  boundary <- normalize_for_guard(root)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) stop("Input outside work_root: ", candidate)
  candidate
}
assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) {
    stop("Output must be below work_root")
  }
  candidate
}

out_dir <- assert_output(file.path(
  work_root, "outputs/y1_y3_irt/07_ministry_multiyear_results"
))
table_names <- c("headline", "grade", "heterogeneity", "stable")
comparisons <- map_dfr(table_names, function(table_name) {
  read_csv(
    assert_input(file.path(out_dir, paste0("ministry_", table_name, "_irt_comparison.csv"))),
    show_col_types = FALSE
  ) %>%
    mutate(table_name = table_name)
})

method_order <- c(
  "ministry_sum",
  "irt_chained_strict",
  "irt_pooled_strict_all",
  "irt_pooled_strict_control",
  "irt_grade_specific_strict",
  "irt_chained_provisional"
)
method_labels <- c(
  ministry_sum = "Ministry standardized sum score",
  irt_chained_strict = "IRT chained, strict anchors",
  irt_pooled_strict_all = "IRT subject pooled, all-sample calibration",
  irt_pooled_strict_control = "IRT subject pooled, comparison-only calibration",
  irt_grade_specific_strict = "IRT grade-specific pooled calibration",
  irt_chained_provisional = "IRT chained, provisional anchors"
)

key_fields <- c(
  "table_name", "panel", "exposure", "cohort", "pooled", "subject_order",
  "grade", "group_order", "subject", "subgroup"
)

for (table_name in table_names) {
  current <- comparisons %>%
    filter(.data$table_name == .env$table_name) %>%
    mutate(score_method = factor(score_method, levels = method_order)) %>%
    select(
      any_of(key_fields), score_method, b, se, p, n_students, n_schools,
      ministry_b, ministry_se, ministry_p, delta_b,
      same_sample_sum_b, same_sample_sum_se, same_sample_sum_p,
      delta_same_sample_sum_b, result_status
    ) %>%
    pivot_wider(
      names_from = score_method,
      values_from = c(
        b, se, p, n_students, n_schools, delta_b,
        delta_same_sample_sum_b, result_status
      ),
      names_glue = "{score_method}_{.value}"
    ) %>%
    arrange(panel, cohort, grade, group_order, subject_order)
  write_csv(
    current,
    assert_output(file.path(out_dir, paste0("ministry_", table_name, "_irt_comparison_wide.csv"))),
    na = ""
  )
}

write_csv(
  comparisons %>%
    mutate(
      score_method_label = unname(method_labels[score_method]),
      method_order = match(score_method, method_order)
    ) %>%
    arrange(table_name, panel, cohort, grade, group_order, subject_order, method_order),
  assert_output(file.path(out_dir, "ministry_all_groups_irt_comparison_long.csv")),
  na = ""
)

summary_table <- read_csv(
  assert_input(file.path(out_dir, "ministry_irt_comparison_summary.csv")),
  show_col_types = FALSE
)
tieout <- read_csv(
  assert_input(file.path(out_dir, "ministry_sum_score_reference_tieout.csv")),
  show_col_types = FALSE
)
validation <- read_csv(
  assert_input(file.path(out_dir, "ministry_multiyear_validation_checks.csv")),
  show_col_types = FALSE
)

fmt <- function(x, digits = 3) ifelse(is.na(x), "—", formatC(x, digits = digits, format = "f"))
md_row <- function(values) paste0("| ", paste(values, collapse = " | "), " |")

headline <- comparisons %>%
  filter(table_name == "headline", score_method %in% c(
    "ministry_sum", "irt_pooled_strict_all", "irt_chained_strict"
  )) %>%
  select(panel, exposure, cohort, pooled, subject_order, subject, score_method, b, se) %>%
  pivot_wider(names_from = score_method, values_from = c(b, se)) %>%
  mutate(
    group = if_else(pooled == 1, paste0("Pooled, ", exposure, " year(s)"),
                    paste0("Cohort ", cohort, ", ", exposure, " year(s)")),
    delta = b_irt_pooled_strict_all - b_ministry_sum
  ) %>%
  arrange(panel, pooled, cohort, subject_order)

headline_lines <- c(
  "| Group | Subject | Ministry sum | Pooled strict-all IRT | Difference | Chained strict IRT |",
  "|---|---:|---:|---:|---:|---:|",
  pmap_chr(headline, function(...) {
    row <- list(...)
    md_row(c(
      row$group,
      str_to_title(row$subject),
      paste0(fmt(row$b_ministry_sum), " (", fmt(row$se_ministry_sum), ")"),
      paste0(fmt(row$b_irt_pooled_strict_all), " (", fmt(row$se_irt_pooled_strict_all), ")"),
      fmt(row$delta),
      paste0(fmt(row$b_irt_chained_strict), " (", fmt(row$se_irt_chained_strict), ")")
    ))
  })
)

stable_headline <- comparisons %>%
  filter(table_name == "stable", score_method %in% c(
    "ministry_sum", "irt_pooled_strict_all", "irt_chained_strict"
  )) %>%
  select(cohort, exposure, subject_order, subject, score_method, b, se) %>%
  pivot_wider(names_from = score_method, values_from = c(b, se)) %>%
  mutate(
    group = paste0("Cohort ", cohort, ", ", exposure, " year(s)"),
    delta = b_irt_pooled_strict_all - b_ministry_sum
  ) %>%
  arrange(cohort, exposure, subject_order)
stable_lines <- c(
  "| Group | Subject | Recomputed stable-sample sum | Pooled strict-all IRT | Difference | Chained strict IRT |",
  "|---|---:|---:|---:|---:|---:|",
  pmap_chr(stable_headline, function(...) {
    row <- list(...)
    md_row(c(
      row$group,
      str_to_title(row$subject),
      paste0(fmt(row$b_ministry_sum), " (", fmt(row$se_ministry_sum), ")"),
      paste0(fmt(row$b_irt_pooled_strict_all), " (", fmt(row$se_irt_pooled_strict_all), ")"),
      fmt(row$delta),
      paste0(fmt(row$b_irt_chained_strict), " (", fmt(row$se_irt_chained_strict), ")")
    ))
  })
)

summary_lines <- c(
  "| Result family | IRT method | Cells compared | Mean absolute difference | Maximum difference | Correlation | Same sign |",
  "|---|---|---:|---:|---:|---:|---:|",
  pmap_chr(summary_table, function(...) {
    row <- list(...)
    md_row(c(
      str_to_title(row$table_name),
      unname(method_labels[row$score_method]),
      as.character(row$compared_cell_n),
      fmt(row$mean_absolute_effect_difference),
      fmt(row$maximum_absolute_effect_difference),
      fmt(row$effect_correlation),
      fmt(row$same_sign_share)
    ))
  })
)

strict_largest <- comparisons %>%
  filter(
    score_method == "irt_pooled_strict_all",
    result_status == "compared",
    !is.na(abs_delta_same_sample_sum_b)
  ) %>%
  arrange(desc(abs_delta_same_sample_sum_b)) %>%
  slice_head(n = 15) %>%
  mutate(
    cell = case_when(
      table_name == "grade" & pooled == 1 ~ paste0("Pooled E", exposure, ", grade ", grade, ", ", subject),
      table_name == "grade" ~ paste0("C", cohort, " E", exposure, ", grade ", grade, ", ", subject),
      table_name == "heterogeneity" & pooled == 1 ~ paste0("Pooled E", exposure, ", ", subgroup, ", ", subject),
      table_name == "heterogeneity" ~ paste0("C", cohort, " E", exposure, ", ", subgroup, ", ", subject),
      table_name == "stable" ~ paste0("C", cohort, " E", exposure, ", ", subject),
      pooled == 1 ~ paste0("Pooled E", exposure, ", ", subject),
      TRUE ~ paste0("C", cohort, " E", exposure, ", ", subject)
    )
  )
largest_lines <- c(
  "| Result family | Cell | Same-sample sum | Pooled strict-all IRT | Absolute difference |",
  "|---|---|---:|---:|---:|",
  pmap_chr(strict_largest, function(...) {
    row <- list(...)
    md_row(c(
      str_to_title(row$table_name), row$cell,
      fmt(row$same_sample_sum_b), fmt(row$b), fmt(row$abs_delta_same_sample_sum_b)
    ))
  })
)

tieout_text <- paste0(
  sum(tieout$exact_to_stored_precision), "/", nrow(tieout),
  " result families reproduce the saved Ministry sum-score reference at the declared precision."
)
validation_text <- paste0(
  sum(validation$pass == 1L), "/", nrow(validation), " validation checks pass."
)

report <- c(
  "# Ministry standardized-sum-score versus IRT reconciliation",
  "",
  paste0("Generated: ", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  "",
  "Status: development analysis; anchor review and source canonicality approval remain pending.",
  "",
  "## Scope",
  "",
  paste0(
    "This package covers every reported cohort-by-exposure headline cell, baseline-grade cell, ",
    "gender/baseline-performance subgroup cell, and stable-sample headline cell. Year 1 uses the ",
    "delivered Year 1 IRT scores unchanged. All later IRT scores are expressed on that fixed Year 1 ",
    "endline-comparison scale. Non-binary items are excluded from estimation."
  ),
  "",
  "## Benchmark and validation",
  "",
  paste0("- ", tieout_text),
  paste0("- ", validation_text),
  paste0(
    "- The pooled strict-all subject models implement the current joint Y2–Y3 calibration candidate. ",
    "The chained strict model is shown alongside it as the transparent link-path sensitivity."
  ),
  "- Full cell-level results for every method are in the long and wide CSV files in this folder.",
  "",
  "## Headline comparison",
  "",
  headline_lines,
  "",
  "## Stable-sample headline comparison",
  "",
  stable_lines,
  "",
  "## Agreement with the recomputed same-sample standardized sum score",
  "",
  summary_lines,
  "",
  "## Largest pooled strict-all differences from the same-sample sum score",
  "",
  largest_lines,
  "",
  "## Interpretation safeguards",
  "",
  "- IRT methods change the outcome metric, not the matched difference-in-differences design.",
  paste0(
    "- The saved stable-table sample counts reproduce exactly, but its coefficient rows do not reproduce ",
    "from the same standardized-sum-score panels. Stable IRT comparisons therefore use the recomputed ",
    "same-sample sum score and retain the published values only as a flagged lineage comparison."
  ),
  "- Missing grade estimates are retained as missing and are not converted to zeros.",
  "- Estimates were not used to choose anchors or remove items.",
  "- The provisional-anchor chain is a sensitivity analysis only.",
  "- These files contain aggregate estimates only and no student or school identifiers."
)

writeLines(
  report,
  assert_output(file.path(out_dir, "MINISTRY_IRT_RESULTS_RECONCILIATION.md"))
)

cat(
  "Wrote aggregate all-group comparison views and Ministry reconciliation report to:\n",
  out_dir, "\n"
)
