#!/usr/bin/env Rscript

# Compare full-form and provisional short-form EAP ability estimates.
#
# Models are calibrated on one deterministic half of schools and used to score
# the other half; the split is then reversed.  Short-form scores use the same
# fitted item parameters as the corresponding full-form score, with omitted
# responses set to missing.  No student identifiers are written to output.

suppressPackageStartupMessages({
  library(dplyr)
  library(haven)
  library(jsonlite)
  library(mirt)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: validate_short_form_scores.R config/paths.local.yml")
paths <- yaml::read_yaml(args[[1]])$dropbox
set.seed(20260816)

endline_path <- file.path(
  paths$y3_root,
  "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta"
)
work <- paths$work_root
registry_path <- file.path(work, "derived/y3_ministry/y3_item_version_registry.csv")
plan_path <- file.path(
  work,
  "outputs/y3_ministry/05_short_form/y4_baseline_short_form_item_plan.csv"
)
summary_path <- file.path(
  work,
  "outputs/y3_ministry/05_short_form/y4_baseline_short_form_summary.csv"
)
out_dir <- file.path(work, "outputs/y3_ministry/05_short_form/score_validation")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

data <- read_dta(endline_path)
registry <- read_csv(registry_path, show_col_types = FALSE) %>%
  filter(wave == "endline") %>%
  mutate(form_grade = as.character(form_grade))
plan <- read_csv(plan_path, show_col_types = FALSE) %>%
  mutate(grade = as.character(grade))
short_summary <- read_csv(summary_path, show_col_types = FALSE) %>%
  mutate(grade = as.character(grade))

label_character <- function(x) as.character(haven::as_factor(x))

prepare_form <- function(source, form_map) {
  item_vars <- intersect(unique(form_map$item_id), names(source))
  form <- source %>%
    filter(
      label_character(subject) == first(form_map$subject),
      label_character(grade) == first(form_map$form_grade)
    ) %>%
    mutate(.source_row = row_number())
  if (!nrow(form)) return(form)
  answered <- rowSums(sapply(form[item_vars], function(x) {
    tag <- haven::na_tag(x)
    !is.na(x) | (!is.na(tag) & tag == "a")
  }))
  duration_value <- if ("duration" %in% names(form)) {
    suppressWarnings(as.numeric(form$duration))
  } else {
    0
  }
  id_key <- as.character(form$id_student_panel)
  missing_key <- is.na(id_key) | id_key == ""
  id_key[missing_key] <- paste0("__row_", form$.source_row[missing_key])
  form %>%
    mutate(.id_key = id_key, .answered = answered, .duration_value = duration_value) %>%
    arrange(.id_key, desc(.answered), desc(.duration_value), .source_row) %>%
    distinct(.id_key, .keep_all = TRUE) %>%
    arrange(.source_row) %>%
    select(-.id_key, -.answered, -.duration_value)
}

binary_items <- function(form, item_ids) {
  items <- intersect(item_ids, names(form))
  keep <- map_lgl(items, function(item) {
    values <- unique(as.numeric(form[[item]][!is.na(form[[item]])]))
    length(values) > 0 && all(values %in% c(0, 1))
  })
  items[keep]
}

score_matrix <- function(form, items) {
  matrix <- sapply(form[items], function(x) as.numeric(!is.na(x) & as.numeric(x) == 1))
  if (length(items) == 1) {
    matrix <- matrix(matrix, ncol = 1, dimnames = list(NULL, items))
  }
  matrix
}

fit_model <- function(matrix) {
  p <- colMeans(matrix)
  eligible <- names(p)[p >= 0.005 & p <= 0.995]
  calibration <- matrix[, eligible, drop = FALSE]
  if (nrow(calibration) < 150 || ncol(calibration) < 10) {
    return(list(model = NULL, items = eligible, model_type = "not fit", error = "insufficient rows/items"))
  }
  two <- tryCatch(
    mirt(calibration, 1, itemtype = "2PL", verbose = FALSE, technical = list(NCYCLES = 1000)),
    error = function(e) e
  )
  if (!inherits(two, "error") && isTRUE(extract.mirt(two, "converged"))) {
    return(list(model = two, items = eligible, model_type = "2PL", error = ""))
  }
  rasch <- tryCatch(
    mirt(calibration, 1, itemtype = "Rasch", verbose = FALSE, technical = list(NCYCLES = 1000)),
    error = function(e) e
  )
  if (!inherits(rasch, "error") && isTRUE(extract.mirt(rasch, "converged"))) {
    return(list(model = rasch, items = eligible, model_type = "Rasch", error = ""))
  }
  error <- paste(
    if (inherits(two, "error")) conditionMessage(two) else "2PL did not converge",
    if (inherits(rasch, "error")) conditionMessage(rasch) else "Rasch did not converge",
    sep = "; "
  )
  list(model = NULL, items = eligible, model_type = "not fit", error = error)
}

extract_scores <- function(model, responses) {
  values <- fscores(
    model,
    method = "EAP",
    response.pattern = responses,
    full.scores = TRUE,
    full.scores.SE = TRUE
  )
  values <- as.data.frame(values)
  tibble(
    theta = as.numeric(values[["F1"]]),
    se = if ("SE_F1" %in% names(values)) as.numeric(values[["SE_F1"]]) else NA_real_
  )
}

safe_cor <- function(x, y, method = "pearson") {
  keep <- is.finite(x) & is.finite(y)
  if (sum(keep) < 3 || sd(x[keep]) == 0 || sd(y[keep]) == 0) return(NA_real_)
  suppressWarnings(cor(x[keep], y[keep], method = method))
}

percentile_rank <- function(x) {
  if (length(x) <= 1) return(rep(0.5, length(x)))
  (rank(x, ties.method = "average") - 1) / (length(x) - 1)
}

quintile_from_percentile <- function(x) pmin(5L, floor(x * 5) + 1L)

comparison_metrics <- function(rows) {
  rows <- rows %>% filter(is.finite(full_theta), is.finite(short_theta))
  if (nrow(rows) < 3) return(tibble())
  full_q <- quintile_from_percentile(rows$full_percentile)
  short_q <- quintile_from_percentile(rows$short_percentile)
  full_top <- rows$full_percentile >= 0.90
  short_top <- rows$short_percentile >= 0.90
  full_bottom <- rows$full_percentile <= 0.10
  short_bottom <- rows$short_percentile <= 0.10
  tibble(
    n = nrow(rows),
    pearson_correlation = safe_cor(rows$full_theta, rows$short_theta),
    spearman_correlation = safe_cor(rows$full_theta, rows$short_theta, "spearman"),
    mean_short_minus_full = mean(rows$short_theta - rows$full_theta),
    rmse = sqrt(mean((rows$short_theta - rows$full_theta)^2)),
    median_absolute_difference = median(abs(rows$short_theta - rows$full_theta)),
    short_to_full_sd_ratio = sd(rows$short_theta) / sd(rows$full_theta),
    mean_full_posterior_se = mean(rows$full_se, na.rm = TRUE),
    mean_short_posterior_se = mean(rows$short_se, na.rm = TRUE),
    posterior_se_increase_pct = 100 * (mean(rows$short_se, na.rm = TRUE) / mean(rows$full_se, na.rm = TRUE) - 1),
    exact_quintile_agreement_pct = 100 * mean(full_q == short_q),
    within_one_quintile_pct = 100 * mean(abs(full_q - short_q) <= 1),
    mean_absolute_percentile_shift = mean(abs(rows$full_percentile - rows$short_percentile)),
    top_decile_retained_pct = 100 * sum(full_top & short_top) / max(sum(full_top), 1),
    bottom_decile_retained_pct = 100 * sum(full_bottom & short_bottom) / max(sum(full_bottom), 1)
  )
}

forms <- registry %>%
  distinct(subject, form_grade) %>%
  arrange(subject, as.numeric(form_grade))

student_rows <- list()
model_rows <- list()
missing_rows <- list()
student_counter <- 0L
model_counter <- 0L
missing_counter <- 0L

for (form_index in seq_len(nrow(forms))) {
  subject_value <- forms$subject[form_index]
  grade_value <- forms$form_grade[form_index]
  message(sprintf("FORM %d/%d: %s grade %s", form_index, nrow(forms), subject_value, grade_value))
  form_map <- registry %>%
    filter(subject == subject_value, form_grade == grade_value) %>%
    distinct(item_id, .keep_all = TRUE)
  form <- prepare_form(data, form_map)
  full_items <- binary_items(form, form_map$item_id)
  full_matrix <- score_matrix(form, full_items)
  planned_items <- plan %>%
    filter(subject == subject_value, grade == grade_value) %>%
    pull(item_id) %>%
    unique()
  scorable_planned <- intersect(planned_items, full_items)
  missing_planned <- setdiff(planned_items, full_items)
  if (length(missing_planned)) {
    missing_counter <- missing_counter + 1L
    missing_rows[[missing_counter]] <- tibble(
      subject = subject_value,
      grade = grade_value,
      item_id = missing_planned,
      reason = "selected historical/new item was not administered in this Year 3 endline form"
    )
  }

  school_value <- as.character(form$school)
  missing_school <- is.na(school_value) | school_value == ""
  school_value[missing_school] <- paste0("__missing_school_", form$.source_row[missing_school])
  schools <- sort(unique(school_value))
  fold_lookup <- set_names(rep(c("A", "B"), length.out = length(schools)), schools)
  fold <- unname(fold_lookup[school_value])

  for (validation_fold in c("A", "B")) {
    validation <- fold == validation_fold
    training <- !validation
    fit <- fit_model(full_matrix[training, , drop = FALSE])
    short_items <- intersect(scorable_planned, fit$items)
    model_counter <- model_counter + 1L
    model_rows[[model_counter]] <- tibble(
      subject = subject_value,
      grade = grade_value,
      validation_fold = validation_fold,
      training_student_n = sum(training),
      validation_student_n = sum(validation),
      full_calibrated_item_n = length(fit$items),
      planned_short_item_n = length(planned_items),
      scorable_planned_item_n = length(scorable_planned),
      scored_short_item_n = length(short_items),
      unavailable_planned_item_n = length(missing_planned),
      model_type = fit$model_type,
      converged = as.integer(!is.null(fit$model)),
      error = fit$error
    )
    if (is.null(fit$model) || length(short_items) < 5) next

    validation_matrix <- full_matrix[validation, fit$items, drop = FALSE]
    short_matrix <- validation_matrix
    short_matrix[, setdiff(fit$items, short_items)] <- NA_real_
    full_score <- extract_scores(fit$model, validation_matrix)
    short_score <- extract_scores(fit$model, short_matrix)

    # Put the two cross-fit folds on a common within-form metric using only the
    # validation fold's full-form location and scale.  The same transformation
    # is applied to the short score and both posterior SEs.
    location <- mean(full_score$theta)
    scale <- sd(full_score$theta)
    if (!is.finite(scale) || scale <= 0) scale <- 1
    treated_value <- suppressWarnings(as.numeric(form$treated[validation]))
    full_theta <- (full_score$theta - location) / scale
    short_theta <- (short_score$theta - location) / scale
    full_percentile <- percentile_rank(full_theta)
    short_percentile <- percentile_rank(short_theta)
    student_counter <- student_counter + 1L
    student_rows[[student_counter]] <- tibble(
      subject = subject_value,
      grade = grade_value,
      validation_fold = validation_fold,
      treated = treated_value,
      full_theta = full_theta,
      short_theta = short_theta,
      full_se = full_score$se / scale,
      short_se = short_score$se / scale,
      full_percentile = full_percentile,
      short_percentile = short_percentile
    )
  }
}

scores <- bind_rows(student_rows)
models <- bind_rows(model_rows)
missing_plan_items <- bind_rows(missing_rows)

sample_rows <- bind_rows(
  scores %>% mutate(sample = "all students"),
  scores %>% filter(treated == 0) %>% mutate(sample = "control students")
)

form_summary <- sample_rows %>%
  group_by(subject, grade, sample) %>%
  group_modify(~ comparison_metrics(.x)) %>%
  ungroup() %>%
  left_join(
    models %>%
      group_by(subject, grade) %>%
      summarize(
        planned_short_item_n = first(planned_short_item_n),
        scorable_planned_item_n = first(scorable_planned_item_n),
        unavailable_planned_item_n = first(unavailable_planned_item_n),
        scored_short_item_n_min = min(scored_short_item_n),
        scored_short_item_n_max = max(scored_short_item_n),
        model_types = paste(sort(unique(model_type)), collapse = ";"),
        both_school_folds_converged = as.integer(sum(converged) == 2),
        .groups = "drop"
      ),
    by = c("subject", "grade")
  ) %>%
  left_join(
    short_summary %>%
      select(subject, grade, current_item_n, provisional_minimum_item_n),
    by = c("subject", "grade")
  ) %>%
  arrange(sample, subject, as.numeric(grade))

quintile_summary <- sample_rows %>%
  mutate(full_quintile = quintile_from_percentile(full_percentile)) %>%
  group_by(subject, grade, sample, full_quintile) %>%
  summarize(
    n = n(),
    mean_full_theta = mean(full_theta),
    mean_short_theta = mean(short_theta),
    mean_short_minus_full = mean(short_theta - full_theta),
    rmse = sqrt(mean((short_theta - full_theta)^2)),
    mean_absolute_percentile_shift = mean(abs(full_percentile - short_percentile)),
    .groups = "drop"
  )

subject_quintile_summary <- quintile_summary %>%
  mutate(weight_n = n) %>%
  group_by(subject, sample, full_quintile) %>%
  summarize(
    n = sum(weight_n),
    mean_full_theta = weighted.mean(mean_full_theta, weight_n),
    mean_short_theta = weighted.mean(mean_short_theta, weight_n),
    mean_short_minus_full = weighted.mean(mean_short_minus_full, weight_n),
    rmse = sqrt(weighted.mean(rmse^2, weight_n)),
    mean_absolute_percentile_shift = weighted.mean(mean_absolute_percentile_shift, weight_n),
    .groups = "drop"
  ) %>%
  arrange(sample, subject, full_quintile)

subject_summary <- form_summary %>%
  group_by(subject, sample) %>%
  summarize(
    grade_forms_n = n(),
    student_form_n = sum(n),
    weighted_mean_form_pearson = weighted.mean(pearson_correlation, pmax(n - 3, 1), na.rm = TRUE),
    minimum_form_pearson = min(pearson_correlation, na.rm = TRUE),
    maximum_form_pearson = max(pearson_correlation, na.rm = TRUE),
    weighted_mean_form_spearman = weighted.mean(spearman_correlation, pmax(n - 3, 1), na.rm = TRUE),
    weighted_exact_quintile_agreement_pct = weighted.mean(exact_quintile_agreement_pct, n, na.rm = TRUE),
    weighted_within_one_quintile_pct = weighted.mean(within_one_quintile_pct, n, na.rm = TRUE),
    weighted_top_decile_retained_pct = weighted.mean(top_decile_retained_pct, n, na.rm = TRUE),
    weighted_bottom_decile_retained_pct = weighted.mean(bottom_decile_retained_pct, n, na.rm = TRUE),
    weighted_mean_absolute_percentile_shift = weighted.mean(mean_absolute_percentile_shift, n, na.rm = TRUE),
    weighted_posterior_se_increase_pct = weighted.mean(posterior_se_increase_pct, n, na.rm = TRUE),
    planned_item_n_range = paste0(min(planned_short_item_n), "-", max(planned_short_item_n)),
    currently_scorable_item_n_range = paste0(min(scorable_planned_item_n), "-", max(scorable_planned_item_n)),
    .groups = "drop"
  ) %>%
  arrange(sample, subject)

write_csv(form_summary, file.path(out_dir, "y4_short_vs_full_by_subject_grade.csv"), na = "")
write_csv(subject_summary, file.path(out_dir, "y4_short_vs_full_by_subject.csv"), na = "")
write_csv(quintile_summary, file.path(out_dir, "y4_short_vs_full_by_ability_quintile.csv"), na = "")
write_csv(subject_quintile_summary, file.path(out_dir, "y4_short_vs_full_by_subject_ability_quintile.csv"), na = "")
write_csv(models, file.path(out_dir, "y4_short_vs_full_model_audit.csv"), na = "")
write_csv(missing_plan_items, file.path(out_dir, "y4_short_vs_full_unavailable_plan_items.csv"), na = "")

run_summary <- list(
  status = if (all(models$converged == 1)) "completed" else "completed with model failures",
  validation_design = "Deterministic two-fold school-held-out calibration and scoring; each fold scored with parameters estimated from the other schools.",
  full_score = "EAP from all eligible binary items in the current Year 3 endline form.",
  short_score = "EAP on the same fixed full-form metric after masking every response not selected for the provisional short form.",
  missing_response_rule = "Incorrect, tagged don't-know, and untagged nonresponse score zero, matching the Year 3 audit.",
  subject_aggregation = "Subject summaries are weighted summaries of grade-specific comparisons; no vertical scale across grades is assumed.",
  treatment_policy = "Selection was treatment-blind. Results are reported for all students and, as a sensitivity, for control students only.",
  exact_form_limitation = "Historical/new additions were not administered in the target Year 3 grade and therefore cannot be included in an observed same-student comparison before the next pilot.",
  testlet_limitation = "The short-form plan remains provisional until passage, image, oral-task, and rubric bundles are confirmed.",
  form_n = nrow(forms),
  model_fold_n = nrow(models),
  converged_model_fold_n = sum(models$converged == 1),
  scored_student_form_n = nrow(scores),
  unavailable_plan_item_rows = nrow(missing_plan_items),
  output_files = c(
    "y4_short_vs_full_by_subject_grade.csv",
    "y4_short_vs_full_by_subject.csv",
    "y4_short_vs_full_by_ability_quintile.csv",
    "y4_short_vs_full_by_subject_ability_quintile.csv",
    "y4_short_vs_full_model_audit.csv",
    "y4_short_vs_full_unavailable_plan_items.csv"
  )
)
writeLines(
  toJSON(run_summary, pretty = TRUE, auto_unbox = TRUE),
  file.path(out_dir, "y4_short_vs_full_run_summary.json")
)
cat(toJSON(run_summary, pretty = TRUE, auto_unbox = TRUE), "\n")
