#!/usr/bin/env Rscript

# Assemble the six Ministry matched-DiD design panels with fixed-Year-1-scale
# IRT outcomes. Legacy Dropbox files are read only. Student-level derived
# panels are written only below the configured work_root.

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
if (!length(args) %in% c(1L, 2L)) {
  stop("Usage: prepare_ministry_multiyear_irt_panels.R config/paths.local.yml [success_marker]")
}

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
  if (!any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Input outside approved roots: ", candidate)
  candidate
}
assert_work_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) stop("Derived input outside work_root: ", candidate)
  candidate
}
assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Output inside a legacy source root")
  candidate
}

label_character <- function(x) {
  if (inherits(x, "haven_labelled")) as.character(haven::as_factor(x)) else as.character(x)
}
subject_name <- function(x) {
  value <- label_character(x)
  case_when(
    value %in% c("1", "Arabic") ~ "Arabic",
    value %in% c("2", "French") ~ "French",
    value %in% c("3", "Math", "Maths") ~ "Maths",
    TRUE ~ NA_character_
  )
}
canonical_id <- function(id, year, wave) {
  value <- as.character(id)
  already_prefixed <- str_detect(value, "^Y[123]_")
  prefix <- case_when(
    year == 1L ~ "Y1_",
    year == 2L ~ "Y2_",
    year == 3L ~ "Y3_",
    TRUE ~ ""
  )
  # Later endline files already carry the original cohort prefix. Unprefixed
  # Year 2 records are Cohort 2; unprefixed Year 3 baseline records are Cohort 3.
  if_else(already_prefixed, value, paste0(prefix, value))
}
sha256_file <- function(path) digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)

analysis_specs <- tribble(
  ~panel_id, ~file_name, ~cohort, ~exposure, ~panel,
  "c1e1", "01_cohort_1_year_1.dta", 1L, 1L, "A",
  "c2e1", "04_cohort_2_year_2.dta", 2L, 1L, "A",
  "c3e1", "06_cohort_3_year_3.dta", 3L, 1L, "A",
  "c1e2", "02_cohort_1_year_2.dta", 1L, 2L, "B",
  "c2e2", "05_cohort_2_year_3.dta", 2L, 2L, "B",
  "c1e3", "03_cohort_1_year_3.dta", 1L, 3L, "C"
) %>%
  mutate(path = map_chr(file_name, ~ assert_source(file.path(
    paths$y3_root, "4 - Data processing/04_Endline/Clean", .x
  ))))

y1_specs <- tribble(
  ~subject, ~file_name, ~score_variable,
  "Arabic", "temp3.dta", "theta_arabic",
  "French", "temp4.dta", "theta_french",
  "Maths", "temp5.dta", "theta_math"
) %>%
  mutate(path = map_chr(file_name, ~ assert_source(file.path(
    paths$y1_root, "4 - Data processing/Endline/Temp", .x
  ))))

read_y1_score <- function(subject_value, path, score_variable) {
  raw <- read_dta(path, col_select = all_of(c(
    "student_id", "baseline", "subject", "grade", score_variable
  )))
  score <- as.numeric(raw[[score_variable]])
  tibble(
    student_id = canonical_id(raw$student_id, 1L, if_else(raw$baseline == 1, "baseline", "endline")),
    year = 1L,
    wave_short = if_else(raw$baseline == 1, "baseline", "endline"),
    subject_name = subject_value,
    administered_grade = suppressWarnings(as.integer(label_character(raw$grade))),
    irt_score = score
  ) %>%
    filter(!is.na(irt_score))
}

y1_scores <- pmap_dfr(
  y1_specs %>% select(subject, path, score_variable),
  ~ read_y1_score(..1, ..2, ..3)
) %>%
  mutate(
    score_method = "fixed_y1_reference",
    score_origin = "delivered_year1_score_unchanged"
  )
if (anyDuplicated(y1_scores[c("student_id", "year", "wave_short", "subject_name")])) {
  stop("Duplicate key in delivered Year 1 score bank")
}

derived_dir <- file.path(work_root, "derived/y1_y3_irt")
method_specs <- tribble(
  ~score_method, ~file_name, ~score_origin, ~year_override,
  "primary", "multiyear_irt_outcomes_primary.dta", "concurrent_subject_all_final_fixed_y1", NA_integer_,
  "primary_wle", "multiyear_irt_outcomes_primary_wle.dta", "primary_item_bank_wle_person_scores", NA_integer_,
  "subject_final_control", "multiyear_irt_outcomes_joint_subject_pooled_mixture_comparison_only_purified_andy_core_math_bridge5.dta", "final_subject_pool_control_calibration", NA_integer_,
  "grade_final_all", "multiyear_irt_outcomes_joint_grade_specific_mixture_all_purified_andy_core_math_bridge5.dta", "final_grade_specific_all_calibration", NA_integer_,
  "grade_final_control", "multiyear_irt_outcomes_joint_grade_specific_mixture_comparison_only_purified_andy_core_math_bridge5.dta", "final_grade_specific_control_calibration", NA_integer_,
  "pooled_strict_all", "multiyear_irt_outcomes_joint_subject_pooled_mixture_all_strict_summary.dta", "strict_subject_pool_all_calibration", NA_integer_,
  "pooled_strict_control", "multiyear_irt_outcomes_joint_subject_pooled_mixture_comparison_only_strict_summary.dta", "strict_subject_pool_control_calibration", NA_integer_,
  "grade_specific_strict", "multiyear_irt_outcomes_joint_grade_specific_mixture_all_strict_summary.dta", "strict_grade_specific_all_calibration", NA_integer_,
  "grade_strict_control", "multiyear_irt_outcomes_joint_grade_specific_mixture_comparison_only_strict_summary.dta", "strict_grade_specific_control_calibration", NA_integer_,
  "chained_strict", "multiyear_irt_outcomes_chained_strict_summary.dta", "strict_selected_path_fixed_y1", NA_integer_,
  "direct_strict", "y3_irt_outcomes_strict_summary.dta", "strict_direct_fixed_y1", 3L,
  "pooled_andy_core", "multiyear_irt_outcomes_joint_subject_pooled_mixture_all_purified_andy_core.dta", "andy_core_before_math_bridge", NA_integer_,
  "pooled_broad", "multiyear_irt_outcomes_joint_subject_pooled_mixture_all_purified_strict.dta", "broad_purification_all_calibration", NA_integer_,
  "dev_schools_final", "multiyear_irt_outcomes_joint_subject_pooled_mixture_development_schools_purified_andy_core_math_bridge5.dta", "school_development_calibration", NA_integer_,
  "chained_provisional", "multiyear_irt_outcomes_chained_provisional_id.dta", "provisional_id_selected_path_fixed_y1", NA_integer_,
  "direct_provisional", "y3_irt_outcomes_provisional_id.dta", "provisional_id_direct_fixed_y1", 3L
) %>%
  mutate(path = map_chr(file_name, ~ assert_work_input(file.path(derived_dir, .x))))

read_later_score <- function(score_method, path, score_origin, year_override) {
  raw <- read_dta(path)
  required <- c("id_student_panel", "wave", "subject", "administered_grade", "theta_y1_published_z")
  if (is.na(year_override)) required <- c(required, "year")
  missing <- setdiff(required, names(raw))
  if (length(missing)) stop("Missing multiyear outcome fields: ", paste(missing, collapse = ", "))
  year_value <- if (is.na(year_override)) as.integer(raw$year) else rep(as.integer(year_override), nrow(raw))
  wave_value <- as.character(raw$wave)
  result <- tibble(
    student_id = canonical_id(raw$id_student_panel, year_value, wave_value),
    year = year_value,
    wave_short = wave_value,
    subject_name = subject_name(raw$subject),
    administered_grade = suppressWarnings(as.integer(raw$administered_grade)),
    irt_score = as.numeric(raw$theta_y1_published_z),
    score_method = score_method,
    score_origin = score_origin
  ) %>%
    filter(year %in% c(2L, 3L), wave_short %in% c("baseline", "endline"))
  if (any(!is.finite(result$irt_score))) stop("Missing/non-finite later-year IRT score")
  if (anyDuplicated(result[c("student_id", "year", "wave_short", "subject_name")])) {
    stop("Duplicate key in later-year score bank: ", score_method)
  }
  result
}

later_scores <- pmap_dfr(
  method_specs %>% select(score_method, path, score_origin, year_override),
  ~ read_later_score(..1, ..2, ..3, ..4)
)

# Replicate the exact delivered Year 1 score for every later-year IRT method.
score_bank <- bind_rows(
  later_scores,
  crossing(
    y1_scores %>% select(-score_method, -score_origin),
    method_specs %>% select(score_method, score_origin)
  )
) %>%
  select(student_id, year, wave_short, subject_name, administered_grade,
         score_method, irt_score, score_origin)

if (anyDuplicated(score_bank[c("student_id", "year", "wave_short", "subject_name", "score_method")])) {
  stop("Duplicate composite key in assembled score bank")
}

out_root <- assert_output(file.path(work_root, "outputs/y1_y3_irt/07_ministry_multiyear_results"))
panel_dir <- assert_output(file.path(out_root, "analysis_inputs"))
dir.create(panel_dir, recursive = TRUE, showWarnings = FALSE)

wide_bank <- score_bank %>%
  select(student_id, year, wave_short, subject_name, score_method, irt_score) %>%
  pivot_wider(names_from = score_method, values_from = irt_score, names_prefix = "irt_")

# The Ministry stable-sample table follows students observed in the final
# cohort-specific panel and retains matched pairs with both school arms. For
# the final exposure panel, the inherited code additionally removes students
# with a Year 3 replacement-baseline record. The combined legacy file is used
# only to recover that sample-membership flag; it is never used as an item or
# score source.
stable_membership_source <- assert_source(file.path(
  paths$y3_root, "4 - Data processing/04_Endline/Clean/y1y2y3_tested_data.dta"
))

# The delivered stable-sample table used the sum score standardized in the
# full combined testing file before the stable subsample was selected. The six
# clean panel files standardize their own panel-specific sum scores, which is
# correct for the headline table but cannot reproduce that stable table. Build
# the legacy stable-score benchmark independently and keep it in the derived
# Dropbox panels as a dedicated field.
legacy_combined <- read_dta(stable_membership_source) %>%
  filter(!(
    coalesce(as.numeric(dup_base_y3) == 1, FALSE) |
      coalesce(as.numeric(dup_end_y3) == 1, FALSE)
  ))

legacy_binary_items <- function(data, prefix) {
  candidates <- names(data)[startsWith(names(data), prefix)]
  candidates <- candidates[map_lgl(data[candidates], is.numeric)]
  included <- candidates[map_lgl(candidates, function(item) {
    values <- suppressWarnings(as.numeric(data[[item]]))
    observed <- values[!is.na(values)]
    length(observed) > 0L && all(observed %in% c(0, 1))
  })]
  if (prefix == "a") included <- setdiff(included, "answered")
  included
}

legacy_row_total <- function(data, items) {
  response <- sapply(data[items], function(x) {
    value <- suppressWarnings(as.numeric(x))
    tag <- haven::na_tag(x)
    value[!is.na(tag) & tag == "a"] <- 0
    value
  })
  if (length(items) == 1L) response <- matrix(response, ncol = 1L)
  observed <- rowSums(!is.na(response))
  total <- rowSums(response, na.rm = TRUE)
  total[observed == 0L] <- NA_real_
  total
}

legacy_item_sets <- list(
  Arabic = legacy_binary_items(legacy_combined, "a"),
  French = legacy_binary_items(legacy_combined, "f"),
  Maths = legacy_binary_items(legacy_combined, "m")
)
legacy_combined <- legacy_combined %>%
  mutate(
    cohort_number = case_when(
      as.numeric(cohort1) == 1 ~ 1L,
      as.numeric(cohort2) == 1 ~ 2L,
      as.numeric(cohort3) == 1 ~ 3L,
      TRUE ~ NA_integer_
    ),
    treated_for_cohort = case_when(
      cohort_number == 1L ~ as.numeric(treated_y1),
      cohort_number == 2L ~ as.numeric(treated_y2),
      cohort_number == 3L ~ as.numeric(treated_y3),
      TRUE ~ NA_real_
    ),
    subject_name = subject_name(subject),
    raw_legacy_arabic = legacy_row_total(., legacy_item_sets$Arabic),
    raw_legacy_french = legacy_row_total(., legacy_item_sets$French),
    raw_legacy_maths = legacy_row_total(., legacy_item_sets$Maths)
  )

standardize_legacy_subject <- function(data, raw_name, target_subject) {
  data %>%
    filter(subject_name == target_subject) %>%
    group_by(cohort_number, wave) %>%
    mutate(
      control_mean = mean(.data[[raw_name]][treated_for_cohort == 0], na.rm = TRUE),
      control_sd = sd(.data[[raw_name]][treated_for_cohort == 0], na.rm = TRUE),
      score_ministry_stable = (.data[[raw_name]] - control_mean) / control_sd
    ) %>%
    ungroup() %>%
    transmute(
      student_id = as.character(id_student_panel), wave = as.character(wave),
      subject_name, score_ministry_stable
    )
}

legacy_sum_bank <- bind_rows(
  standardize_legacy_subject(legacy_combined, "raw_legacy_arabic", "Arabic"),
  standardize_legacy_subject(legacy_combined, "raw_legacy_french", "French"),
  standardize_legacy_subject(legacy_combined, "raw_legacy_maths", "Maths")
)
if (anyDuplicated(legacy_sum_bank[c("student_id", "wave", "subject_name")])) {
  stop("Duplicate key in independently reconstructed legacy stable sum scores")
}

legacy_y3_baseline_ids <- legacy_combined %>%
  filter(wave == "baseline_Y3") %>%
  distinct(student_id = as.character(id_student_panel)) %>%
  pull(student_id)
stable_final_panels <- list(`1` = "c1e3", `2` = "c2e2")
stable_definitions <- imap(stable_final_panels, function(panel_id, cohort_value) {
  path <- analysis_specs$path[match(panel_id, analysis_specs$panel_id)]
  final <- read_dta(path, col_select = all_of(c("student_id", "pair_id", "cd_etab"))) %>%
    transmute(
      student_id = as.character(student_id),
      pair_id = as.character(pair_id),
      school_id = as.character(cd_etab)
    )
  complete_pairs <- final %>%
    distinct(pair_id, school_id) %>%
    count(pair_id, name = "school_n") %>%
    filter(school_n == 2L) %>%
    pull(pair_id)
  balanced_final_students <- final %>%
    filter(pair_id %in% complete_pairs) %>%
    count(student_id, name = "panel_row_n") %>%
    filter(panel_row_n == 2L) %>%
    pull(student_id)
  list(
    cohort = as.integer(cohort_value),
    final_panel_id = panel_id,
    pair_ids = complete_pairs,
    student_ids = final %>% filter(pair_id %in% complete_pairs) %>% distinct(student_id) %>% pull(student_id),
    final_panel_student_ids = final %>%
      filter(
        pair_id %in% complete_pairs,
        student_id %in% balanced_final_students,
        !student_id %in% legacy_y3_baseline_ids
      ) %>%
      distinct(student_id) %>%
      pull(student_id)
  )
})

coverage_rows <- list()
panel_rows <- list()
stable_audit_rows <- list()
for (index in seq_len(nrow(analysis_specs))) {
  spec <- analysis_specs[index, ]
  raw <- read_dta(spec$path[[1]])
  required <- c("student_id", "wave", "baseline", "post", "subject", "grade", "treated", "pair_id", "cd_etab")
  missing <- setdiff(required, names(raw))
  if (length(missing)) stop("Missing analysis-design fields in ", spec$file_name[[1]], ": ", paste(missing, collapse = ", "))
  panel <- raw %>%
    mutate(
      student_id = as.character(student_id),
      year = suppressWarnings(as.integer(str_extract(as.character(wave), "[123]$"))),
      wave_short = if_else(baseline == 1, "baseline", "endline"),
      subject_name = subject_name(subject)
    ) %>%
    left_join(wide_bank, by = c("student_id", "year", "wave_short", "subject_name")) %>%
    left_join(legacy_sum_bank, by = c("student_id", "wave", "subject_name"))

  stable_definition <- stable_definitions[[as.character(spec$cohort[[1]])]]
  panel$stable_sample <- if (is.null(stable_definition)) {
    0L
  } else {
    stable_student_ids <- if (spec$panel_id[[1]] == stable_definition$final_panel_id) {
      stable_definition$final_panel_student_ids
    } else {
      stable_definition$student_ids
    }
    as.integer(
      panel$student_id %in% stable_student_ids &
        as.character(panel$pair_id) %in% stable_definition$pair_ids
    )
  }

  if (nrow(panel) != nrow(raw)) stop("Analysis-panel join changed row count")
  irt_fields <- paste0("irt_", method_specs$score_method)
  for (field in irt_fields) {
    by_wave <- panel %>%
      group_by(wave = as.character(wave)) %>%
      summarise(
        panel_row_n = n(),
        score_nonmissing_n = sum(!is.na(.data[[field]])),
        score_coverage = mean(!is.na(.data[[field]])),
        .groups = "drop"
      ) %>%
      mutate(panel_id = spec$panel_id[[1]], score_method = str_remove(field, "^irt_"))
    balanced <- panel %>%
      group_by(student_id) %>%
      summarise(balanced = sum(!is.na(.data[[field]])) == 2L, .groups = "drop")
    by_wave$balanced_student_n <- sum(balanced$balanced)
    coverage_rows[[paste(spec$panel_id[[1]], field, sep = "|")]] <- by_wave
  }

  output_path <- assert_output(file.path(panel_dir, paste0(spec$panel_id[[1]], "_irt_panel.dta")))
  write_dta(panel, output_path, version = 15)
  stable_audit_rows[[spec$panel_id[[1]]]] <- panel %>%
    filter(stable_sample == 1L) %>%
    summarise(
      stable_student_n = n_distinct(student_id),
      stable_school_n = n_distinct(as.character(cd_etab)),
      stable_pair_n = n_distinct(as.character(pair_id))
    ) %>%
    mutate(panel_id = spec$panel_id[[1]], cohort = spec$cohort[[1]], exposure = spec$exposure[[1]])
  panel_rows[[spec$panel_id[[1]]]] <- tibble(
    panel_id = spec$panel_id[[1]], cohort = spec$cohort[[1]], exposure = spec$exposure[[1]],
    panel = spec$panel[[1]], source_file = spec$file_name[[1]], source_sha256 = sha256_file(spec$path[[1]]),
    source_row_n = nrow(raw), source_student_n = n_distinct(raw$student_id),
    derived_file = basename(output_path),
    source_role = "read_only_legacy_derived_design_reference",
    canonicality_status = "requires_collaborator_confirmation"
  )
}

coverage <- bind_rows(coverage_rows) %>%
  select(panel_id, score_method, wave, panel_row_n, score_nonmissing_n,
         score_coverage, balanced_student_n)
panel_registry <- bind_rows(panel_rows)
stable_audit <- bind_rows(stable_audit_rows) %>%
  select(panel_id, cohort, exposure, stable_student_n, stable_school_n, stable_pair_n)

write_csv(coverage, assert_output(file.path(out_root, "irt_panel_score_coverage.csv")), na = "")
write_csv(panel_registry, assert_output(file.path(out_root, "ministry_analysis_panel_registry.csv")), na = "")
write_csv(stable_audit, assert_output(file.path(out_root, "stable_sample_reconstruction_audit.csv")), na = "")
write_csv(
  tibble(
    source_file = basename(stable_membership_source),
    source_sha256 = sha256_file(stable_membership_source),
    use = "stable_sample_membership_only",
    item_or_score_source = 0L,
    status = "read_only_legacy_lineage_reconciliation"
  ),
  assert_output(file.path(out_root, "stable_sample_lineage_registry.csv")), na = ""
)
write_csv(
  tibble(
    subject = names(legacy_item_sets),
    included_binary_item_n = map_int(legacy_item_sets, length),
    nonbinary_rule = "numeric variables with observed values contained in {0,1}; tagged .a is incorrect; other missing values remain missing",
    output_role = "independent benchmark for the delivered stable-sample sum-score table"
  ),
  assert_output(file.path(out_root, "legacy_stable_sum_score_reconstruction_audit.csv")),
  na = ""
)
write_csv(
  method_specs %>% transmute(score_method, score_origin, source_file = file_name, source_sha256 = map_chr(path, sha256_file)),
  assert_output(file.path(out_root, "irt_score_method_registry.csv")), na = ""
)

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  ministry_design_panel_n = nrow(analysis_specs),
  score_method_n = nrow(method_specs),
  delivered_y1_score_row_n = nrow(y1_scores),
  later_year_score_row_n = nrow(later_scores),
  minimum_wave_score_coverage = min(coverage$score_coverage),
  all_y1_method_scores_are_delivered_unchanged = TRUE,
  outcome_scale = "fixed Year 1 endline-comparison mean and SD",
  status = "development_only_not_approved"
)
writeLines(
  toJSON(summary, pretty = TRUE, auto_unbox = TRUE),
  assert_output(file.path(out_root, "panel_preparation_summary.json"))
)
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
if (length(args) == 2L) writeLines("panel_preparation_complete", args[[2]])
