#!/usr/bin/env Rscript

# Construct the non-IRT benchmark outcomes used in the measurement robustness
# exercise. This script deliberately performs no regression. Treatment status
# is used only to define the comparison-group mean and SD, then removed before
# student-level outcomes are written.

suppressPackageStartupMessages({
  library(digest)
  library(dplyr)
  library(haven)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(tidyr)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: build_plain_score_robustness.R config/paths.local.yml")
}

config_path <- normalizePath(args[[1]], mustWork = TRUE)
paths <- yaml::read_yaml(config_path)$dropbox
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)

is_within <- function(path, root) {
  candidate <- normalizePath(path, mustWork = FALSE)
  boundary <- normalizePath(root, mustWork = FALSE)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_source <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Input outside approved roots: ", candidate)
  candidate
}
assert_work_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) stop("Derived input outside work_root: ", candidate)
  candidate
}
assert_output <- function(path) {
  candidate <- normalizePath(path, mustWork = FALSE)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x) && !is_within(work_root, .x)))) stop("Output inside a source root")
  candidate
}
label_character <- function(x) as.character(haven::as_factor(x))
clean_integer <- function(x, field) {
  value <- suppressWarnings(as.integer(label_character(x)))
  if (any(is.na(value) & !is.na(x))) stop("Could not parse ", field)
  value
}
sha256_file <- function(path) digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)

wave_files <- c(
  baseline = assert_source(file.path(paths$y3_root, "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta")),
  endline = assert_source(file.path(paths$y3_root, "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta"))
)
registry_path <- assert_work_input(file.path(work_root, "outputs/y3_ministry/00_readiness/y3_source_registry.csv"))
manifest_path <- assert_work_input(file.path(work_root, "outputs/y1_y3_irt/01_link_design/y3_y1_anchor_manifest.csv"))
source_registry <- read_csv(registry_path, show_col_types = FALSE)

source_lineage <- imap_dfr(wave_files, function(path, wave_value) {
  relative_path <- substring(path, nchar(normalizePath(paths$y3_root)) + 2L)
  registered <- source_registry %>% filter(root_alias == "y3_root", .data$relative_path == .env$relative_path)
  if (nrow(registered) != 1L) stop("Source does not have one registry row: ", relative_path)
  observed_hash <- sha256_file(path)
  if (!identical(observed_hash, registered$sha256[[1]])) stop("Source hash mismatch: ", relative_path)
  tibble(
    year = 3L, wave = wave_value, root_alias = "y3_root", relative_path = relative_path,
    sha256 = observed_hash, canonicality_status = registered$canonicality_status[[1]]
  )
})

manifest <- read_csv(manifest_path, show_col_types = FALSE) %>%
  mutate(administered_grade = as.integer(administered_grade)) %>%
  filter(wave %in% names(wave_files), item_type == "binary") %>%
  distinct(wave, subject, administered_grade, item_id)
if (!nrow(manifest)) stop("Binary Year 3 item manifest is empty")
if (anyDuplicated(manifest)) stop("Duplicate keys in binary item manifest")

score_one_wave <- function(path, wave_value) {
  raw <- read_dta(path)
  required <- c("id_student_panel", "subject", "grade", "cohort", "treated")
  if (wave_value == "baseline") required <- c(required, "pair_id", "school_id", "out_list")
  missing_fields <- setdiff(required, names(raw))
  if (length(missing_fields)) stop("Missing fields in ", wave_value, ": ", paste(missing_fields, collapse = ", "))
  raw$.source_row <- seq_len(nrow(raw))
  subject_all <- label_character(raw$subject)
  grade_all <- clean_integer(raw$grade, "grade")
  forms <- manifest %>% filter(wave == wave_value) %>% distinct(subject, administered_grade)
  score_rows <- list(); audit_rows <- list()

  for (i in seq_len(nrow(forms))) {
    subject_value <- forms$subject[[i]]
    grade_value <- forms$administered_grade[[i]]
    candidate_items <- manifest %>%
      filter(wave == wave_value, subject == subject_value, administered_grade == grade_value) %>%
      pull(item_id) %>% unique()
    absent <- setdiff(candidate_items, names(raw))
    if (length(absent)) stop("Manifest fields absent in source for ", wave_value, " ", subject_value, " Grade ", grade_value)
    form <- raw[subject_all == subject_value & grade_all == grade_value, , drop = FALSE]

    binary_item <- map_lgl(candidate_items, function(item) {
      x <- form[[item]]
      values <- suppressWarnings(as.numeric(x[!is.na(x)]))
      all(values %in% c(0, 1))
    })
    included <- candidate_items[binary_item]
    if (!length(included)) stop("No binary items for ", wave_value, " ", subject_value, " Grade ", grade_value)

    answered <- rowSums(sapply(form[included], function(x) {
      tag <- haven::na_tag(x)
      !is.na(x) | (!is.na(tag) & tag == "a")
    }))
    duration <- if ("duration" %in% names(form)) suppressWarnings(as.numeric(form$duration)) else rep(0, nrow(form))
    duration[is.na(duration)] <- 0
    id_key <- as.character(form$id_student_panel)
    missing_id <- is.na(id_key) | id_key == ""
    id_key[missing_id] <- paste0("__missing_", form$.source_row[missing_id])
    before_n <- nrow(form)
    form <- form %>%
      mutate(.id_key = id_key, .answered = answered, .duration = duration) %>%
      arrange(.id_key, desc(.answered), desc(.duration), .source_row) %>%
      distinct(.id_key, .keep_all = TRUE) %>%
      arrange(.source_row)

    response <- sapply(form[included], function(x) {
      numeric_value <- suppressWarnings(as.numeric(x))
      scored <- rep(NA_real_, length(x))
      scored[!is.na(x)] <- as.numeric(numeric_value[!is.na(x)] == 1)
      tag <- haven::na_tag(x)
      scored[!is.na(tag) & tag == "a"] <- 0
      scored
    })
    if (length(included) == 1L) response <- matrix(response, ncol = 1L)
    observed_n <- rowSums(!is.na(response))
    raw_total <- rowSums(response, na.rm = TRUE)
    raw_total[observed_n == 0L] <- NA_real_

    scores <- tibble(
      source_id = as.character(form$id_student_panel), subject = subject_value,
      administered_grade = grade_value, wave = wave_value,
      cohort = clean_integer(form$cohort, "cohort"), treated = clean_integer(form$treated, "treated"),
      raw_total = raw_total, observed_item_n = as.integer(observed_n), binary_item_n = length(included)
    )
    if (wave_value == "baseline") {
      scores <- scores %>% mutate(
        pair_id = as.character(form$pair_id), school_id = as.character(form$school_id),
        out_list = str_detect(str_to_lower(label_character(form$out_list)), "^out")
      )
    }
    score_rows[[paste(subject_value, grade_value, sep = "|")]] <- scores
    audit_rows[[paste(subject_value, grade_value, sep = "|")]] <- tibble(
      wave = wave_value, subject = subject_value, administered_grade = grade_value,
      manifest_binary_item_n = length(candidate_items), included_binary_item_n = length(included),
      observed_nonbinary_item_n_excluded = sum(!binary_item), source_row_n = before_n,
      deduplicated_row_n = nrow(form), duplicate_row_n_removed = before_n - nrow(form),
      missing_id_row_n = sum(is.na(form$id_student_panel) | form$id_student_panel == "")
    )
  }
  list(scores = bind_rows(score_rows), audit = bind_rows(audit_rows))
}

wave_results <- imap(wave_files, score_one_wave)
baseline <- wave_results$baseline$scores %>%
  rename_with(~ paste0(.x, "_baseline"), c("cohort", "treated", "raw_total", "observed_item_n", "binary_item_n"))
endline <- wave_results$endline$scores %>%
  rename_with(~ paste0(.x, "_endline"), c("cohort", "treated", "raw_total", "observed_item_n", "binary_item_n"))

panel <- baseline %>%
  select(-wave) %>%
  inner_join(endline %>% select(-wave), by = c("source_id", "subject", "administered_grade")) %>%
  mutate(
    cohort = cohort_baseline, treated = treated_baseline,
    metadata_mismatch = cohort_baseline != cohort_endline | treated_baseline != treated_endline
  ) %>%
  filter(
    source_id != "", !is.na(source_id), !is.na(raw_total_baseline), !is.na(raw_total_endline),
    treated %in% c(0L, 1L), !is.na(cohort), pair_id != "", !is.na(pair_id),
    school_id != "", !is.na(school_id)
  )
if (anyDuplicated(panel[c("source_id", "subject", "administered_grade")])) stop("Duplicate panel keys")

sample_definitions <- c(
  listed_panel = "exclude baseline out_list flags",
  all_panel = "retain baseline out_list flags",
  listed_consistent_metadata = "exclude out_list flags and cross-wave cohort/treatment mismatches"
)
subset_panel <- function(data, variant) {
  if (variant == "all_panel") return(data)
  if (variant == "listed_panel") return(filter(data, !out_list))
  if (variant == "listed_consistent_metadata") return(filter(data, !out_list, !metadata_mismatch))
  stop("Unknown sample variant")
}

standardize_variant <- function(data, variant) {
  long <- bind_rows(
    data %>% transmute(source_id, subject, administered_grade, cohort, treated, wave = "baseline", raw_total = raw_total_baseline, observed_item_n = observed_item_n_baseline, binary_item_n = binary_item_n_baseline),
    data %>% transmute(source_id, subject, administered_grade, cohort, treated, wave = "endline", raw_total = raw_total_endline, observed_item_n = observed_item_n_endline, binary_item_n = binary_item_n_endline)
  )
  code_stats <- long %>% filter(treated == 0L) %>% group_by(cohort, wave, subject) %>%
    summarise(control_n = n(), mean = mean(raw_total), sd = sd(raw_total), .groups = "drop")
  grade_stats <- long %>% filter(treated == 0L) %>% group_by(cohort, wave, subject, administered_grade) %>%
    summarise(control_n = n(), mean = mean(raw_total), sd = sd(raw_total), .groups = "drop")
  if (any(!is.finite(code_stats$sd) | code_stats$sd <= 0) || any(!is.finite(grade_stats$sd) | grade_stats$sd <= 0)) {
    stop("Nonpositive comparison-group SD")
  }
  scored <- long %>%
    left_join(code_stats %>% rename(code_mean = mean, code_sd = sd, code_control_n = control_n), by = c("cohort", "wave", "subject")) %>%
    left_join(grade_stats %>% rename(grade_mean = mean, grade_sd = sd, grade_control_n = control_n), by = c("cohort", "wave", "subject", "administered_grade")) %>%
    mutate(plain_code = (raw_total - code_mean) / code_sd, plain_report_grade = (raw_total - grade_mean) / grade_sd)

  outcome <- scored %>%
    select(source_id, subject, administered_grade, cohort, wave, raw_total, observed_item_n, binary_item_n, plain_code, plain_report_grade) %>%
    pivot_longer(c(plain_code, plain_report_grade), names_to = "score_method_base", values_to = "score") %>%
    mutate(
      year = 3L, sample_variant = variant,
      method_id = paste(score_method_base, variant, sep = "__"), score_family = "standardized_binary_sum",
      scale_status = if_else(
        score_method_base == "plain_code",
        "comparison_z_within_subject_cohort_wave",
        "comparison_z_within_subject_grade_cohort_wave"
      ),
      final_outcome_approved = 0L
    ) %>%
    select(source_id, year, wave, cohort, subject, administered_grade, method_id, score_family,
           sample_variant, score, raw_total, observed_item_n, binary_item_n, scale_status,
           final_outcome_approved)

  checks <- bind_rows(
    scored %>% filter(treated == 0L) %>% group_by(cohort, wave, subject) %>%
      summarise(control_n = n(), achieved_mean = mean(plain_code), achieved_sd = sd(plain_code), .groups = "drop") %>%
      mutate(administered_grade = NA_integer_, score_method_base = "plain_code"),
    scored %>% filter(treated == 0L) %>% group_by(cohort, wave, subject, administered_grade) %>%
      summarise(control_n = n(), achieved_mean = mean(plain_report_grade), achieved_sd = sd(plain_report_grade), .groups = "drop") %>%
      mutate(score_method_base = "plain_report_grade")
  ) %>% mutate(sample_variant = variant, method_id = paste(score_method_base, variant, sep = "__"))
  stats <- bind_rows(
    code_stats %>% mutate(administered_grade = NA_integer_, score_method_base = "plain_code"),
    grade_stats %>% mutate(score_method_base = "plain_report_grade")
  ) %>% mutate(sample_variant = variant, method_id = paste(score_method_base, variant, sep = "__"))
  list(outcome = outcome, checks = checks, stats = stats)
}

variants <- imap(sample_definitions, ~ standardize_variant(subset_panel(panel, .y), .y))
outcomes <- bind_rows(map(variants, "outcome"))
checks <- bind_rows(map(variants, "checks"))
stats <- bind_rows(map(variants, "stats"))
item_audit <- bind_rows(map(wave_results, "audit"))

out_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/06_outcome_construction/plain_scores"))
derived_dir <- assert_output(file.path(work_root, "derived/y1_y3_irt"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(source_lineage, file.path(out_dir, "plain_score_source_lineage.csv"), na = "")
write_csv(item_audit, file.path(out_dir, "plain_score_item_and_duplicate_audit.csv"), na = "")
write_csv(stats, file.path(out_dir, "plain_score_standardization_constants.csv"), na = "")
write_csv(checks, file.path(out_dir, "plain_score_standardization_checks.csv"), na = "")
write_csv(outcomes, file.path(derived_dir, "y3_plain_standardized_scores_long.csv"), na = "")
write_dta(outcomes, file.path(derived_dir, "y3_plain_standardized_scores_long.dta"), version = 15)

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), outcome_row_n = nrow(outcomes),
  method_n = n_distinct(outcomes$method_id), student_n = n_distinct(outcomes$source_id),
  nonbinary_item_occurrence_n_excluded = sum(item_audit$observed_nonbinary_item_n_excluded),
  duplicate_row_n_removed = sum(item_audit$duplicate_row_n_removed),
  maximum_absolute_control_mean = max(abs(checks$achieved_mean)),
  maximum_absolute_control_sd_deviation = max(abs(checks$achieved_sd - 1)),
  treatment_fields_exported = 0L, regression_executed = 0L,
  status = "measurement_robustness_not_final_outcome"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "plain_score_run_summary.json"))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
