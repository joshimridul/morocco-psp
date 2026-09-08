#!/usr/bin/env Rscript

# Development-only Year 3 within-year matched-DiD comparison across IRT
# outcomes and verified binary-item raw scores. Source Dropbox roots are read
# only. Every generated, data-bearing artifact is aggregate and is written
# below the dedicated work_root.

suppressPackageStartupMessages({
  library(digest)
  library(dplyr)
  library(fixest)
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
if (length(args) != 1) {
  stop("Usage: run_y3_irt_treatment_sensitivity.R config/paths.local.yml")
}

config_path <- normalizePath(args[[1]], mustWork = TRUE)
paths <- yaml::read_yaml(config_path)$dropbox
source_roots <- normalizePath(
  c(paths$y1_root, paths$y2_root, paths$y3_root),
  mustWork = TRUE
)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)

normalize_for_guard <- function(path) normalizePath(path, mustWork = FALSE)

is_within <- function(path, root) {
  candidate <- normalize_for_guard(path)
  boundary <- normalize_for_guard(root)
  identical(candidate, boundary) ||
    startsWith(candidate, paste0(boundary, .Platform$file.sep))
}

assert_source <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!any(map_lgl(source_roots, ~ is_within(candidate, .x)))) {
    stop("Input is outside approved read-only source roots: ", candidate)
  }
  candidate
}

assert_work_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) {
    stop("Derived input is outside work_root: ", candidate)
  }
  candidate
}

assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) {
    stop("Output must be below work_root: ", candidate)
  }
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) {
    stop("Output resolves inside a read-only source root: ", candidate)
  }
  candidate
}

wave_files <- c(
  baseline = file.path(
    paths$y3_root,
    "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta"
  ),
  endline = file.path(
    paths$y3_root,
    "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta"
  )
)
walk(wave_files, assert_source)

source_registry_path <- assert_work_input(file.path(
  work_root,
  "outputs/y3_ministry/00_readiness/y3_source_registry.csv"
))
anchor_manifest_path <- assert_work_input(file.path(
  work_root,
  "outputs/y1_y3_irt/01_link_design/y3_y1_anchor_manifest.csv"
))
derived_dir <- assert_work_input(file.path(work_root, "derived/y1_y3_irt"))

out_dir <- assert_output(file.path(
  work_root,
  "outputs/y1_y3_irt/06_treatment_effect_sensitivity"
))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

label_character <- function(x) {
  if (inherits(x, "haven_labelled")) {
    as.character(haven::as_factor(x))
  } else {
    as.character(x)
  }
}

clean_integer <- function(x, field) {
  value <- suppressWarnings(as.integer(label_character(x)))
  if (any(is.na(value) & !is.na(x))) {
    stop("Could not parse integer field: ", field)
  }
  value
}

sha256_file <- function(path) {
  digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)
}

verify_registered_sources <- function(files, registry_path) {
  registry <- read_csv(registry_path, show_col_types = FALSE)
  rows <- map_dfr(names(files), function(wave_value) {
    path <- normalizePath(files[[wave_value]], mustWork = TRUE)
    relative_path <- substring(
      path,
      nchar(normalizePath(paths$y3_root, mustWork = TRUE)) + 2L
    )
    match <- registry %>%
      filter(
        root_alias == "y3_root",
        .data$relative_path == .env$relative_path
      )
    if (nrow(match) != 1) {
      stop("Expected exactly one source-registry row for ", relative_path)
    }
    observed_hash <- sha256_file(path)
    if (!identical(observed_hash, match$sha256[[1]])) {
      stop("Source hash differs from registry for ", relative_path)
    }
    tibble(
      wave = wave_value,
      relative_path = relative_path,
      sha256 = observed_hash,
      candidate_status = match$candidate_status[[1]],
      canonicality_status = match$canonicality_status[[1]]
    )
  })
  rows
}

registered_sources <- verify_registered_sources(wave_files, source_registry_path)

manifest <- read_csv(anchor_manifest_path, show_col_types = FALSE) %>%
  mutate(administered_grade = as.integer(administered_grade)) %>%
  filter(wave %in% c("baseline", "endline"))

if (nrow(manifest) == 0) stop("Binary item manifest is empty")
if (any(is.na(manifest$item_type)) || any(manifest$item_type != "binary")) {
  stop("Non-binary item rows are present in the scoring manifest")
}
if (anyDuplicated(manifest[c("wave", "subject", "administered_grade", "item_id")])) {
  stop("Duplicate wave-subject-grade-item keys in binary item manifest")
}

required_raw_fields <- c(
  "id_student_panel", "subject", "grade", "cohort", "treated"
)

score_wave <- function(path, wave_value, node_manifest) {
  message("Reading registered Year 3 ", wave_value, " source")
  raw <- read_dta(path)
  missing_fields <- setdiff(required_raw_fields, names(raw))
  if (length(missing_fields)) {
    stop(
      "Missing required ", wave_value, " fields: ",
      paste(missing_fields, collapse = ", ")
    )
  }
  if (wave_value == "baseline") {
    baseline_fields <- c("pair_id", "school_id", "out_list")
    missing_baseline_fields <- setdiff(baseline_fields, names(raw))
    if (length(missing_baseline_fields)) {
      stop(
        "Missing baseline design fields: ",
        paste(missing_baseline_fields, collapse = ", ")
      )
    }
  }

  subject_value <- label_character(raw$subject)
  grade_value <- clean_integer(raw$grade, "grade")
  raw$.source_row <- seq_len(nrow(raw))
  scored_forms <- list()
  item_audit <- list()

  forms <- node_manifest %>%
    distinct(subject, administered_grade) %>%
    arrange(subject, administered_grade)

  for (form_index in seq_len(nrow(forms))) {
    this_subject <- forms$subject[[form_index]]
    this_grade <- forms$administered_grade[[form_index]]
    form_map <- node_manifest %>%
      filter(
        subject == this_subject,
        administered_grade == this_grade
      ) %>%
      distinct(item_id)
    missing_item_fields <- setdiff(form_map$item_id, names(raw))
    if (length(missing_item_fields)) {
      stop(
        "Manifest item fields are absent for ", wave_value, " ",
        this_subject, " Grade ", this_grade, ": ",
        paste(missing_item_fields, collapse = ", ")
      )
    }

    form <- raw[subject_value == this_subject & grade_value == this_grade, , drop = FALSE]
    candidate_items <- form_map$item_id
    observed_binary <- map_lgl(candidate_items, function(item) {
      response <- form[[item]]
      value <- suppressWarnings(as.numeric(response))
      ordinary_observed <- !is.na(response)
      all(value[ordinary_observed] %in% c(0, 1))
    })
    included_items <- candidate_items[observed_binary]
    if (!length(included_items)) {
      stop("No observed-binary items remain for a registered form")
    }

    answered_matrix <- sapply(form[included_items], function(x) {
      tag <- haven::na_tag(x)
      !is.na(x) | (!is.na(tag) & tag == "a")
    })
    if (length(included_items) == 1) {
      answered_matrix <- matrix(answered_matrix, ncol = 1)
    }
    answered <- rowSums(answered_matrix)
    duration_value <- if ("duration" %in% names(form)) {
      suppressWarnings(as.numeric(form$duration))
    } else {
      rep(0, nrow(form))
    }
    duration_value[is.na(duration_value)] <- 0
    id_key <- as.character(form$id_student_panel)
    missing_id <- is.na(id_key) | id_key == ""
    id_key[missing_id] <- paste0("__row_", form$.source_row[missing_id])

    keep_index <- tibble(
      .row = seq_len(nrow(form)),
      .id_key = id_key,
      .answered = answered,
      .duration = duration_value,
      .source_row = form$.source_row
    ) %>%
      arrange(.id_key, desc(.answered), desc(.duration), .source_row) %>%
      distinct(.id_key, .keep_all = TRUE) %>%
      arrange(.source_row) %>%
      pull(.row)
    form <- form[keep_index, , drop = FALSE]

    response_matrix <- sapply(form[included_items], function(x) {
      value <- suppressWarnings(as.numeric(x))
      scored <- rep(NA_real_, length(x))
      ordinary_observed <- !is.na(x)
      scored[ordinary_observed] <- as.numeric(value[ordinary_observed] == 1)
      tag <- haven::na_tag(x)
      scored[!is.na(tag) & tag == "a"] <- 0
      scored
    })
    if (length(included_items) == 1) {
      response_matrix <- matrix(response_matrix, ncol = 1)
    }
    observed_n <- rowSums(!is.na(response_matrix))
    raw_total <- rowSums(response_matrix, na.rm = TRUE)
    raw_total[observed_n == 0] <- NA_real_

    result <- tibble(
      id_student_panel = as.character(form$id_student_panel),
      subject = this_subject,
      grade = this_grade,
      wave = wave_value,
      cohort_wave = clean_integer(form$cohort, "cohort"),
      treated_wave = clean_integer(form$treated, "treated"),
      plain_raw_total = raw_total,
      plain_observed_item_n = as.integer(observed_n),
      plain_binary_item_n = length(included_items)
    )
    if (wave_value == "baseline") {
      result <- result %>%
        mutate(
          pair_id = as.character(form$pair_id),
          school_id = as.character(form$school_id),
          out_list = str_detect(
            str_to_lower(label_character(form$out_list)),
            "^out"
          )
        )
    }
    scored_forms[[paste(this_subject, this_grade, sep = "|")]] <- result
    item_audit[[paste(this_subject, this_grade, sep = "|")]] <- tibble(
      wave = wave_value,
      subject = this_subject,
      grade = this_grade,
      manifest_item_n = length(candidate_items),
      included_binary_item_n = length(included_items),
      excluded_observed_nonbinary_item_n = sum(!observed_binary),
      student_row_n_before_deduplication = nrow(form) +
        sum(duplicated(id_key)),
      student_row_n_after_deduplication = nrow(form)
    )
  }

  list(
    scores = bind_rows(scored_forms),
    item_audit = bind_rows(item_audit)
  )
}

wave_results <- imap(wave_files, function(path, wave_value) {
  score_wave(
    path,
    wave_value,
    manifest %>% filter(wave == wave_value)
  )
})
item_audit <- bind_rows(map(wave_results, "item_audit"))

if (sum(item_audit$excluded_observed_nonbinary_item_n) > 0) {
  message(
    "Excluded ", sum(item_audit$excluded_observed_nonbinary_item_n),
    " manifest-listed items with observed values outside {0,1}."
  )
}

baseline_scores <- wave_results$baseline$scores %>%
  rename_with(~ paste0(.x, "_baseline"), c(
    "cohort_wave", "treated_wave", "plain_raw_total",
    "plain_observed_item_n", "plain_binary_item_n"
  ))
endline_scores <- wave_results$endline$scores %>%
  select(-wave) %>%
  rename_with(~ paste0(.x, "_endline"), c(
    "cohort_wave", "treated_wave", "plain_raw_total",
    "plain_observed_item_n", "plain_binary_item_n"
  ))

plain_panel_all <- baseline_scores %>%
  select(-wave) %>%
  inner_join(
    endline_scores,
    by = c("id_student_panel", "subject", "grade")
  ) %>%
  mutate(
    cohort = cohort_wave_baseline,
    treated = treated_wave_baseline,
    treatment_metadata_mismatch =
      treated_wave_baseline != treated_wave_endline,
    cohort_metadata_mismatch =
      cohort_wave_baseline != cohort_wave_endline,
    any_metadata_mismatch =
      treatment_metadata_mismatch | cohort_metadata_mismatch,
    key = paste(id_student_panel, subject, grade, sep = "|")
  ) %>%
  filter(
    !is.na(plain_raw_total_baseline),
    !is.na(plain_raw_total_endline),
    !is.na(treated),
    treated %in% c(0L, 1L),
    !is.na(cohort),
    !is.na(pair_id), pair_id != "",
    !is.na(school_id), school_id != ""
  )

if (anyDuplicated(plain_panel_all$key)) {
  stop("Plain-score panel contains duplicate student-subject-grade keys")
}

sample_variants <- c(
  listed_panel = "exclude baseline out_list flags",
  all_panel = "retain baseline out_list flags",
  listed_consistent_metadata = paste(
    "exclude baseline out_list flags and the records with treatment or cohort",
    "metadata disagreement across waves"
  )
)

subset_variant <- function(panel, variant) {
  if (variant == "all_panel") return(panel)
  if (variant == "listed_panel") return(panel %>% filter(!out_list))
  if (variant == "listed_consistent_metadata") {
    return(panel %>% filter(!out_list, !any_metadata_mismatch))
  }
  stop("Unknown sample variant: ", variant)
}

standardize_plain <- function(panel, variant) {
  long <- bind_rows(
    panel %>%
      transmute(
        across(c(
          id_student_panel, key, subject, grade, cohort, treated,
          pair_id, school_id, out_list, any_metadata_mismatch
        )),
        wave = "baseline",
        plain_raw_total = plain_raw_total_baseline
      ),
    panel %>%
      transmute(
        across(c(
          id_student_panel, key, subject, grade, cohort, treated,
          pair_id, school_id, out_list, any_metadata_mismatch
        )),
        wave = "endline",
        plain_raw_total = plain_raw_total_endline
      )
  )

  code_stats <- long %>%
    filter(treated == 0L) %>%
    group_by(cohort, wave, subject) %>%
    summarise(
      control_n = n(),
      control_mean = mean(plain_raw_total),
      control_sd = sd(plain_raw_total),
      .groups = "drop"
    ) %>%
    mutate(
      sample_variant = variant,
      standardization = "plain_code_subject_cohort_wave",
      grade = NA_integer_
    )
  if (any(!is.finite(code_stats$control_sd) | code_stats$control_sd <= 0)) {
    stop("Invalid control SD in code-matched plain-score standardization")
  }

  grade_stats <- long %>%
    filter(treated == 0L) %>%
    group_by(cohort, wave, subject, grade) %>%
    summarise(
      control_n = n(),
      control_mean = mean(plain_raw_total),
      control_sd = sd(plain_raw_total),
      .groups = "drop"
    ) %>%
    mutate(
      sample_variant = variant,
      standardization = "plain_report_subject_grade_cohort_wave"
    )
  if (any(!is.finite(grade_stats$control_sd) | grade_stats$control_sd <= 0)) {
    stop("Invalid control SD in grade-specific plain-score standardization")
  }

  scored_long <- long %>%
    left_join(
      code_stats %>%
        select(
          cohort, wave, subject,
          code_mean = control_mean,
          code_sd = control_sd
        ),
      by = c("cohort", "wave", "subject")
    ) %>%
    left_join(
      grade_stats %>%
        select(
          cohort, wave, subject, grade,
          grade_mean = control_mean,
          grade_sd = control_sd
        ),
      by = c("cohort", "wave", "subject", "grade")
    ) %>%
    mutate(
      plain_code_z = (plain_raw_total - code_mean) / code_sd,
      plain_report_grade_z = (plain_raw_total - grade_mean) / grade_sd
    )

  standardization_checks <- bind_rows(
    scored_long %>%
      filter(treated == 0L) %>%
      group_by(cohort, wave, subject) %>%
      summarise(
        achieved_control_mean = mean(plain_code_z),
        achieved_control_sd = sd(plain_code_z),
        .groups = "drop"
      ) %>%
      mutate(
        sample_variant = variant,
        standardization = "plain_code_subject_cohort_wave",
        grade = NA_integer_
      ),
    scored_long %>%
      filter(treated == 0L) %>%
      group_by(cohort, wave, subject, grade) %>%
      summarise(
        achieved_control_mean = mean(plain_report_grade_z),
        achieved_control_sd = sd(plain_report_grade_z),
        .groups = "drop"
      ) %>%
      mutate(
        sample_variant = variant,
        standardization = "plain_report_subject_grade_cohort_wave"
      )
  )

  wide <- scored_long %>%
    select(
      id_student_panel, key, subject, grade, cohort, treated,
      pair_id, school_id, out_list, any_metadata_mismatch,
      wave, plain_code_z, plain_report_grade_z
    ) %>%
    pivot_wider(
      names_from = wave,
      values_from = c(plain_code_z, plain_report_grade_z),
      names_glue = "{.value}_{wave}"
    ) %>%
    mutate(
      plain_code_change = plain_code_z_endline - plain_code_z_baseline,
      plain_report_grade_change =
        plain_report_grade_z_endline - plain_report_grade_z_baseline
    )

  list(
    panel = wide,
    stats = bind_rows(code_stats, grade_stats) %>%
      select(
        sample_variant, standardization, cohort, wave, subject, grade,
        control_n, control_mean, control_sd
      ),
    checks = standardization_checks %>%
      select(
        sample_variant, standardization, cohort, wave, subject, grade,
        achieved_control_mean, achieved_control_sd
      )
  )
}

plain_variants <- imap(sample_variants, function(description, variant) {
  standardize_plain(subset_variant(plain_panel_all, variant), variant)
})

irt_specs <- tribble(
  ~score_method, ~model_label, ~file_name,
  "direct_strict", "Direct fixed Year 1 anchors: strict-summary set", "y3_irt_outcomes_strict_summary.dta",
  "direct_provisional", "Direct fixed Year 1 anchors: provisional non-conflicted ID set", "y3_irt_outcomes_provisional_id.dta",
  "chained_strict", "Selected-path chained links: strict-summary set", "y3_irt_outcomes_chained_strict_summary.dta",
  "chained_provisional", "Selected-path chained links: provisional non-conflicted ID set", "y3_irt_outcomes_chained_provisional_id.dta",
  "pooled_strict_all", "Subject-pooled incomplete-booklet 2PL: all calibration records", "y3_irt_outcomes_joint_subject_pooled_mixture_all_strict_summary.dta",
  "pooled_purified_strict_all", "Subject-pooled 2PL with targeted comparison-only DIF/drift frees", "y3_irt_outcomes_joint_subject_pooled_mixture_all_purified_strict.dta",
  "pooled_purified_andy_core", "Subject-pooled 2PL with Andy-style endline grade-DIF and baseline drift frees", "y3_irt_outcomes_joint_subject_pooled_mixture_all_purified_andy_core.dta",
  "pooled_purified_math_bridge", "Andy-style purification with Math consensus DIF, five-anchor screened-link floor, and four-anchor graph links", "y3_irt_outcomes_joint_subject_pooled_mixture_all_purified_andy_core_math_bridge5.dta",
  "pooled_strict_comparison", "Subject-pooled incomplete-booklet 2PL: comparison-only calibration", "y3_irt_outcomes_joint_subject_pooled_mixture_comparison_only_strict_summary.dta",
  "pooled_strict_school_development", "Subject-pooled 2PL: school-development calibration", "y3_irt_outcomes_joint_subject_pooled_mixture_development_schools_strict_summary.dta",
  "grade_specific_strict_all", "Grade-specific incomplete-booklet 2PL: all calibration records", "y3_irt_outcomes_joint_grade_specific_mixture_all_strict_summary.dta"
)

read_irt_panel <- function(spec, plain_panel) {
  path <- assert_work_input(file.path(derived_dir, spec$file_name[[1]]))
  outcome <- read_dta(path) %>%
    transmute(
      id_student_panel = as.character(id_student_panel),
      wave = as.character(wave),
      subject = as.character(subject),
      grade = as.integer(administered_grade),
      theta = as.numeric(theta_y1_published_z),
      final_outcome_approved = as.integer(final_outcome_approved)
    ) %>%
    filter(wave %in% c("baseline", "endline"))
  if (!nrow(outcome)) stop("IRT outcome is empty: ", spec$file_name[[1]])
  if (any(outcome$final_outcome_approved != 0L)) {
    stop("Unexpected approved status in development IRT outcome")
  }
  if (any(!is.finite(outcome$theta))) {
    stop("IRT outcome contains missing or non-finite theta")
  }
  if (anyDuplicated(outcome[c("id_student_panel", "wave", "subject", "grade")])) {
    stop("Duplicate keys in IRT outcome: ", spec$score_method[[1]])
  }

  wide <- outcome %>%
    select(-final_outcome_approved) %>%
    pivot_wider(names_from = wave, values_from = theta, names_prefix = "irt_") %>%
    filter(!is.na(irt_baseline), !is.na(irt_endline)) %>%
    mutate(
      irt_change = irt_endline - irt_baseline,
      key = paste(id_student_panel, subject, grade, sep = "|")
    )
  if (anyDuplicated(wide$key)) stop("Duplicate balanced IRT panel keys")

  plain_panel %>%
    inner_join(
      wide %>% select(key, irt_baseline, irt_endline, irt_change),
      by = "key"
    )
}

fit_effect <- function(
    panel,
    change_variable,
    baseline_variable,
    endline_variable,
    sample_variant,
    estimand_sample,
    score_method,
    model_label,
    pairing_role,
    subject_scope,
    cohort_scope,
    grade_scope) {
  data <- panel
  if (subject_scope != "Overall") {
    data <- data %>% filter(subject == subject_scope)
  }
  if (cohort_scope != "Pooled_equal_weight") {
    data <- data %>% filter(cohort == as.integer(cohort_scope))
  }
  if (grade_scope != "All_grades") {
    data <- data %>% filter(grade == as.integer(grade_scope))
  }
  data <- data %>%
    filter(
      is.finite(.data[[change_variable]]),
      is.finite(.data[[baseline_variable]]),
      is.finite(.data[[endline_variable]])
    ) %>%
    mutate(
      cluster_id = interaction(cohort, pair_id, drop = TRUE),
      fe_cell = interaction(cohort, pair_id, grade, drop = TRUE)
    ) %>%
    group_by(fe_cell) %>%
    filter(n_distinct(treated) == 2L) %>%
    ungroup()

  if (cohort_scope == "Pooled_equal_weight") {
    data <- data %>%
      group_by(cohort) %>%
      mutate(cohort_weight = 1 / n()) %>%
      ungroup()
  } else {
    data <- data %>% mutate(cohort_weight = 1)
  }

  base_row <- tibble(
    sample_variant = sample_variant,
    estimand_sample = estimand_sample,
    score_method = score_method,
    model_label = model_label,
    pairing_role = pairing_role,
    subject = subject_scope,
    cohort_scope = cohort_scope,
    grade_scope = grade_scope,
    n_students = nrow(data),
    n_panel_observations = 2L * nrow(data),
    n_subjects = n_distinct(data$subject),
    subjects_in_sample = paste(sort(unique(data$subject)), collapse = "+"),
    n_schools = n_distinct(paste(data$cohort, data$school_id, sep = "|")),
    n_pairs = n_distinct(data$cluster_id),
    n_pair_grade_cells = n_distinct(data$fe_cell),
    control_baseline_mean = mean(data[[baseline_variable]][data$treated == 0L]),
    control_endline_mean = mean(data[[endline_variable]][data$treated == 0L]),
    control_change_mean = mean(data[[change_variable]][data$treated == 0L]),
    treated_change_mean = mean(data[[change_variable]][data$treated == 1L])
  )

  if (nrow(data) < 50 || n_distinct(data$cluster_id) < 4) {
    return(base_row %>%
      mutate(
        estimate = NA_real_, std_error = NA_real_, conf_low = NA_real_,
        conf_high = NA_real_, p_value = NA_real_,
        estimation_status = "not_estimated_insufficient_sample"
      ))
  }

  model_formula <- as.formula(paste(change_variable, "~ treated | fe_cell"))
  fit_result <- tryCatch(
    list(
      model = feols(
        model_formula,
        data = data,
        weights = ~ cohort_weight,
        cluster = ~ cluster_id,
        ssc = ssc(
          adj = TRUE,
          cluster.adj = TRUE,
          cluster.df = "min",
          t.df = "min"
        ),
        notes = FALSE
      ),
      error = ""
    ),
    error = function(error) list(model = NULL, error = conditionMessage(error))
  )
  if (is.null(fit_result$model)) {
    return(base_row %>%
      mutate(
        estimate = NA_real_, std_error = NA_real_, conf_low = NA_real_,
        conf_high = NA_real_, p_value = NA_real_,
        estimation_status = paste0("model_error: ", fit_result$error)
      ))
  }

  fit <- fit_result$model
  coefficient_table <- coeftable(fit)
  if (!"treated" %in% rownames(coefficient_table)) {
    return(base_row %>%
      mutate(
        estimate = NA_real_, std_error = NA_real_, conf_low = NA_real_,
        conf_high = NA_real_, p_value = NA_real_,
        estimation_status = "treatment_coefficient_not_identified"
      ))
  }
  interval <- confint(fit, parm = "treated", level = 0.95)
  base_row %>%
    mutate(
      estimate = unname(coefficient_table["treated", "Estimate"]),
      std_error = unname(coefficient_table["treated", "Std. Error"]),
      conf_low = unname(interval[1, 1]),
      conf_high = unname(interval[1, 2]),
      p_value = unname(coefficient_table["treated", "Pr(>|t|)"]),
      estimation_status = "estimated_development_only"
    )
}

subject_scopes <- c("Overall", "Arabic", "French", "Maths")
cohort_scopes <- c("Pooled_equal_weight", "1", "2", "3")
grade_scopes <- c("All_grades", as.character(1:6))

fit_grid <- function(panel, score_definitions, sample_variant, estimand_sample) {
  pmap_dfr(
    crossing(
      score_index = seq_len(nrow(score_definitions)),
      subject_scope = subject_scopes,
      cohort_scope = cohort_scopes,
      grade_scope = grade_scopes
    ),
    function(score_index, subject_scope, cohort_scope, grade_scope) {
      definition <- score_definitions[score_index, ]
      fit_effect(
        panel = panel,
        change_variable = definition$change_variable,
        baseline_variable = definition$baseline_variable,
        endline_variable = definition$endline_variable,
        sample_variant = sample_variant,
        estimand_sample = estimand_sample,
        score_method = definition$score_method,
        model_label = definition$model_label,
        pairing_role = definition$pairing_role,
        subject_scope = subject_scope,
        cohort_scope = cohort_scope,
        grade_scope = grade_scope
      )
    }
  )
}

plain_score_definitions <- tribble(
  ~score_method, ~model_label, ~pairing_role, ~change_variable, ~baseline_variable, ~endline_variable,
  "plain_code", "Binary raw total standardized by subject x cohort x wave controls", "standalone_plain", "plain_code_change", "plain_code_z_baseline", "plain_code_z_endline",
  "plain_report_grade", "Binary raw total standardized by subject x grade x cohort x wave controls", "standalone_plain", "plain_report_grade_change", "plain_report_grade_z_baseline", "plain_report_grade_z_endline"
)

estimate_rows <- list()
contrast_rows <- list()
sample_audit_rows <- list()
method_panel_store <- list()

for (variant in names(plain_variants)) {
  plain_panel <- plain_variants[[variant]]$panel
  variant_method_panels <- list()
  estimate_rows[[paste(variant, "plain", sep = "|")]] <- fit_grid(
    plain_panel,
    plain_score_definitions,
    variant,
    "full_plain_panel"
  )
  sample_audit_rows[[paste(variant, "plain", sep = "|")]] <- plain_panel %>%
    count(subject, cohort, name = "n_students") %>%
    mutate(
      sample_variant = variant,
      estimand_sample = "full_plain_panel",
      method_type = "plain"
    )

  for (spec_index in seq_len(nrow(irt_specs))) {
    spec <- irt_specs[spec_index, ]
    method <- spec$score_method[[1]]
    method_panel <- read_irt_panel(spec, plain_panel)
    variant_method_panels[[method]] <- method_panel
    method_panel_store[[paste(variant, method, sep = "|")]] <- method_panel$key

    definitions <- bind_rows(
      tibble(
        score_method = method,
        model_label = spec$model_label[[1]],
        pairing_role = "irt_target",
        change_variable = "irt_change",
        baseline_variable = "irt_baseline",
        endline_variable = "irt_endline"
      ),
      plain_score_definitions %>%
        mutate(
          pairing_role = "plain_companion_same_student_panel",
          model_label = paste0(model_label, "; evaluated on ", method, " panel")
        )
    )
    estimate_rows[[paste(variant, method, sep = "|")]] <- fit_grid(
      method_panel,
      definitions,
      variant,
      method
    )
    sample_audit_rows[[paste(variant, method, sep = "|")]] <- method_panel %>%
      count(subject, cohort, name = "n_students") %>%
      mutate(
        sample_variant = variant,
        estimand_sample = method,
        method_type = "irt_panel"
      )

    contrast_panel <- method_panel %>%
      mutate(
        contrast_plain_code_baseline =
          irt_baseline - plain_code_z_baseline,
        contrast_plain_code_endline =
          irt_endline - plain_code_z_endline,
        contrast_plain_code_change =
          irt_change - plain_code_change,
        contrast_plain_report_grade_baseline =
          irt_baseline - plain_report_grade_z_baseline,
        contrast_plain_report_grade_endline =
          irt_endline - plain_report_grade_z_endline,
        contrast_plain_report_grade_change =
          irt_change - plain_report_grade_change
      )
    contrast_definitions <- tribble(
      ~score_method, ~model_label, ~pairing_role, ~change_variable, ~baseline_variable, ~endline_variable,
      paste0(method, "_minus_plain_code"), paste0(spec$model_label[[1]], " minus code-matched plain score"), "method_contrast", "contrast_plain_code_change", "contrast_plain_code_baseline", "contrast_plain_code_endline",
      paste0(method, "_minus_plain_report_grade"), paste0(spec$model_label[[1]], " minus grade-standardized plain score"), "method_contrast", "contrast_plain_report_grade_change", "contrast_plain_report_grade_baseline", "contrast_plain_report_grade_endline"
    )
    contrast_rows[[paste(variant, method, "plain", sep = "|")]] <- fit_grid(
      contrast_panel,
      contrast_definitions,
      variant,
      method
    )
  }

  strict_pairs <- tribble(
    ~left_method, ~right_method,
    "chained_strict", "pooled_strict_all",
    "chained_strict", "pooled_strict_comparison",
    "pooled_strict_all", "pooled_strict_comparison",
    "pooled_strict_all", "pooled_purified_strict_all",
    "pooled_strict_all", "pooled_purified_andy_core",
    "pooled_strict_all", "pooled_purified_math_bridge"
  )
  for (pair_index in seq_len(nrow(strict_pairs))) {
    left_method <- strict_pairs$left_method[[pair_index]]
    right_method <- strict_pairs$right_method[[pair_index]]
    left_scores <- variant_method_panels[[left_method]] %>%
      select(key, left_baseline = irt_baseline, left_endline = irt_endline)
    contrast_panel <- variant_method_panels[[right_method]] %>%
      inner_join(left_scores, by = "key") %>%
      mutate(
        contrast_baseline = left_baseline - irt_baseline,
        contrast_endline = left_endline - irt_endline,
        contrast_change = contrast_endline - contrast_baseline
      )
    contrast_method <- paste0(left_method, "_minus_", right_method)
    contrast_definition <- tibble(
      score_method = contrast_method,
      model_label = paste(left_method, "minus", right_method),
      pairing_role = "strict_irt_method_contrast",
      change_variable = "contrast_change",
      baseline_variable = "contrast_baseline",
      endline_variable = "contrast_endline"
    )
    contrast_rows[[paste(variant, contrast_method, sep = "|")]] <- fit_grid(
      contrast_panel,
      contrast_definition,
      variant,
      "strict_core_common_panel"
    )
  }
}

estimates <- bind_rows(estimate_rows) %>%
  mutate(
    year3_estimand = paste(
      "within-Year-3 baseline-to-endline matched DiD; baseline assignment;",
      "pair-by-grade fixed effects; matched-pair clustered SE"
    ),
    final_outcome_approved = 0L
  ) %>%
  arrange(
    sample_variant, estimand_sample, pairing_role,
    score_method, subject, cohort_scope, grade_scope
  )

outcome_contrasts <- bind_rows(contrast_rows) %>%
  mutate(
    year3_estimand = paste(
      "difference between two outcome-specific Year 3 matched-DiD",
      "treatment effects on an identical student panel"
    ),
    final_outcome_approved = 0L
  ) %>%
  arrange(
    sample_variant, estimand_sample, pairing_role,
    score_method, subject, cohort_scope, grade_scope
  )

sample_audit <- bind_rows(sample_audit_rows) %>%
  select(
    sample_variant, estimand_sample, method_type,
    subject, cohort, n_students
  ) %>%
  arrange(sample_variant, estimand_sample, subject, cohort)

overlap_rows <- list()
for (variant in names(plain_variants)) {
  methods <- irt_specs$score_method
  for (left_index in seq_along(methods)) {
    for (right_index in left_index:length(methods)) {
      left_method <- methods[[left_index]]
      right_method <- methods[[right_index]]
      left_keys <- method_panel_store[[paste(variant, left_method, sep = "|")]]
      right_keys <- method_panel_store[[paste(variant, right_method, sep = "|")]]
      intersection_n <- length(intersect(left_keys, right_keys))
      union_n <- length(union(left_keys, right_keys))
      overlap_rows[[length(overlap_rows) + 1L]] <- tibble(
        sample_variant = variant,
        left_method = left_method,
        right_method = right_method,
        left_n = length(left_keys),
        right_n = length(right_keys),
        intersection_n = intersection_n,
        union_n = union_n,
        jaccard = if_else(union_n > 0, intersection_n / union_n, NA_real_),
        identical_panel = identical(sort(left_keys), sort(right_keys))
      )
    }
  }
}
method_overlap <- bind_rows(overlap_rows)

comparison_keys <- c(
  "sample_variant", "estimand_sample", "subject", "cohort_scope",
  "grade_scope"
)
irt_target <- estimates %>%
  filter(pairing_role == "irt_target") %>%
  select(
    all_of(comparison_keys), irt_method = score_method,
    irt_estimate = estimate, irt_se = std_error,
    irt_n_students = n_students, irt_n_pairs = n_pairs,
    irt_status = estimation_status
  )
plain_companion <- estimates %>%
  filter(pairing_role == "plain_companion_same_student_panel") %>%
  select(
    all_of(comparison_keys), plain_method = score_method,
    plain_estimate = estimate, plain_se = std_error,
    plain_n_students = n_students, plain_n_pairs = n_pairs,
    plain_status = estimation_status
  )
method_comparisons <- suppressWarnings(
  left_join(irt_target, plain_companion, by = comparison_keys)
) %>%
  mutate(
    estimate_difference_irt_minus_plain = irt_estimate - plain_estimate,
    same_regression_n = irt_n_students == plain_n_students &
      irt_n_pairs == plain_n_pairs
  ) %>%
  arrange(
    sample_variant, irt_method, plain_method,
    subject, cohort_scope
  )

strict_core <- c(
  "chained_strict", "pooled_strict_all", "pooled_strict_comparison",
  "pooled_purified_strict_all", "pooled_purified_andy_core",
  "pooled_purified_math_bridge"
)
strict_core_dispersion <- estimates %>%
  filter(pairing_role == "irt_target", score_method %in% strict_core) %>%
  group_by(sample_variant, subject, cohort_scope, grade_scope) %>%
  summarise(
    method_n = n_distinct(score_method[estimation_status == "estimated_development_only"]),
    min_estimate = if (all(is.na(estimate))) NA_real_ else min(estimate, na.rm = TRUE),
    max_estimate = if (all(is.na(estimate))) NA_real_ else max(estimate, na.rm = TRUE),
    estimate_range = if_else(
      is.na(min_estimate) | is.na(max_estimate),
      NA_real_,
      max_estimate - min_estimate
    ),
    .groups = "drop"
  )

plain_contrast <- estimates %>%
  filter(
    estimand_sample == "full_plain_panel",
    pairing_role == "standalone_plain"
  ) %>%
  select(
    sample_variant, subject, cohort_scope, grade_scope, score_method,
    estimate, std_error, n_students, n_pairs, estimation_status
  ) %>%
  pivot_wider(
    names_from = score_method,
    values_from = c(estimate, std_error, n_students, n_pairs, estimation_status)
  ) %>%
  mutate(
    estimate_difference_grade_minus_code =
      estimate_plain_report_grade - estimate_plain_code
  )

standardization_stats <- bind_rows(map(plain_variants, "stats"))
standardization_checks <- bind_rows(map(plain_variants, "checks"))

write_csv(
  estimates,
  assert_output(file.path(out_dir, "treatment_effect_estimates.csv")),
  na = ""
)
write_csv(
  outcome_contrasts,
  assert_output(file.path(out_dir, "outcome_treatment_effect_contrasts.csv")),
  na = ""
)
write_csv(
  method_comparisons,
  assert_output(file.path(out_dir, "irt_vs_plain_same_panel.csv")),
  na = ""
)
write_csv(
  strict_core_dispersion,
  assert_output(file.path(out_dir, "strict_core_effect_dispersion.csv")),
  na = ""
)
write_csv(
  plain_contrast,
  assert_output(file.path(out_dir, "plain_standardization_contrast.csv")),
  na = ""
)
write_csv(
  sample_audit,
  assert_output(file.path(out_dir, "analysis_sample_audit.csv")),
  na = ""
)
write_csv(
  method_overlap,
  assert_output(file.path(out_dir, "irt_method_panel_overlap.csv")),
  na = ""
)
write_csv(
  item_audit,
  assert_output(file.path(out_dir, "plain_score_binary_item_audit.csv")),
  na = ""
)
write_csv(
  standardization_stats,
  assert_output(file.path(out_dir, "plain_score_standardization_constants.csv")),
  na = ""
)
write_csv(
  standardization_checks,
  assert_output(file.path(out_dir, "plain_score_standardization_checks.csv")),
  na = ""
)

principal_summary <- estimates %>%
  filter(
    sample_variant == "listed_panel",
    subject == "Overall",
    cohort_scope == "Pooled_equal_weight",
    grade_scope == "All_grades",
    (
      pairing_role == "irt_target" |
        (estimand_sample == "full_plain_panel" & pairing_role == "standalone_plain")
    )
  ) %>%
  select(
    score_method, model_label, pairing_role, estimand_sample,
    estimate, std_error, conf_low, conf_high, p_value,
    n_students, n_subjects, subjects_in_sample, n_schools, n_pairs,
    estimation_status
  ) %>%
  arrange(pairing_role, score_method)
write_csv(
  principal_summary,
  assert_output(file.path(out_dir, "principal_pooled_overall_comparison.csv")),
  na = ""
)

principal_contrasts <- outcome_contrasts %>%
  filter(
    sample_variant == "listed_panel",
    subject == "Overall",
    cohort_scope == "Pooled_equal_weight",
    grade_scope == "All_grades"
  ) %>%
  select(
    score_method, model_label, pairing_role, estimand_sample,
    estimate, std_error, conf_low, conf_high, p_value,
    n_students, n_subjects, subjects_in_sample, n_schools, n_pairs,
    estimation_status
  ) %>%
  arrange(pairing_role, score_method)
write_csv(
  principal_contrasts,
  assert_output(file.path(out_dir, "principal_pooled_overall_contrasts.csv")),
  na = ""
)

run_summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  status = "development_only_unapproved",
  estimand = paste(
    "Year 3 baseline-to-endline intent-to-treat matched difference-in-differences;",
    "this is a within-Year-3 measurement sensitivity, not a cumulative one-,",
    "two-, or three-year cohort exposure estimate."
  ),
  specification = list(
    assignment = "baseline treatment assignment and cohort",
    fixed_effects = "matched-pair by baseline grade in first differences",
    standard_errors = "clustered by matched pair; cohort-specific pair IDs in pooled models",
    pooled_weighting = "equal total weight for each cohort within the exact regression subset",
    covariates = paste(
      "none in this development pass because the approved Year 3 wave files do not",
      "contain the full production PDS-LASSO covariate set"
    )
  ),
  scoring = list(
    irt = paste(
      "theta_y1_published_z: fixed Year 1 endline matched-comparison",
      "mean and SD; Year 1 baseline is not the reference"
    ),
    plain_code = paste(
      "verified binary raw total standardized to Year 3 controls separately",
      "by subject, cohort, and wave, matching the production do-file"
    ),
    plain_report_grade = paste(
      "verified binary raw total standardized to Year 3 controls separately",
      "by subject, grade, cohort, and wave, matching the written report language"
    ),
    nonbinary_rule = "all non-binary items excluded before score construction"
  ),
  sample_variants = as.list(sample_variants),
  source_registry_verification = registered_sources,
  input_hashes = list(
    anchor_manifest_sha256 = sha256_file(anchor_manifest_path),
    irt_outcomes = set_names(
      map_chr(irt_specs$file_name, ~ sha256_file(file.path(derived_dir, .x))),
      irt_specs$score_method
    )
  ),
  counts = list(
    binary_manifest_item_occurrences_all_waves = nrow(
      read_csv(anchor_manifest_path, show_col_types = FALSE)
    ),
    binary_manifest_item_occurrences_baseline_endline = nrow(manifest),
    observed_nonbinary_item_occurrences_excluded =
      sum(item_audit$excluded_observed_nonbinary_item_n),
    raw_balanced_panel_students_before_sample_restrictions = nrow(plain_panel_all),
    estimate_rows = nrow(estimates),
    contrast_rows = nrow(outcome_contrasts),
    successfully_estimated_rows = sum(
      estimates$estimation_status == "estimated_development_only"
    ),
    successfully_estimated_contrasts = sum(
      outcome_contrasts$estimation_status == "estimated_development_only"
    )
  ),
  calibration_treatment_blind = TRUE,
  data_written_to_github = FALSE,
  student_level_output_written = FALSE,
  final_outcome_approved = FALSE,
  deferred_issue = paste(
    "The previously observed approximately 1.60 raw-theta location shift is",
    "not resolved here; this run tests whether it changes the estimated ITT effect."
  ),
  software = list(
    R = R.version.string,
    fixest = as.character(packageVersion("fixest")),
    haven = as.character(packageVersion("haven"))
  )
)
writeLines(
  toJSON(run_summary, pretty = TRUE, auto_unbox = TRUE, na = "null"),
  assert_output(file.path(out_dir, "run_summary.json"))
)

cat(toJSON(run_summary$counts, pretty = TRUE, auto_unbox = TRUE), "\n")
print(principal_summary, n = Inf)
