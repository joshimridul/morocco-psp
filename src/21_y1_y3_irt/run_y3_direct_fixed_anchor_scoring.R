#!/usr/bin/env Rscript

# Development-only Year 3 scoring on the verified Year 1 2PL metric.
# This first pass uses direct fixed Year 1 anchors only. Nodes that require a
# chained Year 3 bridge are reported and left unscored rather than forced.

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
if (length(args) < 1 || length(args) > 3) {
  stop(
    "Usage: run_y3_direct_fixed_anchor_scoring.R config/paths.local.yml ",
    "[strict_summary|provisional_id] [baseline,endline|baseline,pilot,endline]"
  )
}

config_path <- normalizePath(args[[1]], mustWork = TRUE)
anchor_mode <- if (length(args) >= 2) args[[2]] else "strict_summary"
requested_waves <- if (length(args) >= 3) str_split(args[[3]], ",", simplify = TRUE) else c("baseline", "endline")
requested_waves <- as.character(requested_waves[requested_waves != ""])
if (!anchor_mode %in% c("strict_summary", "provisional_id")) {
  stop("Unknown anchor mode: ", anchor_mode)
}
if (!all(requested_waves %in% c("baseline", "pilot", "endline"))) {
  stop("Unknown wave requested: ", paste(setdiff(requested_waves, c("baseline", "pilot", "endline")), collapse = ", "))
}

paths <- yaml::read_yaml(config_path)$dropbox
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)

normalize_for_guard <- function(path) {
  normalizePath(path, mustWork = FALSE)
}

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
    stop("Output must be below the dedicated work root: ", candidate)
  }
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) {
    stop("Output resolves inside a legacy root: ", candidate)
  }
  candidate
}

set.seed(20260804)

wave_files <- c(
  baseline = file.path(paths$y3_root, "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta"),
  pilot = file.path(paths$y3_root, "4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta"),
  endline = file.path(paths$y3_root, "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta")
)
wave_files <- wave_files[requested_waves]
walk(wave_files, assert_source)

registry_path <- file.path(work_root, "derived/y3_ministry/y3_item_version_registry.csv")
manifest_path <- file.path(work_root, "outputs/y1_y3_irt/01_link_design/y3_y1_anchor_manifest.csv")
if (!file.exists(registry_path)) stop("Missing Year 3 item registry: ", registry_path)
if (!file.exists(manifest_path)) stop("Missing Year 1 anchor manifest: ", manifest_path)

registry <- read_csv(registry_path, show_col_types = FALSE) %>%
  mutate(form_grade = as.character(form_grade))
manifest <- read_csv(manifest_path, show_col_types = FALSE) %>%
  mutate(administered_grade = as.character(administered_grade))

anchor_flag <- if (anchor_mode == "strict_summary") "strict_development_anchor" else "provisional_id_anchor"
out_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/02_y3_direct_scoring", anchor_mode))
derived_dir <- assert_output(file.path(work_root, "derived/y1_y3_irt"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

label_character <- function(x) as.character(haven::as_factor(x))

prepare_form <- function(data, form_map) {
  item_vars <- intersect(unique(form_map$item_id), names(data))
  form <- data %>%
    filter(
      label_character(subject) == first(form_map$subject),
      label_character(grade) == first(form_map$form_grade)
    ) %>%
    mutate(.source_row = row_number())
  if (nrow(form) == 0) return(form)
  answered <- if (length(item_vars)) {
    rowSums(sapply(form[item_vars], function(x) {
      tag <- haven::na_tag(x)
      !is.na(x) | (!is.na(tag) & tag == "a")
    }))
  } else {
    rep(0, nrow(form))
  }
  duration_value <- if ("duration" %in% names(form)) {
    suppressWarnings(as.numeric(form$duration))
  } else {
    rep(0, nrow(form))
  }
  id_key <- as.character(form$id_student_panel)
  missing_id <- is.na(id_key) | id_key == ""
  id_key[missing_id] <- paste0("__row_", form$.source_row[missing_id])
  form %>%
    mutate(.id_key = id_key, .answered = answered, .duration_value = duration_value) %>%
    arrange(.id_key, desc(.answered), desc(.duration_value), .source_row) %>%
    distinct(.id_key, .keep_all = TRUE) %>%
    arrange(.source_row) %>%
    select(-.id_key, -.answered, -.duration_value)
}

binary_matrix <- function(form, item_ids) {
  items <- intersect(item_ids, names(form))
  if (!length(items)) return(matrix(numeric(), nrow = nrow(form), ncol = 0))
  result <- sapply(form[items], function(x) {
    value <- suppressWarnings(as.numeric(x))
    scored <- rep(NA_real_, length(x))
    scored[!is.na(x)] <- as.numeric(value[!is.na(x)] == 1)
    tag <- haven::na_tag(x)
    scored[!is.na(tag) & tag == "a"] <- 0
    scored
  })
  if (length(items) == 1) {
    result <- matrix(result, ncol = 1, dimnames = list(NULL, items))
  }
  result
}

nonconstant_columns <- function(matrix) {
  if (!ncol(matrix)) return(character())
  colnames(matrix)[apply(matrix, 2, function(x) length(unique(x[!is.na(x)])) == 2)]
}

fit_fixed_anchor_model <- function(response_matrix, anchor_table) {
  values <- mirt(
    response_matrix,
    1,
    itemtype = "2PL",
    pars = "values",
    verbose = FALSE
  )
  for (index in seq_len(nrow(anchor_table))) {
    item <- anchor_table$item_id[index]
    a <- anchor_table$y1_discrimination_a[index]
    d <- anchor_table$mirt_intercept_d[index]
    a_row <- values$item == item & values$name == "a1"
    d_row <- values$item == item & values$name == "d"
    if (sum(a_row) != 1 || sum(d_row) != 1) {
      stop("Could not identify one mirt slope and intercept row for anchor ", item)
    }
    values$value[a_row] <- a
    values$value[d_row] <- d
    values$est[a_row | d_row] <- FALSE
  }
  group_rows <- values$item == "GROUP" & values$name %in% c("MEAN_1", "COV_11")
  if (sum(group_rows) != 2) stop("Could not identify the latent mean and variance rows")
  values$est[group_rows] <- TRUE
  values$value[values$item == "GROUP" & values$name == "MEAN_1"] <- 0
  values$value[values$item == "GROUP" & values$name == "COV_11"] <- 1
  mirt(
    response_matrix,
    1,
    itemtype = "2PL",
    pars = values,
    verbose = FALSE,
    technical = list(NCYCLES = 1500)
  )
}

outcomes <- list()
model_rows <- list()
parameter_rows <- list()

for (wave in names(wave_files)) {
  message("Reading treatment-blind Year 3 ", wave, " data")
  raw <- read_dta(wave_files[[wave]])
  treatment_like <- names(raw)[str_detect(names(raw), regex("treat|assign|intervention|pioneer", ignore_case = TRUE))]
  wave_map <- registry %>% filter(.data$wave == .env$wave)
  forms <- wave_map %>% distinct(subject, form_grade) %>% arrange(subject, as.numeric(form_grade))

  for (form_index in seq_len(nrow(forms))) {
    subject_value <- forms$subject[form_index]
    grade_value <- forms$form_grade[form_index]
    node_id <- paste(wave, subject_value, grade_value, sep = "|")
    message("Scoring node ", node_id)
    form_map <- wave_map %>%
      filter(subject == subject_value, form_grade == grade_value) %>%
      distinct(item_id, .keep_all = TRUE)
    form <- prepare_form(raw, form_map)
    node_manifest <- manifest %>%
      filter(
        .data$wave == .env$wave,
        .data$subject == .env$subject_value,
        .data$administered_grade == .env$grade_value
      )
    response <- binary_matrix(form, node_manifest$item_id)
    variable_items <- nonconstant_columns(response)
    response <- response[, variable_items, drop = FALSE]
    anchors <- node_manifest %>%
      filter(.data[[anchor_flag]] == 1, item_id %in% variable_items) %>%
      distinct(item_id, .keep_all = TRUE)
    anchor_n <- nrow(anchors)
    difficulty_range <- if (anchor_n >= 2) {
      diff(range(anchors$y1_difficulty_b))
    } else {
      NA_real_
    }

    base_summary <- tibble(
      model_id = node_id,
      wave = wave,
      subject = subject_value,
      administered_grade = grade_value,
      anchor_mode = anchor_mode,
      n_students = nrow(form),
      modeled_item_n = ncol(response),
      fixed_anchor_n = anchor_n,
      fixed_anchor_difficulty_range = difficulty_range,
      treatment_like_fields_excluded_n = length(treatment_like),
      treatment_used_in_calibration = 0L
    )

    if (nrow(form) < 100 || ncol(response) < 5 || anchor_n < 5) {
      model_rows[[node_id]] <- base_summary %>%
        mutate(
          converged = 0L,
          calibration_status = case_when(
            n_students < 100 ~ "not_estimated_fewer_than_100_students",
            modeled_item_n < 5 ~ "not_estimated_fewer_than_5_variable_items",
            TRUE ~ "not_estimated_fewer_than_5_direct_fixed_anchors"
          ),
          log_likelihood = NA_real_, AIC = NA_real_, BIC = NA_real_,
          latent_mean = NA_real_, latent_variance = NA_real_, error = ""
        )
      next
    }

    fit_result <- tryCatch(
      list(model = fit_fixed_anchor_model(response, anchors), error = ""),
      error = function(error) list(model = NULL, error = conditionMessage(error))
    )
    if (is.null(fit_result$model)) {
      model_rows[[node_id]] <- base_summary %>%
        mutate(
          converged = 0L, calibration_status = "model_error",
          log_likelihood = NA_real_, AIC = NA_real_, BIC = NA_real_,
          latent_mean = NA_real_, latent_variance = NA_real_, error = fit_result$error
        )
      next
    }

    model <- fit_result$model
    converged <- isTRUE(extract.mirt(model, "converged"))
    coefficients <- coef(model, IRTpars = TRUE, simplify = TRUE)
    latent_mean <- as.numeric(coefficients$means[1])
    latent_variance <- as.numeric(coefficients$cov[1, 1])
    if (!converged) {
      model_rows[[node_id]] <- base_summary %>%
        mutate(
          converged = 0L,
          calibration_status = "estimated_not_converged",
          log_likelihood = as.numeric(extract.mirt(model, "logLik")),
          AIC = as.numeric(extract.mirt(model, "AIC")),
          BIC = as.numeric(extract.mirt(model, "BIC")),
          latent_mean = latent_mean,
          latent_variance = latent_variance,
          error = ""
        )
      rm(model)
      invisible(gc())
      next
    }
    scores <- fscores(model, method = "EAP", full.scores.SE = TRUE)
    ref_mean <- first(node_manifest$y1_reference_mean)
    ref_sd <- first(node_manifest$y1_reference_sd)
    cohort_value <- if ("cohort" %in% names(form)) label_character(form$cohort) else rep("", nrow(form))

    outcomes[[node_id]] <- tibble(
      id_student_panel = as.character(form$id_student_panel),
      wave = wave,
      cohort = cohort_value,
      subject = subject_value,
      administered_grade = grade_value,
      model_id = node_id,
      anchor_mode = anchor_mode,
      theta_y1_metric = as.numeric(scores[, "F1"]),
      se_theta_y1_metric = as.numeric(scores[, "SE_F1"]),
      theta_y1_published_z = (theta_y1_metric - ref_mean) / ref_sd,
      se_theta_y1_published_z = se_theta_y1_metric / ref_sd,
      scale_status = "development_only_direct_anchor_link",
      final_outcome_approved = 0L
    )

    item_parameters <- as.data.frame(coefficients$items)
    item_parameters$item_id <- rownames(item_parameters)
    parameter_rows[[node_id]] <- as_tibble(item_parameters) %>%
      transmute(
        model_id = node_id,
        wave = wave,
        subject = subject_value,
        administered_grade = grade_value,
        item_id = item_id,
        discrimination_a = a,
        difficulty_b = b,
        fixed_y1_anchor = as.integer(item_id %in% anchors$item_id),
        anchor_mode = anchor_mode,
        scale_status = "development_only_direct_anchor_link"
      )

    model_rows[[node_id]] <- base_summary %>%
      mutate(
        converged = as.integer(converged),
        calibration_status = "estimated_development_only",
        log_likelihood = as.numeric(extract.mirt(model, "logLik")),
        AIC = as.numeric(extract.mirt(model, "AIC")),
        BIC = as.numeric(extract.mirt(model, "BIC")),
        latent_mean = latent_mean,
        latent_variance = latent_variance,
        error = ""
      )
    rm(model)
    invisible(gc())
  }
  rm(raw)
  invisible(gc())
}

outcome_table <- bind_rows(outcomes)
model_table <- bind_rows(model_rows)
parameter_table <- bind_rows(parameter_rows)

outcome_csv <- assert_output(file.path(derived_dir, paste0("y3_irt_outcomes_", anchor_mode, ".csv")))
outcome_dta <- assert_output(file.path(derived_dir, paste0("y3_irt_outcomes_", anchor_mode, ".dta")))
model_csv <- assert_output(file.path(out_dir, "y3_direct_fixed_anchor_model_summary.csv"))
parameter_csv <- assert_output(file.path(out_dir, "y3_direct_fixed_anchor_item_parameters.csv"))
summary_json <- assert_output(file.path(out_dir, "y3_direct_fixed_anchor_run_summary.json"))

write_csv(outcome_table, outcome_csv, na = "")
write_dta(outcome_table, outcome_dta, version = 15)
write_csv(model_table, model_csv, na = "")
write_csv(parameter_table, parameter_csv, na = "")

run_summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  anchor_mode = anchor_mode,
  requested_waves = requested_waves,
  node_n = nrow(model_table),
  estimated_node_n = sum(model_table$calibration_status == "estimated_development_only"),
  nonconverged_node_n = sum(model_table$calibration_status == "estimated_not_converged"),
  skipped_node_n = sum(str_starts(model_table$calibration_status, "not_estimated")),
  outcome_row_n = nrow(outcome_table),
  treatment_used_in_calibration = FALSE,
  score_definition = paste(
    "EAP theta from a node-specific 2PL model with direct Year 1 anchor parameters fixed;",
    "latent mean and variance estimated on the Year 1 metric."
  ),
  standardization = "Fixed Year 1 endline matched-comparison mean and SD; no Year 3 treatment field used.",
  status = "development_only",
  final_use_blockers = c(
    "canonical source confirmation",
    "full item-version and exposure review",
    "chained links for skipped nodes",
    "anchor-set and link-path sensitivity",
    "treatment-related DIF after measurement rules are frozen"
  )
)
writeLines(toJSON(run_summary, pretty = TRUE, auto_unbox = TRUE), summary_json)
cat(toJSON(run_summary, pretty = TRUE, auto_unbox = TRUE), "\n")
