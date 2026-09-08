#!/usr/bin/env Rscript

# Build an aggregate, treatment-blind Year 2 form/item registry from explicitly
# registered wave-specific development inputs. No student-level data are written.

suppressPackageStartupMessages({
  library(dplyr)
  library(haven)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("Usage: build_y2_operational_registry.R config/paths.local.yml")
}

config_path <- normalizePath(args[[1]], mustWork = TRUE)
paths <- yaml::read_yaml(config_path)$dropbox
source_roots <- normalizePath(
  c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE
)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)

normalize_for_guard <- function(path) normalizePath(path, mustWork = FALSE)
is_within <- function(path, root) {
  candidate <- normalize_for_guard(path)
  boundary <- normalize_for_guard(root)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_source <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!any(map_lgl(source_roots, ~ is_within(candidate, .x)))) {
    stop("Input is outside approved legacy roots: ", candidate)
  }
  candidate
}
assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) {
    stop("Output must be below work_root: ", candidate)
  }
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) {
    stop("Output resolves inside a legacy source root: ", candidate)
  }
  candidate
}

wave_specs <- tribble(
  ~wave, ~relative_path, ~id_column,
  "baseline", "4 - Data processing/04_Baseline/Clean/baseline_data.dta", "id_student_yr2",
  "pilot", "4 - Data processing/08_Pilot/Clean/pilot_data_20250505_ya.dta", "student_id",
  "endline", "4 - Data processing/09_Endline/Clean/endline_data_20250716_ks.dta", "id_student"
) %>%
  mutate(path = map_chr(relative_path, ~ assert_source(file.path(paths$y2_root, .x))))

subject_prefix <- c(Arabic = "a", French = "f", Maths = "m")
label_character <- function(x) as.character(haven::as_factor(x))

deduplicate_node <- function(data, id_column, item_vars) {
  data <- data %>% mutate(.source_row = row_number())
  answered <- if (length(item_vars)) {
    rowSums(sapply(data[item_vars], function(x) {
      tag <- haven::na_tag(x)
      !is.na(x) | (!is.na(tag) & tag == "a")
    }))
  } else {
    rep(0, nrow(data))
  }
  duration_value <- if ("duration" %in% names(data)) {
    suppressWarnings(as.numeric(data$duration))
  } else {
    rep(0, nrow(data))
  }
  id_key <- as.character(data[[id_column]])
  missing_id <- is.na(id_key) | id_key == ""
  id_key[missing_id] <- paste0("__missing_row_", data$.source_row[missing_id])
  data %>%
    mutate(.id_key = id_key, .answered = answered, .duration_value = duration_value) %>%
    arrange(.id_key, desc(.answered), desc(.duration_value), .source_row) %>%
    distinct(.id_key, .keep_all = TRUE) %>%
    arrange(.source_row) %>%
    select(-.id_key, -.answered, -.duration_value)
}

registry_rows <- list()
node_rows <- list()
wave_rows <- list()

for (spec_index in seq_len(nrow(wave_specs))) {
  wave_value <- wave_specs$wave[spec_index]
  id_column <- wave_specs$id_column[spec_index]
  raw <- read_dta(wave_specs$path[spec_index])
  if (!all(c("subject", "grade", id_column) %in% names(raw))) {
    stop("Missing subject, grade, or ID column in Year 2 ", wave_value)
  }
  subject_value <- label_character(raw$subject)
  grade_value <- label_character(raw$grade)
  treatment_like <- names(raw)[str_detect(
    names(raw), regex("treat|assign|intervention|pioneer", ignore_case = TRUE)
  )]
  wave_duplicate_removed <- 0L

  for (subject_name in names(subject_prefix)) {
    item_vars <- names(raw)[str_detect(
      names(raw), regex(paste0("^", subject_prefix[[subject_name]], "[0-9]"))
    )]
    grades <- sort(unique(grade_value[subject_value == subject_name]))
    grades <- grades[!is.na(grades) & grades != ""]
    for (grade_name in grades) {
      node_raw <- raw[subject_value == subject_name & grade_value == grade_name, , drop = FALSE]
      node <- deduplicate_node(node_raw, id_column, item_vars)
      duplicate_removed <- nrow(node_raw) - nrow(node)
      wave_duplicate_removed <- wave_duplicate_removed + duplicate_removed
      if (!nrow(node)) next

      administered_n <- map_int(item_vars, function(item) {
        {
          tag <- haven::na_tag(node[[item]])
          sum(!is.na(node[[item]]) | (!is.na(tag) & tag == "a"))
        }
      })
      administered_rate <- administered_n / nrow(node)
      administered_items <- item_vars[administered_rate >= 0.80]
      off_form_positive <- sum(administered_n > 0 & administered_rate < 0.80)

      for (item in administered_items) {
        value <- node[[item]]
        tag <- haven::na_tag(value)
        administered <- !is.na(value) | (!is.na(tag) & tag == "a")
        observed_value <- suppressWarnings(as.numeric(value[!is.na(value)]))
        unexpected_nonbinary_n <- sum(!observed_value %in% c(0, 1))
        binary_irt_eligible <- length(observed_value) > 0 && unexpected_nonbinary_n == 0
        correct <- !is.na(value) & suppressWarnings(as.numeric(value)) == 1
        correct_n <- sum(correct)
        item_administered_n <- sum(administered)
        registry_rows[[paste(wave_value, subject_name, grade_name, item, sep = "|")]] <- tibble(
          year = 2L,
          wave = wave_value,
          subject = subject_name,
          administered_grade = as.character(grade_name),
          node_id = paste("Y2", wave_value, subject_name, grade_name, sep = "|"),
          item_id = item,
          n_students = nrow(node),
          administered_n = item_administered_n,
          administered_rate = item_administered_n / nrow(node),
          correct_n = if (binary_irt_eligible) correct_n else NA_integer_,
          incorrect_or_dont_know_n = if (binary_irt_eligible) {
            item_administered_n - correct_n
          } else {
            NA_integer_
          },
          p_correct = if (binary_irt_eligible) correct_n / item_administered_n else NA_real_,
          observed_nonmissing_n = length(observed_value),
          unexpected_nonbinary_n = unexpected_nonbinary_n,
          observed_min = if (length(observed_value)) min(observed_value) else NA_real_,
          observed_max = if (length(observed_value)) max(observed_value) else NA_real_,
          binary_irt_eligible = as.integer(binary_irt_eligible),
          variable_after_binary_scoring = as.integer(
            binary_irt_eligible && correct_n > 0 && correct_n < item_administered_n
          ),
          item_type = if (binary_irt_eligible) {
            "binary_1_correct_other_administered_0"
          } else {
            "nonbinary_excluded_from_2pl"
          },
          treatment_used = 0L,
          source_status = "provisional_development_input_requires_confirmation"
        )
      }

      node_rows[[paste(wave_value, subject_name, grade_name, sep = "|")]] <- tibble(
        year = 2L,
        wave = wave_value,
        subject = subject_name,
        administered_grade = as.character(grade_name),
        node_id = paste("Y2", wave_value, subject_name, grade_name, sep = "|"),
        n_source_rows = nrow(node_raw),
        n_deduplicated_students = nrow(node),
        duplicate_rows_removed = duplicate_removed,
        administered_item_n = length(administered_items),
        binary_irt_item_n = sum(map_lgl(administered_items, function(item) {
          value <- node[[item]]
          observed_value <- suppressWarnings(as.numeric(value[!is.na(value)]))
          length(observed_value) > 0 && all(observed_value %in% c(0, 1))
        })),
        nonbinary_excluded_item_n = sum(map_lgl(administered_items, function(item) {
          value <- node[[item]]
          observed_value <- suppressWarnings(as.numeric(value[!is.na(value)]))
          length(observed_value) > 0 && any(!observed_value %in% c(0, 1))
        })),
        variable_binary_item_n = sum(map_lgl(administered_items, function(item) {
          value <- node[[item]]
          tag <- haven::na_tag(value)
          administered <- !is.na(value) | (!is.na(tag) & tag == "a")
          observed_value <- suppressWarnings(as.numeric(value[!is.na(value)]))
          correct_n <- sum(!is.na(value) & suppressWarnings(as.numeric(value)) == 1)
          length(observed_value) > 0 && all(observed_value %in% c(0, 1)) &&
            correct_n > 0 && correct_n < sum(administered)
        })),
        partially_administered_column_n = off_form_positive,
        treatment_like_field_n = length(treatment_like),
        treatment_used = 0L,
        source_status = "provisional_development_input_requires_confirmation"
      )
    }
  }

  wave_rows[[wave_value]] <- tibble(
    year = 2L,
    wave = wave_value,
    source_relative_path = wave_specs$relative_path[spec_index],
    source_row_n = nrow(raw),
    source_column_n = ncol(raw),
    node_n = sum(map_lgl(node_rows, ~ .x$wave[[1]] == wave_value)),
    duplicate_rows_removed = wave_duplicate_removed,
    treatment_used = 0L,
    source_status = "provisional_development_input_requires_confirmation"
  )
  rm(raw)
  invisible(gc())
}

registry <- bind_rows(registry_rows) %>% arrange(subject, wave, as.numeric(administered_grade), item_id)
nodes <- bind_rows(node_rows) %>% arrange(subject, wave, as.numeric(administered_grade))
waves <- bind_rows(wave_rows) %>% arrange(wave)
if (!nrow(registry) || !nrow(nodes)) stop("Year 2 operational registry is empty")

out_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/00_y2_sources"))
derived_dir <- assert_output(file.path(work_root, "derived/y1_y3_irt"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

registry_path <- assert_output(file.path(derived_dir, "y2_operational_item_registry.csv"))
node_path <- assert_output(file.path(out_dir, "y2_operational_node_summary.csv"))
wave_path <- assert_output(file.path(out_dir, "y2_operational_wave_summary.csv"))
summary_path <- assert_output(file.path(out_dir, "y2_operational_registry_summary.json"))
write_csv(registry, registry_path, na = "")
write_csv(nodes, node_path, na = "")
write_csv(waves, wave_path, na = "")

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  wave_n = nrow(waves),
  node_n = nrow(nodes),
  node_item_n = nrow(registry),
  source_row_n = sum(waves$source_row_n),
  duplicate_rows_removed = sum(waves$duplicate_rows_removed),
  partially_administered_column_n = sum(nodes$partially_administered_column_n),
  binary_irt_node_item_n = sum(registry$binary_irt_eligible == 1),
  nonbinary_excluded_node_item_n = sum(registry$binary_irt_eligible == 0),
  treatment_used = FALSE,
  scoring_rule = "For verified binary columns, one is correct; zero and tagged don't-know are incorrect; untagged system missing remains missing. Nonbinary columns are excluded from 2PL IRT.",
  administration_rule = "An item belongs to a form when at least 80 percent of deduplicated node records carry an administered value; observed Year 2 form rates were checked separately.",
  status = "development_only_requires_source_confirmation"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), summary_path)
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
