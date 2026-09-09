#!/usr/bin/env Rscript

# Compare outcome constructions without estimating treatment effects. Level
# scores are standardized within year-wave-subject-grade before pooling, so the
# headline matrix measures student ordering rather than arbitrary node location.
# A second matrix compares Year 3 baseline-to-endline changes.

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
if (length(args) != 2L) stop("Usage: build_measurement_correlations.R config/paths.local.yml config/irt_pipeline.yml")
paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
specification <- yaml::read_yaml(normalizePath(args[[2]], mustWork = TRUE))
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)

is_within <- function(path, root) {
  candidate <- normalizePath(path, mustWork = FALSE); boundary <- normalizePath(root, mustWork = FALSE)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_work_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) stop("Input outside work_root")
  candidate
}
assert_output <- function(path) {
  candidate <- normalizePath(path, mustWork = FALSE)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x) && !is_within(work_root, .x)))) stop("Output inside source root")
  candidate
}
safe_z <- function(x) {
  deviation <- sd(x, na.rm = TRUE)
  if (!is.finite(deviation) || deviation <= 0) return(rep(NA_real_, length(x)))
  (x - mean(x, na.rm = TRUE)) / deviation
}
safe_cor <- function(x, y, method = "pearson") {
  keep <- is.finite(x) & is.finite(y)
  if (sum(keep) < specification$minimum_pairwise_correlation_n || sd(x[keep]) == 0 || sd(y[keep]) == 0) return(NA_real_)
  suppressWarnings(cor(x[keep], y[keep], method = method))
}

derived_dir <- file.path(work_root, "derived/y1_y3_irt")
out_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/06_outcome_construction/correlations"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
scores <- read_csv(assert_work_input(file.path(derived_dir, "multiyear_measurement_robustness_long.csv")), show_col_types = FALSE) %>%
  mutate(
    source_id = as.character(source_id), year = as.integer(year), wave = as.character(wave),
    subject = as.character(subject), administered_grade = as.character(administered_grade),
    method_id = as.character(method_id), score = as.numeric(score)
  ) %>% filter(is.finite(score))

method_order <- read_csv(
  assert_work_input(file.path(work_root, "outputs/y1_y3_irt/06_outcome_construction/measurement_method_registry.csv")),
  show_col_types = FALSE
) %>% filter(eligible_for_comparison == 1L) %>% pull(method_id)
method_order <- method_order[method_order %in% unique(scores$method_id)]
if (length(method_order) < 2L) stop("Fewer than two eligible measurement methods")

level <- scores %>% filter(year == 3L, wave %in% c("baseline", "endline")) %>%
  group_by(method_id, year, wave, subject, administered_grade) %>%
  mutate(within_node_z = safe_z(score)) %>% ungroup() %>%
  select(source_id, year, wave, subject, administered_grade, method_id, score, within_node_z)
level_key <- paste(level$source_id, level$year, level$wave, level$subject, level$administered_grade, level$method_id, sep = "|")
if (anyDuplicated(level_key)) stop("Duplicate method-node keys in level correlations")
level_wide <- level %>% select(-score) %>% pivot_wider(names_from = method_id, values_from = within_node_z)

matrix_for <- function(wide, methods, value_columns = methods) {
  matrix_values <- matrix(NA_real_, nrow = length(methods), ncol = length(methods), dimnames = list(methods, methods))
  n_values <- matrix(0L, nrow = length(methods), ncol = length(methods), dimnames = list(methods, methods))
  spearman <- matrix(NA_real_, nrow = length(methods), ncol = length(methods), dimnames = list(methods, methods))
  for (i in seq_along(methods)) {
    for (j in i:length(methods)) {
      x <- wide[[value_columns[[i]]]]; y <- wide[[value_columns[[j]]]]
      keep <- is.finite(x) & is.finite(y)
      n_values[i, j] <- n_values[j, i] <- sum(keep)
      matrix_values[i, j] <- matrix_values[j, i] <- safe_cor(x, y, "pearson")
      spearman[i, j] <- spearman[j, i] <- safe_cor(x, y, "spearman")
    }
  }
  list(pearson = matrix_values, spearman = spearman, n = n_values)
}
level_matrices <- matrix_for(level_wide, method_order)

changes <- level %>% select(source_id, subject, administered_grade, method_id, wave, score) %>%
  pivot_wider(names_from = wave, values_from = score) %>%
  filter(is.finite(baseline), is.finite(endline)) %>%
  mutate(change = endline - baseline) %>%
  group_by(method_id, subject, administered_grade) %>%
  mutate(within_grade_change_z = safe_z(change)) %>% ungroup()
change_key <- paste(changes$source_id, changes$subject, changes$administered_grade, changes$method_id, sep = "|")
if (anyDuplicated(change_key)) stop("Duplicate method-panel keys in change correlations")
change_wide <- changes %>% select(source_id, subject, administered_grade, method_id, within_grade_change_z) %>%
  pivot_wider(names_from = method_id, values_from = within_grade_change_z)
change_matrices <- matrix_for(change_wide, method_order)

matrix_to_table <- function(x) tibble(method_id = rownames(x)) %>% bind_cols(as_tibble(x, .name_repair = "minimal"))
write_csv(matrix_to_table(level_matrices$pearson), file.path(out_dir, "correlation_matrix_y3_levels_within_node_pearson.csv"), na = "")
write_csv(matrix_to_table(level_matrices$spearman), file.path(out_dir, "correlation_matrix_y3_levels_within_node_spearman.csv"), na = "")
write_csv(matrix_to_table(level_matrices$n), file.path(out_dir, "correlation_matrix_y3_levels_pairwise_n.csv"), na = "")
write_csv(matrix_to_table(change_matrices$pearson), file.path(out_dir, "correlation_matrix_y3_changes_within_grade_pearson.csv"), na = "")
write_csv(matrix_to_table(change_matrices$spearman), file.path(out_dir, "correlation_matrix_y3_changes_within_grade_spearman.csv"), na = "")
write_csv(matrix_to_table(change_matrices$n), file.path(out_dir, "correlation_matrix_y3_changes_pairwise_n.csv"), na = "")

pairwise_details <- list()
counter <- 0L
for (i in seq_along(method_order)) {
  for (j in i:length(method_order)) {
    counter <- counter + 1L
    left <- method_order[[i]]; right <- method_order[[j]]
    pairwise_details[[counter]] <- tibble(
      left_method = left, right_method = right,
      level_common_n = level_matrices$n[i, j], level_pearson = level_matrices$pearson[i, j],
      level_spearman = level_matrices$spearman[i, j], change_common_n = change_matrices$n[i, j],
      change_pearson = change_matrices$pearson[i, j], change_spearman = change_matrices$spearman[i, j],
      level_correlation_below_warning = as.integer(!is.na(level_matrices$pearson[i, j]) && level_matrices$pearson[i, j] < specification$correlation_warning_threshold),
      change_correlation_below_warning = as.integer(!is.na(change_matrices$pearson[i, j]) && change_matrices$pearson[i, j] < specification$correlation_warning_threshold),
      thresholds_are_warning_flags_only = 1L
    )
  }
}
pairwise_details <- bind_rows(pairwise_details)
write_csv(pairwise_details, file.path(out_dir, "measurement_method_pairwise_summary.csv"), na = "")

node_pairwise <- list(); counter <- 0L
node_groups <- level %>% distinct(year, wave, subject, administered_grade)
for (node_index in seq_len(nrow(node_groups))) {
  node <- node_groups[node_index, ]
  node_data <- level %>% semi_join(node, by = c("year", "wave", "subject", "administered_grade")) %>%
    select(source_id, method_id, score) %>% pivot_wider(names_from = method_id, values_from = score)
  present <- intersect(method_order, names(node_data))
  if (length(present) < 2L) next
  for (i in seq_along(present)) {
    for (j in i:length(present)) {
      left <- present[[i]]; right <- present[[j]]; keep <- is.finite(node_data[[left]]) & is.finite(node_data[[right]])
      counter <- counter + 1L
      node_pairwise[[counter]] <- bind_cols(node, tibble(
        left_method = left, right_method = right, common_n = sum(keep),
        pearson = safe_cor(node_data[[left]], node_data[[right]], "pearson"),
        spearman = safe_cor(node_data[[left]], node_data[[right]], "spearman"),
        mean_left = mean(node_data[[left]][keep]), mean_right = mean(node_data[[right]][keep]),
        sd_left = sd(node_data[[left]][keep]), sd_right = sd(node_data[[right]][keep])
      ))
    }
  }
}
write_csv(bind_rows(node_pairwise), file.path(out_dir, "measurement_method_node_pairwise_diagnostics.csv"), na = "")

plot_matrix <- function(matrix_values, path, title) {
  concise_label <- function(x) {
    x <- sub("^concurrent_subject_all_final$", "PRIMARY | subject | all | final", x)
    x <- sub("^concurrent__grade_specific__", "Concurrent | grade | ", x)
    x <- sub("^concurrent__subject_pooled__", "Concurrent | subject | ", x)
    x <- sub("^direct__", "Direct | ", x)
    x <- sub("^chained__", "Chained | ", x)
    x <- sub("^plain_code__", "Sum(code z) | ", x)
    x <- sub("^plain_report_grade__", "Sum(grade z) | ", x)
    x <- gsub("comparison_only", "controls", x, fixed = TRUE)
    x <- gsub("development_schools", "school-dev", x, fixed = TRUE)
    x <- gsub("final_purified_math_bridge5", "final", x, fixed = TRUE)
    x <- gsub("provisional_id_stress_test", "ID-only stress", x, fixed = TRUE)
    x <- gsub("strict_summary", "strict", x, fixed = TRUE)
    x <- gsub("broad_purification", "broad", x, fixed = TRUE)
    x <- gsub("listed_consistent_metadata", "listed+consistent", x, fixed = TRUE)
    x <- gsub("listed_panel", "listed", x, fixed = TRUE)
    x <- gsub("all_panel", "all", x, fixed = TRUE)
    x <- gsub("__", " | ", x, fixed = TRUE)
    x
  }
  png(path, width = 2600, height = 2300, res = 180)
  on.exit(dev.off(), add = TRUE)
  par(mar = c(12, 12, 5, 2), bg = "white")
  display <- t(matrix_values[nrow(matrix_values):1, , drop = FALSE])
  missing <- display; missing[] <- ifelse(is.na(display), 1, NA_real_)
  image(seq_len(ncol(matrix_values)), seq_len(nrow(matrix_values)), missing,
        zlim = c(0, 1), col = "#E5E7EB", axes = FALSE, xlab = "", ylab = "")
  image(seq_len(ncol(matrix_values)), seq_len(nrow(matrix_values)), display,
        zlim = c(0.85, 1), col = hcl.colors(100, "YlGnBu", rev = TRUE), axes = FALSE,
        xlab = "", ylab = "", add = TRUE)
  axis(1, at = seq_len(ncol(matrix_values)), labels = concise_label(colnames(matrix_values)), las = 2, cex.axis = 0.58)
  axis(2, at = seq_len(nrow(matrix_values)), labels = rev(concise_label(rownames(matrix_values))), las = 2, cex.axis = 0.58)
  title(main = title, line = 2.4)
  mtext("Pearson r; focused color scale 0.85–1.00; gray = fewer than 100 common records", side = 3, line = 0.6, cex = 0.75, col = "#4B5563")
  box()
}
plot_matrix(level_matrices$pearson, file.path(out_dir, "correlation_matrix_y3_levels.png"), "Y3 measurement correlations: levels standardized within node")
plot_matrix(change_matrices$pearson, file.path(out_dir, "correlation_matrix_y3_changes.png"), "Y3 measurement correlations: changes standardized within grade")

off_diagonal <- pairwise_details %>% filter(left_method != right_method)
primary_pairs <- off_diagonal %>% filter(left_method == specification$primary_method | right_method == specification$primary_method)
primary_pairs <- primary_pairs %>% mutate(
  other_method = if_else(left_method == specification$primary_method, right_method, left_method),
  comparison_class = case_when(
    startsWith(other_method, "plain_") ~ "standardized_sum",
    grepl("provisional_id", other_method, fixed = TRUE) ~ "provisional_id_stress_test",
    TRUE ~ "defensible_irt"
  )
)
safe_minimum <- function(x) if (length(x) && any(is.finite(x))) min(x, na.rm = TRUE) else NA_real_
defensible_irt_pairs <- primary_pairs %>% filter(comparison_class == "defensible_irt")
sum_pairs <- primary_pairs %>% filter(comparison_class == "standardized_sum")
summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), eligible_method_n = length(method_order),
  y3_level_record_n = nrow(level), y3_complete_change_record_n = nrow(changes),
  minimum_primary_level_correlation = min(primary_pairs$level_pearson, na.rm = TRUE),
  minimum_primary_change_correlation = min(primary_pairs$change_pearson, na.rm = TRUE),
  primary_level_warning_n = sum(primary_pairs$level_correlation_below_warning, na.rm = TRUE),
  primary_change_warning_n = sum(primary_pairs$change_correlation_below_warning, na.rm = TRUE),
  minimum_primary_defensible_irt_level_correlation = safe_minimum(defensible_irt_pairs$level_pearson),
  minimum_primary_defensible_irt_change_correlation = safe_minimum(defensible_irt_pairs$change_pearson),
  minimum_primary_standardized_sum_level_correlation = safe_minimum(sum_pairs$level_pearson),
  minimum_primary_standardized_sum_change_correlation = safe_minimum(sum_pairs$change_pearson),
  correlation_warning_threshold = specification$correlation_warning_threshold,
  regression_executed = 0L
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "measurement_correlation_summary.json"))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
