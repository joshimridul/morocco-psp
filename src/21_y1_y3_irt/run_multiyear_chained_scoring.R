#!/usr/bin/env Rscript

# Development-only node-by-node chained calibration on the fixed Year 1 metric.
# Each target node fixes at least five direct Year 1 anchors or bridge-item
# parameters inherited from its selected parent node. Treatment is never used.

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
if (length(args) < 1 || length(args) > 2) {
  stop("Usage: run_multiyear_chained_scoring.R config/paths.local.yml [strict_summary|provisional_id]")
}
config_path <- normalizePath(args[[1]], mustWork = TRUE)
anchor_mode <- if (length(args) == 2) args[[2]] else "strict_summary"
if (!anchor_mode %in% c("strict_summary", "provisional_id")) stop("Unknown anchor mode")

paths <- yaml::read_yaml(config_path)$dropbox
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
normalize_for_guard <- function(path) normalizePath(path, mustWork = FALSE)
is_within <- function(path, root) {
  candidate <- normalize_for_guard(path)
  boundary <- normalize_for_guard(root)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_source <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Input outside approved roots: ", candidate)
  candidate
}
assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Output inside a legacy root")
  candidate
}

set.seed(20260804)
source_specs <- tribble(
  ~source_key, ~year, ~wave, ~relative_path, ~id_column,
  "Y2|baseline", 2L, "baseline", "4 - Data processing/04_Baseline/Clean/baseline_data.dta", "id_student_yr2",
  "Y2|pilot", 2L, "pilot", "4 - Data processing/08_Pilot/Clean/pilot_data_20250505_ya.dta", "student_id",
  "Y2|endline", 2L, "endline", "4 - Data processing/09_Endline/Clean/endline_data_20250716_ks.dta", "id_student",
  "Y3|baseline", 3L, "baseline", "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta", "id_student_panel",
  "Y3|pilot", 3L, "pilot", "4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta", "id_student_panel",
  "Y3|endline", 3L, "endline", "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta", "id_student_panel"
) %>%
  mutate(
    root = if_else(year == 2L, paths$y2_root, paths$y3_root),
    path = map2_chr(root, relative_path, ~ assert_source(file.path(.x, .y)))
  )

graph_dir <- file.path(work_root, "outputs/y1_y3_irt/01_multiyear_link_graph")
occurrence_path <- file.path(graph_dir, "multiyear_item_occurrence_manifest.csv")
link_item_path <- file.path(graph_dir, "multiyear_link_item_manifest.csv")
paths_path <- file.path(graph_dir, "multiyear_selected_paths.csv")
walk(c(occurrence_path, link_item_path, paths_path), ~ if (!file.exists(.x)) stop("Missing graph input: ", .x))
occurrences <- read_csv(occurrence_path, show_col_types = FALSE) %>%
  mutate(administered_grade = as.character(administered_grade))
link_items <- read_csv(link_item_path, show_col_types = FALSE)
selected <- read_csv(paths_path, show_col_types = FALSE) %>%
  mutate(administered_grade = as.character(administered_grade)) %>%
  filter(anchor_mode == .env$anchor_mode)

target_paths <- selected %>%
  filter(year %in% c(2L, 3L), wave %in% c("baseline", "endline"), path_status == "linked_development_only")
active_nodes <- unique(unlist(str_split(target_paths$selected_path, fixed(">"))))
active_nodes <- active_nodes[str_detect(active_nodes, regex("^Y[23]\\|"))]
fit_order <- selected %>%
  filter(node_id %in% active_nodes, path_status == "linked_development_only") %>%
  arrange(as.numeric(path_depth), subject, year, wave, as.numeric(administered_grade))

label_character <- function(x) as.character(haven::as_factor(x))
data_cache <- list()
get_source_data <- function(year, wave) {
  key <- paste0("Y", year, "|", wave)
  if (is.null(data_cache[[key]])) {
    spec <- source_specs %>% filter(source_key == key)
    if (nrow(spec) != 1) stop("No unique source specification for ", key)
    message("Reading treatment-blind source ", key)
    data_cache[[key]] <<- read_dta(spec$path[[1]])
  }
  data_cache[[key]]
}

prepare_node <- function(data, id_column, subject_value, grade_value, item_vars) {
  form <- data %>%
    filter(
      label_character(subject) == .env$subject_value,
      label_character(grade) == .env$grade_value
    ) %>%
    mutate(.source_row = row_number())
  if (!nrow(form)) return(form)
  item_vars <- intersect(item_vars, names(form))
  answered <- if (length(item_vars)) {
    rowSums(sapply(form[item_vars], function(x) {
      tag <- haven::na_tag(x)
      !is.na(x) | (!is.na(tag) & tag == "a")
    }))
  } else rep(0, nrow(form))
  duration_value <- if ("duration" %in% names(form)) suppressWarnings(as.numeric(form$duration)) else rep(0, nrow(form))
  id_key <- as.character(form[[id_column]])
  missing_id <- is.na(id_key) | id_key == ""
  id_key[missing_id] <- paste0("__missing_row_", form$.source_row[missing_id])
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
    unexpected <- !is.na(value) & !value %in% c(0, 1)
    if (any(unexpected)) {
      stop("Non-binary observed response reached the 2PL scorer for item ", deparse(substitute(x)))
    }
    scored <- rep(NA_real_, length(x))
    scored[!is.na(x)] <- as.numeric(value[!is.na(x)] == 1)
    tag <- haven::na_tag(x)
    scored[!is.na(tag) & tag == "a"] <- 0
    scored
  })
  if (length(items) == 1) result <- matrix(result, ncol = 1, dimnames = list(NULL, items))
  result
}
nonconstant_columns <- function(matrix) {
  if (!ncol(matrix)) return(character())
  colnames(matrix)[apply(matrix, 2, function(x) length(unique(x[!is.na(x)])) == 2)]
}

fit_fixed_anchor_model <- function(response_matrix, anchors) {
  values <- mirt(response_matrix, 1, itemtype = "2PL", pars = "values", verbose = FALSE)
  for (index in seq_len(nrow(anchors))) {
    item <- anchors$item_id[index]
    a_row <- values$item == item & values$name == "a1"
    d_row <- values$item == item & values$name == "d"
    if (sum(a_row) != 1 || sum(d_row) != 1) stop("Cannot identify anchor parameter rows for ", item)
    values$value[a_row] <- anchors$discrimination_a[index]
    values$value[d_row] <- -anchors$discrimination_a[index] * anchors$difficulty_b[index]
    values$est[a_row | d_row] <- FALSE
  }
  group_rows <- values$item == "GROUP" & values$name %in% c("MEAN_1", "COV_11")
  values$est[group_rows] <- TRUE
  values$value[values$item == "GROUP" & values$name == "MEAN_1"] <- 0
  values$value[values$item == "GROUP" & values$name == "COV_11"] <- 1
  mirt(response_matrix, 1, itemtype = "2PL", pars = values, verbose = FALSE, technical = list(NCYCLES = 1500))
}

parameter_bank <- list()
model_rows <- list()
parameter_rows <- list()
outcomes <- list()
strict_flag <- if (anchor_mode == "strict_summary") "direct_y1_strict_anchor" else "direct_y1_provisional_anchor"
link_flag <- if (anchor_mode == "strict_summary") "strict_summary_link" else "provisional_id_link"

for (index in seq_len(nrow(fit_order))) {
  path_row <- fit_order[index, ]
  node_id <- path_row$node_id[[1]]
  year_value <- path_row$year[[1]]
  wave_value <- path_row$wave[[1]]
  subject_value <- path_row$subject[[1]]
  grade_value <- path_row$administered_grade[[1]]
  parent <- path_row$parent_node_id[[1]]
  message("Fitting chained node ", node_id, " from ", parent)
  spec <- source_specs %>% filter(year == year_value, wave == wave_value)
  raw <- get_source_data(year_value, wave_value)
  treatment_like <- names(raw)[str_detect(names(raw), regex("treat|assign|intervention|pioneer", ignore_case = TRUE))]
  node_occurrences <- occurrences %>% filter(.data$node_id == .env$node_id)
  form <- prepare_node(raw, spec$id_column[[1]], subject_value, grade_value, node_occurrences$item_id)
  response <- binary_matrix(form, node_occurrences$item_id)
  variable_items <- nonconstant_columns(response)
  response <- response[, variable_items, drop = FALSE]

  if (startsWith(parent, "Y1|reference|")) {
    anchors <- node_occurrences %>%
      filter(.data[[strict_flag]] == 1, item_id %in% variable_items) %>%
      transmute(
        item_id,
        discrimination_a = as.numeric(y1_discrimination_a),
        difficulty_b = as.numeric(y1_difficulty_b)
      ) %>%
      distinct(item_id, .keep_all = TRUE)
    anchor_source <- "fixed_y1_reference"
  } else {
    if (is.null(parameter_bank[[parent]])) stop("Parent parameters unavailable for ", node_id)
    edge_items <- link_items %>%
      filter(
        ((node_a == parent & node_b == node_id) | (node_b == parent & node_a == node_id)),
        .data[[link_flag]] == 1,
        item_id %in% variable_items
      ) %>%
      distinct(item_id, .keep_all = TRUE)
    anchors <- parameter_bank[[parent]] %>%
      filter(item_id %in% edge_items$item_id) %>%
      select(item_id, discrimination_a, difficulty_b) %>%
      distinct(item_id, .keep_all = TRUE)
    anchor_source <- "fixed_parent_bridge_parameters"
  }

  base <- tibble(
    model_id = node_id,
    node_id = node_id,
    year = year_value,
    wave = wave_value,
    subject = subject_value,
    administered_grade = grade_value,
    anchor_mode = anchor_mode,
    path_depth = as.integer(path_row$path_depth[[1]]),
    parent_node_id = parent,
    anchor_source = anchor_source,
    n_students = nrow(form),
    modeled_item_n = ncol(response),
    fixed_anchor_n = nrow(anchors),
    treatment_like_fields_excluded_n = length(treatment_like),
    treatment_used_in_calibration = 0L
  )

  if (nrow(form) < 100 || ncol(response) < 5 || nrow(anchors) < 5) {
    model_rows[[node_id]] <- base %>% mutate(
      converged = 0L,
      calibration_status = case_when(
        n_students < 100 ~ "not_estimated_fewer_than_100_students",
        modeled_item_n < 5 ~ "not_estimated_fewer_than_5_variable_items",
        TRUE ~ "not_estimated_fewer_than_5_available_path_anchors"
      ),
      log_likelihood = NA_real_, AIC = NA_real_, BIC = NA_real_,
      latent_mean = NA_real_, latent_variance = NA_real_, error = ""
    )
    next
  }

  warning_messages <- character()
  fit <- tryCatch(
    list(
      model = withCallingHandlers(
        fit_fixed_anchor_model(response, anchors),
        warning = function(warning) {
          warning_messages <<- c(warning_messages, conditionMessage(warning))
          invokeRestart("muffleWarning")
        }
      ),
      error = ""
    ),
    error = function(error) list(model = NULL, error = conditionMessage(error))
  )
  if (is.null(fit$model)) {
    model_rows[[node_id]] <- base %>% mutate(
      converged = 0L, calibration_status = "model_error",
      log_likelihood = NA_real_, AIC = NA_real_, BIC = NA_real_,
      latent_mean = NA_real_, latent_variance = NA_real_,
      warning = paste(unique(warning_messages), collapse = " | "), error = fit$error
    )
    next
  }

  model <- fit$model
  coefficients <- coef(model, IRTpars = TRUE, simplify = TRUE)
  item_parameters <- as.data.frame(coefficients$items)
  item_parameters$item_id <- rownames(item_parameters)
  bank <- as_tibble(item_parameters) %>%
    transmute(item_id, discrimination_a = a, difficulty_b = b)
  parameter_bank[[node_id]] <- bank
  parameter_rows[[node_id]] <- bank %>%
    mutate(
      model_id = node_id, year = year_value, wave = wave_value,
      subject = subject_value, administered_grade = grade_value,
      fixed_anchor = as.integer(item_id %in% anchors$item_id),
      anchor_source = anchor_source, anchor_mode = anchor_mode,
      scale_status = "development_only_chained_y1_metric"
    ) %>%
    select(model_id, year, wave, subject, administered_grade, item_id,
           discrimination_a, difficulty_b, fixed_anchor, anchor_source,
           anchor_mode, scale_status)

  converged <- isTRUE(extract.mirt(model, "converged"))
  model_rows[[node_id]] <- base %>% mutate(
    converged = as.integer(converged),
    calibration_status = case_when(
      !converged ~ "estimated_not_converged",
      length(warning_messages) > 0 ~ "estimated_with_warning",
      TRUE ~ "estimated_development_only"
    ),
    log_likelihood = as.numeric(extract.mirt(model, "logLik")),
    AIC = as.numeric(extract.mirt(model, "AIC")),
    BIC = as.numeric(extract.mirt(model, "BIC")),
    latent_mean = as.numeric(coefficients$means[1]),
    latent_variance = as.numeric(coefficients$cov[1, 1]),
    warning = paste(unique(warning_messages), collapse = " | "),
    error = ""
  )

  # A nonconverged node cannot supply bridge parameters to a child and cannot
  # emit ability scores.
  if (!converged) {
    parameter_bank[[node_id]] <- NULL
    parameter_rows[[node_id]] <- NULL
    rm(model)
    invisible(gc())
    next
  }

  if (year_value %in% c(2L, 3L) && wave_value %in% c("baseline", "endline")) {
    score <- fscores(model, method = "EAP", full.scores.SE = TRUE)
    cohort_value <- if ("cohort" %in% names(form)) label_character(form$cohort) else rep("", nrow(form))
    ref_mean <- first(node_occurrences$y1_reference_mean)
    ref_sd <- first(node_occurrences$y1_reference_sd)
    outcomes[[node_id]] <- tibble(
      id_student_panel = as.character(form[[spec$id_column[[1]]]]),
      year = year_value,
      wave = wave_value,
      cohort = cohort_value,
      subject = subject_value,
      administered_grade = grade_value,
      model_id = node_id,
      anchor_mode = anchor_mode,
      link_path_depth = as.integer(path_row$path_depth[[1]]),
      parent_node_id = parent,
      theta_y1_metric = as.numeric(score[, "F1"]),
      se_theta_y1_metric = as.numeric(score[, "SE_F1"]),
      theta_y1_published_z = (theta_y1_metric - ref_mean) / ref_sd,
      se_theta_y1_published_z = se_theta_y1_metric / ref_sd,
      scale_status = "development_only_chained_y1_metric",
      final_outcome_approved = 0L
    )
  }
  rm(model)
  invisible(gc())
}

outcome_table <- bind_rows(outcomes)
model_table <- bind_rows(model_rows)
parameter_table <- bind_rows(parameter_rows)
out_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/03_chained_scoring", anchor_mode))
derived_dir <- assert_output(file.path(work_root, "derived/y1_y3_irt"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

outcome_csv <- assert_output(file.path(derived_dir, paste0("multiyear_irt_outcomes_chained_", anchor_mode, ".csv")))
outcome_dta <- assert_output(file.path(derived_dir, paste0("multiyear_irt_outcomes_chained_", anchor_mode, ".dta")))
y3_outcome_csv <- assert_output(file.path(derived_dir, paste0("y3_irt_outcomes_chained_", anchor_mode, ".csv")))
y3_outcome_dta <- assert_output(file.path(derived_dir, paste0("y3_irt_outcomes_chained_", anchor_mode, ".dta")))
model_csv <- assert_output(file.path(out_dir, "multiyear_chained_model_summary.csv"))
parameter_csv <- assert_output(file.path(out_dir, "multiyear_chained_item_parameters.csv"))
summary_json <- assert_output(file.path(out_dir, "multiyear_chained_run_summary.json"))
write_csv(outcome_table, outcome_csv, na = "")
write_dta(outcome_table, outcome_dta, version = 15)
write_csv(filter(outcome_table, year == 3L), y3_outcome_csv, na = "")
write_dta(filter(outcome_table, year == 3L), y3_outcome_dta, version = 15)
write_csv(model_table, model_csv, na = "")
write_csv(parameter_table, parameter_csv, na = "")

target_total <- selected %>% filter(year %in% c(2L, 3L), wave %in% c("baseline", "endline")) %>% nrow()
summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  anchor_mode = anchor_mode,
  active_path_node_n = nrow(fit_order),
  estimated_path_node_n = sum(str_starts(model_table$calibration_status, "estimated_")),
  estimated_with_warning_node_n = sum(model_table$calibration_status == "estimated_with_warning"),
  nonconverged_path_node_n = sum(model_table$calibration_status == "estimated_not_converged"),
  failed_or_skipped_path_node_n = sum(!str_starts(model_table$calibration_status, "estimated_")),
  multiyear_baseline_endline_target_node_n = target_total,
  multiyear_scored_node_n = length(outcomes),
  multiyear_unlinked_graph_node_n = target_total - nrow(target_paths),
  y3_baseline_endline_target_node_n = sum(selected$year == 3L & selected$wave %in% c("baseline", "endline")),
  y3_scored_node_n = sum(model_table$year == 3L & model_table$wave %in% c("baseline", "endline") & model_table$converged == 1L),
  outcome_row_n = nrow(outcome_table),
  treatment_used_in_calibration = FALSE,
  score_definition = "EAP theta from node-specific 2PL calibrations with direct Year 1 or selected parent bridge parameters fixed.",
  status = "development_only_not_approved",
  final_use_blockers = c(
    "canonical Year 2 and Year 3 source confirmation",
    "full item-version and exposure review",
    "path and anchor-set sensitivity",
    "joint-model and comparison-only sensitivity",
    "treatment-related DIF after measurement rules are frozen"
  )
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), summary_json)
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
