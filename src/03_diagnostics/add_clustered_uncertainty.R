#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(haven)
  library(purrr)
  library(readr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: add_clustered_uncertainty.R config/paths.local.yml")
paths <- yaml::read_yaml(args[[1]])$dropbox
set.seed(20260804)
y3 <- paths$y3_root
work <- paths$work_root
files <- c(
  baseline = file.path(y3, "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta"),
  pilot = file.path(y3, "4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta"),
  endline = file.path(y3, "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta")
)
registry <- read_csv(file.path(work, "derived/y3_ministry/y3_item_version_registry.csv"), show_col_types = FALSE) %>%
  mutate(form_grade = as.character(form_grade))
out_dir <- file.path(work, "outputs/y3_ministry/01_item_quality")

label_character <- function(x) as.character(haven::as_factor(x))

prepare_form <- function(data, form_map) {
  item_vars <- intersect(unique(form_map$item_id), names(data))
  form <- data %>%
    filter(label_character(subject) == first(form_map$subject), label_character(grade) == first(form_map$form_grade)) %>%
    mutate(.source_row = row_number())
  answered <- rowSums(sapply(form[item_vars], function(x) {
    tag <- haven::na_tag(x)
    !is.na(x) | (!is.na(tag) & tag == "a")
  }))
  duration_value <- if ("duration" %in% names(form)) suppressWarnings(as.numeric(form$duration)) else 0
  id_key <- as.character(form$id_student_panel)
  id_key[is.na(id_key) | id_key == ""] <- paste0("__row_", form$.source_row[is.na(id_key) | id_key == ""])
  form %>%
    mutate(.id_key = id_key, .answered = answered, .duration_value = duration_value) %>%
    arrange(.id_key, desc(.answered), desc(.duration_value), .source_row) %>%
    distinct(.id_key, .keep_all = TRUE) %>%
    arrange(.source_row) %>%
    select(-.id_key, -.answered, -.duration_value)
}

alpha_matrix <- function(x) {
  x <- as.matrix(x); k <- ncol(x)
  if (k < 2 || nrow(x) < 3) return(NA_real_)
  total_var <- var(rowSums(x))
  if (!is.finite(total_var) || total_var <= 0) return(NA_real_)
  k / (k - 1) * (1 - sum(apply(x, 2, var)) / total_var)
}

cluster_mean_se <- function(y, cluster) {
  ok <- is.finite(y) & !is.na(cluster)
  y <- y[ok]; cluster <- as.character(cluster[ok])
  n <- length(y); g <- length(unique(cluster))
  if (n < 2 || g < 2) return(NA_real_)
  residual_sums <- tapply(y - mean(y), cluster, sum)
  sqrt((g / (g - 1)) * sum(residual_sums^2) / n^2)
}

item_rows <- list(); form_rows <- list()
for (wave in names(files)) {
  message(wave)
  data <- read_dta(files[[wave]]) %>% select(-any_of(c("treated", "treatment", "p_treated")))
  wave_map <- registry %>% filter(.data$wave == .env$wave)
  forms <- wave_map %>% distinct(subject, form_grade)
  for (f in seq_len(nrow(forms))) {
    subject_value <- forms$subject[f]; grade_value <- forms$form_grade[f]
    map <- wave_map %>% filter(subject == subject_value, form_grade == grade_value) %>% distinct(item_id, .keep_all = TRUE)
    form <- prepare_form(data, map)
    clusters <- as.character(form$school)
    item_ids <- intersect(map$item_id, names(form))
    binary <- set_names(map_lgl(item_ids, function(item) {
      values <- unique(as.numeric(form[[item]][!is.na(form[[item]])])); all(values %in% c(0, 1))
    }), item_ids)
    binary_items <- names(binary)[binary]
    matrix <- sapply(form[binary_items], function(x) as.numeric(!is.na(x) & as.numeric(x) == 1))
    if (length(binary_items) == 1) matrix <- matrix(matrix, ncol = 1, dimnames = list(NULL, binary_items))
    if (length(binary_items)) {
      for (item in binary_items) {
        y <- matrix[, item]
        se <- cluster_mean_se(y, clusters)
        p <- mean(y)
        item_rows[[paste(wave, subject_value, grade_value, item)]] <- tibble(
          wave = wave, subject = subject_value, grade = grade_value, item_id = item,
          estimate_type = "proportion correct", estimate = p, cluster_se = se,
          ci95_lower = max(0, p - 1.96 * se), ci95_upper = min(1, p + 1.96 * se),
          school_cluster_n = length(unique(clusters)), n = length(y)
        )
      }
      school_ids <- unique(clusters)
      boot_alpha <- replicate(200, {
        sampled <- sample(school_ids, length(school_ids), replace = TRUE)
        indices <- unlist(lapply(sampled, function(school) which(clusters == school)), use.names = FALSE)
        alpha_matrix(matrix[indices, , drop = FALSE])
      })
      raw_score <- rowSums(matrix)
      score_se <- cluster_mean_se(raw_score, clusters)
      form_rows[[paste(wave, subject_value, grade_value)]] <- tibble(
        wave = wave, subject = subject_value, grade = grade_value,
        n = nrow(matrix), item_n = ncol(matrix), school_cluster_n = length(school_ids),
        alpha = alpha_matrix(matrix),
        alpha_school_bootstrap_lower = as.numeric(quantile(boot_alpha, 0.025, na.rm = TRUE)),
        alpha_school_bootstrap_upper = as.numeric(quantile(boot_alpha, 0.975, na.rm = TRUE)),
        raw_score_mean = mean(raw_score), raw_score_cluster_se = score_se,
        raw_score_mean_ci95_lower = mean(raw_score) - 1.96 * score_se,
        raw_score_mean_ci95_upper = mean(raw_score) + 1.96 * score_se
      )
    }
    continuous_items <- names(binary)[!binary]
    for (item in continuous_items) {
      y <- as.numeric(form[[item]])
      se <- cluster_mean_se(y, clusters)
      estimate <- mean(y, na.rm = TRUE)
      item_rows[[paste(wave, subject_value, grade_value, item)]] <- tibble(
        wave = wave, subject = subject_value, grade = grade_value, item_id = item,
        estimate_type = "continuous/rubric mean", estimate = estimate, cluster_se = se,
        ci95_lower = estimate - 1.96 * se, ci95_upper = estimate + 1.96 * se,
        school_cluster_n = length(unique(clusters)), n = sum(!is.na(y))
      )
    }
  }
  rm(data); invisible(gc())
}

items <- bind_rows(item_rows); forms <- bind_rows(form_rows)
write_csv(items, file.path(out_dir, "y3_item_clustered_uncertainty.csv"), na = "")
write_csv(forms, file.path(out_dir, "y3_form_reliability_uncertainty.csv"), na = "")
summary <- list(
  treatment_fields_used = FALSE,
  item_form_rows = nrow(items), form_rows = nrow(forms), bootstrap_replicates = 200,
  uncertainty_method = "School-cluster sandwich SE for means/proportions; nonparametric school-cluster bootstrap percentile interval for alpha."
)
writeLines(jsonlite::toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "y3_uncertainty_summary.json"))
cat(jsonlite::toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
