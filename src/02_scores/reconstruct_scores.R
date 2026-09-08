#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(haven)
  library(openxlsx)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: reconstruct_scores.R config/paths.local.yml")
paths <- yaml::read_yaml(args[[1]])$dropbox
y3 <- paths$y3_root
work <- paths$work_root

files <- c(
  baseline = file.path(y3, "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta"),
  pilot = file.path(y3, "4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta"),
  endline = file.path(y3, "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta")
)
registry_path <- file.path(work, "derived/y3_ministry/y3_item_version_registry.csv")
out_dir <- file.path(work, "outputs/y3_ministry/00_readiness")
derived_dir <- file.path(work, "derived/y3_ministry")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

registry <- read_csv(registry_path, show_col_types = FALSE) %>%
  mutate(
    form_grade = as.character(form_grade),
    grade_specific_scto_id = str_replace(
      scto_question_id, "_N[0-9]+_", paste0("_N", form_grade, "_")
    ),
    analytic_content_domain = case_when(
      wave == "endline" & !is.na(ministry_content_domain) & ministry_content_domain != "" ~ ministry_content_domain,
      TRUE ~ content_domain
    ),
    analytic_cognitive_domain = case_when(
      wave == "endline" & !is.na(ministry_cognitive_domain) & ministry_cognitive_domain != "" ~ ministry_cognitive_domain,
      TRUE ~ cognitive_domain
    )
  )

alpha_from_matrix <- function(x) {
  x <- as.matrix(x)
  k <- ncol(x)
  if (k < 2 || nrow(x) < 3) return(NA_real_)
  total <- rowSums(x)
  total_var <- var(total)
  item_vars <- apply(x, 2, var)
  if (!is.finite(total_var) || total_var <= 0) return(NA_real_)
  k / (k - 1) * (1 - sum(item_vars, na.rm = TRUE) / total_var)
}

safe_cor <- function(x, y) {
  if (length(x) < 3 || sd(x) == 0 || sd(y) == 0) return(NA_real_)
  suppressWarnings(cor(x, y))
}

label_character <- function(x) as.character(haven::as_factor(x))

prepare_form <- function(data, form_map, deduplicate = TRUE) {
  item_vars <- intersect(unique(form_map$item_id), names(data))
  form <- data %>%
    filter(
      label_character(subject) == first(form_map$subject),
      label_character(grade) == first(form_map$form_grade)
    ) %>%
    mutate(.source_row = row_number())
  if (!deduplicate || nrow(form) == 0) return(form)
  answered <- if (length(item_vars)) {
    rowSums(sapply(form[item_vars], function(x) {
      tag <- haven::na_tag(x)
      !is.na(x) | (!is.na(tag) & tag == "a")
    }))
  } else rep(0, nrow(form))
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

item_type <- function(x) {
  values <- sort(unique(as.numeric(x[!is.na(x)])))
  if (all(values %in% c(0, 1))) "binary" else "continuous_or_rubric"
}

item_rows <- list()
raw_item_rows <- list()
form_rows <- list()
duplicate_rows <- list()
map_audit_rows <- list()
off_form_rows <- list()

for (wave in names(files)) {
  message("Reading ", wave)
  data <- read_dta(files[[wave]])
  wave_map <- registry %>% filter(.data$wave == .env$wave)
  data_subject <- label_character(data$subject)
  data_grade <- label_character(data$grade)
  data_item_vars <- names(data)[str_detect(names(data), regex("^[amf][0-9]", ignore_case = TRUE))]
  mapped_item_vars <- unique(wave_map$item_id)
  map_audit_rows[[wave]] <- tibble(
    wave = wave,
    dataset_n = nrow(data),
    dataset_columns_n = ncol(data),
    dataset_item_like_n = length(data_item_vars),
    mapped_unique_item_n = length(mapped_item_vars),
    mapped_items_missing_from_data_n = sum(!mapped_item_vars %in% names(data)),
    data_item_like_missing_from_map_n = sum(!data_item_vars %in% mapped_item_vars),
    mapped_items_missing_from_data = paste(sort(setdiff(mapped_item_vars, names(data))), collapse = ";"),
    data_item_like_missing_from_map = paste(sort(setdiff(data_item_vars, mapped_item_vars)), collapse = ";")
  )

  for (item in intersect(mapped_item_vars, names(data))) {
    expected <- wave_map %>% filter(item_id == item) %>% transmute(subject, form_grade)
    on_form <- rep(FALSE, nrow(data))
    for (j in seq_len(nrow(expected))) {
      on_form <- on_form | (data_subject == expected$subject[j] & data_grade == expected$form_grade[j])
    }
    tag <- haven::na_tag(data[[item]])
    responded <- !is.na(data[[item]]) | (!is.na(tag) & tag == "a")
    off_form_rows[[paste(wave, item)]] <- tibble(
      wave = wave,
      item_id = item,
      expected_form_n = nrow(expected),
      on_form_response_n = sum(responded & on_form),
      off_form_response_n = sum(responded & !on_form)
    )
  }

  forms <- wave_map %>% distinct(subject, form_grade) %>% arrange(subject, as.numeric(form_grade))
  for (f in seq_len(nrow(forms))) {
    subj <- forms$subject[f]
    grd <- forms$form_grade[f]
    key <- paste(wave, subj, grd, sep = "|")
    form_map <- wave_map %>% filter(subject == subj, form_grade == grd) %>% distinct(item_id, .keep_all = TRUE)
    raw_form <- prepare_form(data, form_map, deduplicate = FALSE)
    form <- prepare_form(data, form_map, deduplicate = TRUE)
    item_vars <- intersect(form_map$item_id, names(data))
    types <- set_names(map_chr(item_vars, ~ item_type(data[[.x]])), item_vars)
    binary_items <- names(types)[types == "binary"]
    continuous_items <- names(types)[types != "binary"]
    duplicate_rows[[key]] <- tibble(
      wave = wave, subject = subj, grade = grd,
      raw_n = nrow(raw_form), deduplicated_n = nrow(form), duplicate_rows_removed = nrow(raw_form) - nrow(form)
    )

    score_matrix <- if (length(binary_items)) {
      sapply(form[binary_items], function(x) as.numeric(!is.na(x) & as.numeric(x) == 1))
    } else matrix(numeric(), nrow = nrow(form), ncol = 0)
    if (length(binary_items) == 1) score_matrix <- matrix(score_matrix, ncol = 1, dimnames = list(NULL, binary_items))
    raw_score <- if (ncol(score_matrix)) rowSums(score_matrix) else rep(NA_real_, nrow(form))
    alpha <- if (ncol(score_matrix) >= 2) alpha_from_matrix(score_matrix) else NA_real_
    score_sd <- sd(raw_score)
    form_rows[[key]] <- tibble(
      wave = wave, subject = subj, grade = grd,
      n_raw = nrow(raw_form), n_deduplicated = nrow(form),
      mapped_item_n = nrow(form_map), binary_item_n = length(binary_items),
      continuous_or_rubric_item_n = length(continuous_items),
      raw_score_mean = mean(raw_score), raw_score_sd = score_sd,
      proportion_score_mean = mean(raw_score / max(length(binary_items), 1)),
      floor_pct = mean(raw_score == 0) * 100,
      ceiling_pct = mean(raw_score == length(binary_items)) * 100,
      cronbach_alpha_primary_noncorr_zero = alpha,
      classical_sem = ifelse(is.finite(alpha) && alpha <= 1, score_sd * sqrt(max(0, 1 - alpha)), NA_real_)
    )

    for (sample_label in c("raw", "deduplicated")) {
      target <- if (sample_label == "raw") raw_form else form
      target_score_matrix <- if (length(binary_items)) {
        sapply(target[binary_items], function(x) as.numeric(!is.na(x) & as.numeric(x) == 1))
      } else matrix(numeric(), nrow = nrow(target), ncol = 0)
      if (length(binary_items) == 1) target_score_matrix <- matrix(target_score_matrix, ncol = 1, dimnames = list(NULL, binary_items))
      target_total <- if (ncol(target_score_matrix)) rowSums(target_score_matrix) else rep(NA_real_, nrow(target))
      for (item in item_vars) {
        x <- target[[item]]
        kind <- types[[item]]
        map_row <- form_map %>% filter(item_id == item) %>% slice(1)
        base <- tibble(
          wave = wave, subject = subj, grade = grd, sample = sample_label,
          item_id = item, scto_question_id = map_row$scto_question_id,
          grade_specific_scto_id = map_row$grade_specific_scto_id,
          item_type = kind, n_form = nrow(target),
          content_domain = map_row$analytic_content_domain,
          cognitive_domain = map_row$analytic_cognitive_domain,
          grade_origin = map_row$grade_origin,
          map_anchor_flag = map_row$map_anchor_flag,
          provisional_version_fingerprint = map_row$provisional_version_fingerprint
        )
        if (kind == "binary") {
          numeric_x <- as.numeric(x)
          correct <- !is.na(x) & numeric_x == 1
          incorrect <- !is.na(x) & numeric_x == 0
          tag <- haven::na_tag(x)
          dknow <- !is.na(tag) & tag == "a"
          missing <- is.na(x) & !dknow
          scored <- as.numeric(correct)
          rest <- target_total - scored
          other <- setdiff(binary_items, item)
          alpha_deleted <- if (length(other) >= 2) alpha_from_matrix(target_score_matrix[, other, drop = FALSE]) else NA_real_
          row <- bind_cols(base, tibble(
            n_correct = sum(correct), n_incorrect = sum(incorrect), n_dont_know = sum(dknow),
            n_missing = sum(missing), pct_correct = mean(correct) * 100,
            pct_incorrect = mean(incorrect) * 100, pct_dont_know = mean(dknow) * 100,
            pct_missing = mean(missing) * 100,
            point_biserial_rest = safe_cor(scored, rest),
            alpha_if_deleted = alpha_deleted,
            continuous_mean = NA_real_, continuous_sd = NA_real_, continuous_min = NA_real_, continuous_max = NA_real_
          ))
        } else {
          numeric_x <- as.numeric(x)
          row <- bind_cols(base, tibble(
            n_correct = NA_integer_, n_incorrect = NA_integer_, n_dont_know = sum(!is.na(haven::na_tag(x)) & haven::na_tag(x) == "a"),
            n_missing = sum(is.na(x) & (is.na(haven::na_tag(x)) | haven::na_tag(x) != "a")), pct_correct = NA_real_, pct_incorrect = NA_real_,
            pct_dont_know = mean(!is.na(haven::na_tag(x)) & haven::na_tag(x) == "a") * 100,
            pct_missing = mean(is.na(x) & (is.na(haven::na_tag(x)) | haven::na_tag(x) != "a")) * 100,
            point_biserial_rest = NA_real_, alpha_if_deleted = NA_real_,
            continuous_mean = mean(numeric_x, na.rm = TRUE), continuous_sd = sd(numeric_x, na.rm = TRUE),
            continuous_min = suppressWarnings(min(numeric_x, na.rm = TRUE)),
            continuous_max = suppressWarnings(max(numeric_x, na.rm = TRUE))
          ))
        }
        if (sample_label == "raw") raw_item_rows[[paste(key, item)]] <- row else item_rows[[paste(key, item)]] <- row
      }
    }
  }
  rm(data)
  invisible(gc())
}

item_stats <- bind_rows(item_rows)
raw_item_stats <- bind_rows(raw_item_rows)
form_summary <- bind_rows(form_rows)
duplicate_audit <- bind_rows(duplicate_rows)
map_audit <- bind_rows(map_audit_rows)
off_form_audit <- bind_rows(off_form_rows)

prior_path <- file.path(y3, "5 - Data analysis/03_Baseline/Analysis/Tables/baseline_items_toupdate_20260223_eo.xlsx")
prior_raw <- openxlsx::read.xlsx(
  prior_path, sheet = "By item", colNames = FALSE,
  skipEmptyRows = FALSE, skipEmptyCols = FALSE
)
prior <- prior_raw %>%
  transmute(
    grade_specific_scto_id = as.character(X1),
    prior_n = suppressWarnings(as.numeric(X3)),
    prior_pct_nonresponse = suppressWarnings(as.numeric(X4)),
    prior_pct_incorrect = suppressWarnings(as.numeric(X5)),
    prior_pct_correct = suppressWarnings(as.numeric(X6))
  ) %>%
  filter(str_detect(grade_specific_scto_id, "_ex[0-9]+$"), !is.na(prior_n)) %>%
  distinct(grade_specific_scto_id, .keep_all = TRUE)

tieout <- item_stats %>%
  filter(wave == "baseline", item_type == "binary") %>%
  mutate(reconstructed_pct_nonresponse = pct_dont_know + pct_missing) %>%
  left_join(prior, by = "grade_specific_scto_id") %>%
  mutate(
    n_difference = n_form - prior_n,
    pct_correct_difference = pct_correct - prior_pct_correct,
    pct_incorrect_difference = pct_incorrect - prior_pct_incorrect,
    pct_nonresponse_difference = reconstructed_pct_nonresponse - prior_pct_nonresponse,
    tieout_within_0_001pp = if_else(
      !is.na(prior_n) & n_difference == 0 &
        abs(pct_correct_difference) <= 0.001 & abs(pct_incorrect_difference) <= 0.001 &
        abs(pct_nonresponse_difference) <= 0.001,
      1L, 0L, missing = 0L
    )
  )

write_csv(item_stats, file.path(derived_dir, "y3_item_operational_stats.csv"), na = "")
write_csv(raw_item_stats, file.path(derived_dir, "y3_item_operational_stats_raw.csv"), na = "")
write_csv(form_summary, file.path(derived_dir, "y3_form_score_summary.csv"), na = "")
write_csv(duplicate_audit, file.path(out_dir, "y3_duplicate_audit.csv"), na = "")
write_csv(map_audit, file.path(out_dir, "y3_map_data_audit.csv"), na = "")
write_csv(off_form_audit, file.path(out_dir, "y3_off_form_response_audit.csv"), na = "")
write_csv(tieout, file.path(out_dir, "y3_baseline_item_tieout.csv"), na = "")

summary <- list(
  waves = names(files),
  form_count = nrow(form_summary),
  deduplicated_total = sum(form_summary$n_deduplicated),
  duplicate_rows_removed = sum(duplicate_audit$duplicate_rows_removed),
  operational_item_form_rows = nrow(item_stats),
  binary_item_form_rows = sum(item_stats$item_type == "binary"),
  continuous_or_rubric_item_form_rows = sum(item_stats$item_type != "binary"),
  off_form_response_total = sum(off_form_audit$off_form_response_n),
  baseline_tieout_rows = nrow(tieout),
  baseline_tieout_prior_matches = sum(!is.na(tieout$prior_n)),
  baseline_tieout_exact_rows = sum(tieout$tieout_within_0_001pp),
  score_rule = "Primary raw score is the count correct across mapped binary items; incorrect, tagged don't-know, and untagged nonresponse score zero. Nonbinary fluency/rubric fields are reported separately and excluded from alpha/IRT.",
  duplicate_rule = "Within wave x subject x administered grade x panel ID, retain the row with the most mapped responses, then longest duration, then earliest source row. Identifiers are never exported."
)
writeLines(jsonlite::toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "y3_score_reconstruction_summary.json"))
cat(jsonlite::toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
