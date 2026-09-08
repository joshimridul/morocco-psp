#!/usr/bin/env Rscript

# Joint multi-group sensitivity calibration for Year 2 and Year 3 responses.
# The model is subject-specific. Item parameters are invariant across linked
# form/cohort groups; verified development anchors remain fixed to the archived
# Year 1 metric. Unrestricted specifications free group means and variances;
# efficient pooled-mixture specifications estimate node distributions only
# after the item bank is frozen. Subjects remain separate constructs.

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
if (length(args) < 1 || length(args) > 4) {
  stop(paste(
    "Usage: run_joint_multigroup_scoring.R config/paths.local.yml",
    "[strict_summary|provisional_id|purified_strict|purified_andy_core|purified_andy_core_math_bridge5] [all|comparison_only|development_schools]",
    "[subject_pooled|subject_pooled_mixture|grade_specific|grade_specific_mixture]"
  ))
}
config_path <- normalizePath(args[[1]], mustWork = TRUE)
anchor_mode <- if (length(args) >= 2) args[[2]] else "strict_summary"
sample_mode <- if (length(args) >= 3) args[[3]] else "all"
model_scope <- if (length(args) >= 4) args[[4]] else "subject_pooled"
purified_modes <- c("purified_strict", "purified_andy_core", "purified_andy_core_math_bridge5")
if (!anchor_mode %in% c("strict_summary", "provisional_id", purified_modes)) stop("Unknown anchor mode")
if (!sample_mode %in% c("all", "comparison_only", "development_schools")) stop("Unknown sample mode")
if (!model_scope %in% c("subject_pooled", "subject_pooled_mixture", "grade_specific", "grade_specific_mixture")) stop("Unknown model scope")

local_config <- yaml::read_yaml(config_path)
analysis_config <- yaml::read_yaml(file.path(dirname(config_path), "analysis.yml"))
paths <- local_config$dropbox
optimization <- analysis_config$irt_optimization
calibration_max_cycles <- if (is.null(optimization$calibration_max_cycles)) 1500L else optimization$calibration_max_cycles
primary_calibration_max_cycles <- if (is.null(optimization$primary_calibration_max_cycles)) calibration_max_cycles else optimization$primary_calibration_max_cycles
node_distribution_max_cycles <- if (is.null(optimization$node_distribution_max_cycles)) 1000L else optimization$node_distribution_max_cycles
estimated_discrimination_upper_bound <- if (is.null(optimization$estimated_discrimination_upper_bound)) Inf else optimization$estimated_discrimination_upper_bound
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
assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Output inside legacy root")
  candidate
}

set.seed(20260804)
source_specs <- tribble(
  ~source_key, ~year, ~wave, ~relative_path, ~id_column, ~treatment_column,
  "Y2|baseline", 2L, "baseline", "4 - Data processing/04_Baseline/Clean/baseline_data.dta", "id_student_yr2", "treated_y2",
  "Y2|pilot", 2L, "pilot", "4 - Data processing/08_Pilot/Clean/pilot_data_20250505_ya.dta", "student_id", "",
  "Y2|endline", 2L, "endline", "4 - Data processing/09_Endline/Clean/endline_data_20250716_ks.dta", "id_student", "treated_y2",
  "Y3|baseline", 3L, "baseline", "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta", "id_student_panel", "treated",
  "Y3|pilot", 3L, "pilot", "4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta", "id_student_panel", "treated",
  "Y3|endline", 3L, "endline", "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta", "id_student_panel", "treated"
) %>%
  mutate(
    root = if_else(year == 2L, paths$y2_root, paths$y3_root),
    path = map2_chr(root, relative_path, ~ assert_source(file.path(.x, .y)))
  )

graph_dir <- file.path(work_root, "outputs/y1_y3_irt/01_multiyear_link_graph")
occurrences <- read_csv(file.path(graph_dir, "multiyear_item_occurrence_manifest.csv"), show_col_types = FALSE) %>%
  mutate(administered_grade = as.character(administered_grade))
cohort_overrides <- tibble(
  subject = character(), strict_item_version_id = character(), item_id = character(),
  node_id = character(), cohort = character(), override_analysis_key = character()
)
if (anchor_mode %in% purified_modes) {
  purified_files <- list(
    purified_strict = c(
      mapping = "multiyear_purified_targeted_occurrence_mapping.csv",
      override = "multiyear_purified_cohort_key_overrides.csv",
      path = "multiyear_targeted_purified_selected_paths.csv"
    ),
    purified_andy_core = c(
      mapping = "multiyear_purified_andy_core_occurrence_mapping.csv",
      override = "multiyear_purified_andy_core_cohort_key_overrides.csv",
      path = "multiyear_andy_core_purified_selected_paths.csv"
    ),
    purified_andy_core_math_bridge5 = c(
      mapping = "multiyear_purified_andy_core_math_bridge5_occurrence_mapping.csv",
      override = "multiyear_purified_andy_core_math_bridge5_cohort_key_overrides.csv",
      path = "multiyear_andy_core_math_bridge5_purified_selected_paths.csv"
    )
  )
  mapping_file <- purified_files[[anchor_mode]][["mapping"]]
  override_file <- purified_files[[anchor_mode]][["override"]]
  path_file <- purified_files[[anchor_mode]][["path"]]
  mapping <- read_csv(
    file.path(work_root, "derived/y1_y3_irt", mapping_file),
    show_col_types = FALSE
  ) %>% select(node_id, item_id, purified_analysis_key, purified_direct_y1_anchor)
  occurrences <- occurrences %>% left_join(mapping, by = c("node_id", "item_id"))
  if (any(is.na(occurrences$purified_analysis_key))) stop("Purified occurrence mapping is incomplete")
  cohort_overrides <- read_csv(
    file.path(work_root, "derived/y1_y3_irt", override_file),
    show_col_types = FALSE
  )
  selected <- read_csv(
    file.path(work_root, "outputs/y1_y3_irt/05_anchor_purification/comparison_only", path_file),
    show_col_types = FALSE
  ) %>%
    mutate(administered_grade = as.character(administered_grade)) %>%
    filter(path_status == "linked_development_only")
} else {
  selected <- read_csv(file.path(graph_dir, "multiyear_selected_paths.csv"), show_col_types = FALSE) %>%
    mutate(administered_grade = as.character(administered_grade)) %>%
    filter(anchor_mode == .env$anchor_mode, path_status == "linked_development_only")
}

label_character <- function(x) as.character(haven::as_factor(x))
stable_school_split <- function(value) {
  vapply(as.character(value), function(text) {
    if (is.na(text) || text == "") return("missing_school")
    integers <- utf8ToInt(text)
    bucket <- sum(integers * seq_along(integers)) %% 2
    if (bucket == 0) "development" else "validation"
  }, character(1))
}
data_cache <- list()
get_source_data <- function(year, wave) {
  key <- paste0("Y", year, "|", wave)
  if (is.null(data_cache[[key]])) {
    spec <- source_specs %>% filter(source_key == key)
    message("Reading source ", key)
    data_cache[[key]] <<- read_dta(spec$path[[1]])
  }
  data_cache[[key]]
}

cohort_values <- function(data, year, wave) {
  if (year == 2L && wave == "baseline") return(rep("2", nrow(data)))
  if (year == 2L && wave == "endline" && all(c("cohort1", "cohort2") %in% names(data))) {
    return(ifelse(as.numeric(data$cohort1) == 1, "1", ifelse(as.numeric(data$cohort2) == 1, "2", "unknown")))
  }
  if ("cohort" %in% names(data)) return(label_character(data$cohort))
  rep("pilot_or_unspecified", nrow(data))
}

prepare_node <- function(node_row, node_occurrences) {
  year_value <- node_row$year[[1]]; wave_value <- node_row$wave[[1]]
  subject_value <- node_row$subject[[1]]; grade_value <- node_row$administered_grade[[1]]
  spec <- source_specs %>% filter(year == year_value, wave == wave_value)
  raw <- get_source_data(year_value, wave_value)
  subject_all <- label_character(raw$subject); grade_all <- label_character(raw$grade)
  keep <- subject_all == subject_value & grade_all == grade_value
  form <- raw[keep, , drop = FALSE] %>% mutate(.source_row = row_number())
  if (!nrow(form)) return(NULL)
  source_row_n <- nrow(form)
  item_vars <- intersect(node_occurrences$item_id, names(form))
  answered <- rowSums(sapply(form[item_vars], function(x) {
    tag <- haven::na_tag(x)
    !is.na(x) | (!is.na(tag) & tag == "a")
  }))
  duration_value <- if ("duration" %in% names(form)) suppressWarnings(as.numeric(form$duration)) else rep(0, nrow(form))
  id_key <- as.character(form[[spec$id_column[[1]]]])
  missing_id <- is.na(id_key) | id_key == ""
  id_key[missing_id] <- paste0("__missing_row_", form$.source_row[missing_id])
  duplicated_student_n <- n_distinct(id_key[duplicated(id_key) | duplicated(id_key, fromLast = TRUE)])
  form <- form %>%
    mutate(.id_key = id_key, .answered = answered, .duration_value = duration_value) %>%
    arrange(.id_key, desc(.answered), desc(.duration_value), .source_row) %>%
    distinct(.id_key, .keep_all = TRUE) %>%
    arrange(.source_row)

  treatment <- rep(NA_real_, nrow(form))
  if (spec$treatment_column[[1]] != "" && spec$treatment_column[[1]] %in% names(form)) {
    treatment <- suppressWarnings(as.numeric(form[[spec$treatment_column[[1]]]]))
  }
  cohort <- cohort_values(form, year_value, wave_value)
  school_column <- intersect(c("school_id", "school"), names(form))
  school_split <- if (length(school_column)) {
    stable_school_split(form[[school_column[[1]]]])
  } else {
    rep("missing_school", nrow(form))
  }
  local <- sapply(form[item_vars], function(x) {
    value <- suppressWarnings(as.numeric(x))
    unexpected <- !is.na(value) & !value %in% c(0, 1)
    if (any(unexpected)) stop("Non-binary observed response reached the 2PL scorer")
    scored <- rep(NA_real_, length(x))
    scored[!is.na(x)] <- as.numeric(value[!is.na(x)] == 1)
    tag <- haven::na_tag(x)
    scored[!is.na(tag) & tag == "a"] <- 0
    scored
  })
  if (length(item_vars) == 1) local <- matrix(local, ncol = 1, dimnames = list(NULL, item_vars))
  list(
    meta = tibble(
      source_id = as.character(form[[spec$id_column[[1]]]]),
      node_id = node_row$node_id[[1]], year = year_value, wave = wave_value,
      cohort = cohort, subject = subject_value, administered_grade = grade_value,
      treatment = treatment, school_split = school_split
    ),
    response = local,
    item_ids = item_vars,
    duplicate_audit = tibble(
      node_id = node_row$node_id[[1]], year = year_value, wave = wave_value,
      subject = subject_value, administered_grade = grade_value,
      source_row_n = source_row_n, retained_row_n = nrow(form),
      removed_duplicate_row_n = source_row_n - nrow(form),
      duplicated_student_n = duplicated_student_n,
      missing_id_row_n = sum(missing_id),
      resolution_rule = "most answered eligible binary items; then longest duration; then source row order"
    )
  )
}

analysis_key <- function(node_occurrences) {
  if (anchor_mode %in% purified_modes) {
    node_occurrences$purified_analysis_key
  } else if (anchor_mode == "strict_summary") {
    ifelse(
      !is.na(node_occurrences$current_summary_hash) & node_occurrences$current_summary_hash != "",
      paste(node_occurrences$subject, node_occurrences$item_id, node_occurrences$current_summary_hash, sep = "|"),
      paste(node_occurrences$node_id, node_occurrences$item_id, sep = "|")
    )
  } else {
    ifelse(
      node_occurrences$known_version_conflict == 0,
      paste(node_occurrences$subject, node_occurrences$item_id, sep = "|"),
      paste(node_occurrences$node_id, node_occurrences$item_id, sep = "|")
    )
  }
}

assemble_scope <- function(scope_nodes) {
  pieces <- list(); key_rows <- list()
  for (index in seq_len(nrow(scope_nodes))) {
    node <- scope_nodes[index, ]
    occurrence <- occurrences %>% filter(node_id == node$node_id[[1]])
    occurrence$analysis_key <- analysis_key(occurrence)
    piece <- prepare_node(node, occurrence)
    if (is.null(piece)) next
    raw_to_key <- setNames(occurrence$analysis_key, occurrence$item_id)
    kept_ids <- piece$item_ids[piece$item_ids %in% names(raw_to_key)]
    piece$response <- piece$response[, kept_ids, drop = FALSE]
    if (anchor_mode %in% purified_modes) {
      expanded <- list()
      node_overrides <- cohort_overrides %>% filter(node_id == node$node_id[[1]])
      for (item in kept_ids) {
        base_key <- unname(raw_to_key[[item]])
        base_response <- piece$response[, item]
        item_overrides <- node_overrides %>% filter(.data$item_id == .env$item)
        if (nrow(item_overrides)) {
          for (override_index in seq_len(nrow(item_overrides))) {
            target <- piece$meta$cohort == as.character(item_overrides$cohort[[override_index]])
            override_response <- rep(NA_real_, length(base_response))
            override_response[target] <- base_response[target]
            base_response[target] <- NA_real_
            expanded[[item_overrides$override_analysis_key[[override_index]]]] <- override_response
          }
        }
        expanded[[base_key]] <- base_response
      }
      piece$response <- do.call(cbind, expanded)
      if (is.null(dim(piece$response))) piece$response <- matrix(piece$response, ncol = 1)
      colnames(piece$response) <- names(expanded)
    } else {
      colnames(piece$response) <- unname(raw_to_key[kept_ids])
    }
    pieces[[node$node_id[[1]]]] <- piece
    key_rows[[node$node_id[[1]]]] <- occurrence %>% filter(item_id %in% kept_ids)
  }
  if (!length(pieces)) return(NULL)
  keys <- sort(unique(unlist(map(pieces, ~ colnames(.x$response)))))
  code_map <- tibble(analysis_key = keys, item_code = sprintf("I%04d", seq_along(keys)))
  matrices <- list(); metas <- list()
  for (node_id in names(pieces)) {
    piece <- pieces[[node_id]]
    matrix <- matrix(NA_real_, nrow = nrow(piece$response), ncol = nrow(code_map), dimnames = list(NULL, code_map$item_code))
    codes <- code_map$item_code[match(colnames(piece$response), code_map$analysis_key)]
    matrix[, codes] <- piece$response
    matrices[[node_id]] <- matrix
    metas[[node_id]] <- piece$meta
  }
  list(
    response = do.call(rbind, matrices),
    meta = bind_rows(metas),
    code_map = code_map,
    occurrence = bind_rows(key_rows),
    node_piece = pieces,
    duplicate_audit = bind_rows(map(pieces, "duplicate_audit"))
  )
}

fit_joint <- function(response, group, anchors, max_cycles = calibration_max_cycles) {
  values <- multipleGroup(
    response, 1, group = group, itemtype = "2PL", pars = "values",
    invariance = c("slopes", "intercepts", "free_means", "free_var"), verbose = FALSE
  )
  for (index in seq_len(nrow(anchors))) {
    code <- anchors$item_code[index]
    a_rows <- values$item == code & values$name == "a1"
    d_rows <- values$item == code & values$name == "d"
    if (!any(a_rows) || !any(d_rows)) stop("Missing joint anchor rows for ", code)
    values$value[a_rows] <- anchors$discrimination_a[index]
    values$value[d_rows] <- -anchors$discrimination_a[index] * anchors$difficulty_b[index]
    values$est[a_rows | d_rows] <- FALSE
  }
  free_slope_rows <- values$name == "a1" & values$est
  values$ubound[free_slope_rows] <- pmin(
    values$ubound[free_slope_rows], estimated_discrimination_upper_bound
  )
  group_rows <- values$item == "GROUP" & values$name %in% c("MEAN_1", "COV_11")
  values$est[group_rows] <- TRUE
  values$value[values$item == "GROUP" & values$name == "MEAN_1"] <- 0
  values$value[values$item == "GROUP" & values$name == "COV_11"] <- 1
  multipleGroup(
    response, 1, group = group, itemtype = "2PL", pars = values,
    invariance = c("slopes", "intercepts", "free_means", "free_var"),
    verbose = FALSE, technical = list(NCYCLES = max_cycles)
  )
}

fit_joint_pooled <- function(response, anchors, max_cycles = calibration_max_cycles) {
  values <- mirt(response, 1, itemtype = "2PL", pars = "values", verbose = FALSE)
  for (index in seq_len(nrow(anchors))) {
    code <- anchors$item_code[index]
    a_row <- values$item == code & values$name == "a1"
    d_row <- values$item == code & values$name == "d"
    if (sum(a_row) != 1 || sum(d_row) != 1) stop("Missing pooled anchor rows for ", code)
    values$value[a_row] <- anchors$discrimination_a[index]
    values$value[d_row] <- -anchors$discrimination_a[index] * anchors$difficulty_b[index]
    values$est[a_row | d_row] <- FALSE
  }
  free_slope_rows <- values$name == "a1" & values$est
  values$ubound[free_slope_rows] <- pmin(
    values$ubound[free_slope_rows], estimated_discrimination_upper_bound
  )
  # This is an item-parameter sensitivity model. Keep the pooled mixture at
  # N(0,1) for stability, then estimate each scoring node's distribution after
  # the pooled item parameters are frozen.
  group_rows <- values$item == "GROUP" & values$name %in% c("MEAN_1", "COV_11")
  values$est[group_rows] <- FALSE
  values$value[values$item == "GROUP" & values$name == "MEAN_1"] <- 0
  values$value[values$item == "GROUP" & values$name == "COV_11"] <- 1
  mirt(response, 1, itemtype = "2PL", pars = values, verbose = FALSE,
       technical = list(NCYCLES = max_cycles))
}

fit_fixed_item_scoring_model <- function(response, item_parameters) {
  values <- mirt(response, 1, itemtype = "2PL", pars = "values", verbose = FALSE)
  for (index in seq_len(nrow(item_parameters))) {
    code <- item_parameters$item_code[index]
    a_row <- values$item == code & values$name == "a1"
    d_row <- values$item == code & values$name == "d"
    values$value[a_row] <- item_parameters$discrimination_a[index]
    values$value[d_row] <- -item_parameters$discrimination_a[index] * item_parameters$difficulty_b[index]
    values$est[a_row | d_row] <- FALSE
  }
  group_rows <- values$item == "GROUP" & values$name %in% c("MEAN_1", "COV_11")
  values$est[group_rows] <- TRUE
  values$value[values$item == "GROUP" & values$name == "MEAN_1"] <- 0
  values$value[values$item == "GROUP" & values$name == "COV_11"] <- 1
  mirt(response, 1, itemtype = "2PL", pars = values, verbose = FALSE,
       technical = list(NCYCLES = node_distribution_max_cycles))
}

scope_rows <- if (model_scope %in% c("subject_pooled", "subject_pooled_mixture")) {
  tibble(subject = names(c(Arabic = 1, French = 1, Maths = 1)), administered_grade = "all")
} else {
  selected %>% distinct(subject, administered_grade) %>% arrange(subject, as.numeric(administered_grade))
}

model_rows <- list(); parameter_rows <- list(); group_rows_output <- list(); outcome_rows <- list(); node_score_rows <- list(); duplicate_rows <- list()
item_fit_rows <- list(); global_fit_rows <- list(); local_dependence_rows <- list()
is_primary_specification <- identical(anchor_mode, "purified_andy_core_math_bridge5") &&
  identical(sample_mode, "all") && identical(model_scope, "subject_pooled_mixture")
this_calibration_max_cycles <- if (is_primary_specification) {
  primary_calibration_max_cycles
} else {
  calibration_max_cycles
}
direct_flag <- case_when(
  anchor_mode == "strict_summary" ~ "direct_y1_strict_anchor",
  anchor_mode == "provisional_id" ~ "direct_y1_provisional_anchor",
  anchor_mode %in% purified_modes ~ "purified_direct_y1_anchor"
)

for (scope_index in seq_len(nrow(scope_rows))) {
  subject_value <- scope_rows$subject[scope_index]
  grade_scope <- scope_rows$administered_grade[scope_index]
  scope_id <- if (model_scope %in% c("subject_pooled", "subject_pooled_mixture")) paste(subject_value, "all_grades", sep = "|") else paste(subject_value, grade_scope, sep = "|")
  message("Joint calibration scope ", scope_id, " / ", sample_mode, " / ", anchor_mode)
  scope_nodes <- selected %>% filter(subject == subject_value)
  if (model_scope %in% c("grade_specific", "grade_specific_mixture")) scope_nodes <- scope_nodes %>% filter(administered_grade == grade_scope)
  assembled <- assemble_scope(scope_nodes)
  if (is.null(assembled)) next
  duplicate_rows[[scope_id]] <- assembled$duplicate_audit %>%
    mutate(scope_id = scope_id, model_scope = model_scope,
           sample_mode = sample_mode, anchor_mode = anchor_mode)

  response_all <- assembled$response
  meta_all <- assembled$meta
  globally_variable <- apply(response_all, 2, function(x) length(unique(x[!is.na(x)])) == 2)
  response_all <- response_all[, globally_variable, drop = FALSE]
  code_map <- assembled$code_map %>% filter(item_code %in% colnames(response_all))
  occurrence_keys <- assembled$occurrence
  occurrence_keys$analysis_key <- analysis_key(occurrence_keys)
  anchors <- occurrence_keys %>%
    filter(.data[[direct_flag]] == 1) %>%
    inner_join(code_map, by = "analysis_key") %>%
    transmute(
      item_code,
      discrimination_a = as.numeric(y1_discrimination_a),
      difficulty_b = as.numeric(y1_difficulty_b)
    ) %>%
    distinct(item_code, .keep_all = TRUE)

  calibration_keep <- if (sample_mode == "all") {
    rep(TRUE, nrow(meta_all))
  } else if (sample_mode == "comparison_only") {
    !is.na(meta_all$treatment) & meta_all$treatment == 0
  } else {
    meta_all$school_split == "development"
  }
  group_label <- paste(meta_all$node_id, meta_all$cohort, sep = "|cohort=")
  group_counts <- table(group_label[calibration_keep])
  allowed_groups <- names(group_counts)[group_counts >= 50]
  calibration_keep <- calibration_keep & group_label %in% allowed_groups
  response_calibration <- response_all[calibration_keep, , drop = FALSE]
  group_calibration_label <- group_label[calibration_keep]
  retained_items <- apply(response_calibration, 2, function(x) length(unique(x[!is.na(x)])) == 2)
  response_calibration <- response_calibration[, retained_items, drop = FALSE]
  response_all <- response_all[, colnames(response_calibration), drop = FALSE]
  code_map <- code_map %>% filter(item_code %in% colnames(response_calibration))
  anchors <- anchors %>% filter(item_code %in% colnames(response_calibration))
  group_levels <- sort(unique(group_calibration_label))
  group_code_map <- setNames(sprintf("G%03d", seq_along(group_levels)), group_levels)
  group_calibration <- unname(group_code_map[group_calibration_label])

  base <- tibble(
    scope_id = scope_id, subject = subject_value,
    administered_grade_scope = grade_scope, model_scope = model_scope,
    sample_mode = sample_mode, anchor_mode = anchor_mode,
    calibration_student_n = nrow(response_calibration),
    calibration_group_n = length(group_levels),
    modeled_item_n = ncol(response_calibration), fixed_y1_anchor_n = nrow(anchors),
    excluded_small_group_n = sum(group_counts < 50),
    calibration_max_cycles = this_calibration_max_cycles,
    estimated_discrimination_upper_bound = estimated_discrimination_upper_bound
  )
  if (nrow(response_calibration) < 200 || ncol(response_calibration) < 5 || nrow(anchors) < 5 || length(group_levels) < 2) {
    model_rows[[scope_id]] <- base %>% mutate(
      converged = 0L, calibration_status = "not_estimated_insufficient_joint_design",
      log_likelihood = NA_real_, AIC = NA_real_, BIC = NA_real_, warning = "", error = ""
    )
    next
  }

  warning_messages <- character()
  fit <- tryCatch(
    list(model = withCallingHandlers(
      if (model_scope %in% c("subject_pooled_mixture", "grade_specific_mixture")) {
        fit_joint_pooled(response_calibration, anchors, this_calibration_max_cycles)
      } else {
        fit_joint(response_calibration, group_calibration, anchors, this_calibration_max_cycles)
      },
      warning = function(warning) {
        warning_messages <<- c(warning_messages, conditionMessage(warning)); invokeRestart("muffleWarning")
      }
    ), error = ""),
    error = function(error) list(model = NULL, error = conditionMessage(error))
  )
  if (is.null(fit$model)) {
    model_rows[[scope_id]] <- base %>% mutate(
      converged = 0L, calibration_status = "model_error",
      log_likelihood = NA_real_, AIC = NA_real_, BIC = NA_real_,
      warning = paste(unique(warning_messages), collapse = " | "), error = fit$error
    )
    next
  }

  model <- fit$model
  converged <- isTRUE(extract.mirt(model, "converged"))
  coefficients <- coef(model, IRTpars = TRUE, simplify = TRUE)
  items <- if (model_scope %in% c("subject_pooled_mixture", "grade_specific_mixture")) {
    as.data.frame(coefficients$items)
  } else {
    as.data.frame(coefficients[[names(coefficients)[[1]]]]$items)
  }
  items$item_code <- rownames(items)
  item_parameters <- as_tibble(items) %>%
    transmute(item_code, discrimination_a = a, difficulty_b = b) %>%
    inner_join(code_map, by = "item_code")
  parameter_rows[[scope_id]] <- item_parameters %>%
    mutate(
      scope_id = scope_id, subject = subject_value,
      administered_grade_scope = grade_scope, model_scope = model_scope,
      sample_mode = sample_mode, anchor_mode = anchor_mode,
      fixed_y1_anchor = as.integer(item_code %in% anchors$item_code),
      scale_status = "development_only_joint_y1_metric"
    ) %>%
    select(scope_id, subject, administered_grade_scope, model_scope, sample_mode,
           anchor_mode, item_code, analysis_key, discrimination_a, difficulty_b,
           fixed_y1_anchor, scale_status)

  if (model_scope %in% c("subject_pooled_mixture", "grade_specific_mixture")) {
    group_rows_output[[paste(scope_id, "POOLED", sep = "|")]] <- tibble(
      scope_id = scope_id, subject = subject_value,
      administered_grade_scope = grade_scope, model_scope = model_scope,
      sample_mode = sample_mode, anchor_mode = anchor_mode,
      group_code = "POOLED", group_label = "pooled_calibration_mixture",
      latent_mean = as.numeric(coefficients$means[1]),
      latent_variance = as.numeric(coefficients$cov[1, 1])
    )
  } else {
    for (group_code in names(coefficients)) {
      label <- names(group_code_map)[match(group_code, group_code_map)]
      group_rows_output[[paste(scope_id, group_code, sep = "|")]] <- tibble(
        scope_id = scope_id, subject = subject_value,
        administered_grade_scope = grade_scope, model_scope = model_scope,
        sample_mode = sample_mode, anchor_mode = anchor_mode,
        group_code = group_code, group_label = label,
        latent_mean = as.numeric(coefficients[[group_code]]$means[1]),
        latent_variance = as.numeric(coefficients[[group_code]]$cov[1, 1])
      )
    }
  }
  model_rows[[scope_id]] <- base %>% mutate(
    converged = as.integer(converged),
    calibration_status = case_when(
      !converged ~ "estimated_not_converged",
      length(warning_messages) > 0 ~ "estimated_with_warning",
      TRUE ~ "estimated_development_only"
    ),
    log_likelihood = as.numeric(extract.mirt(model, "logLik")),
    AIC = as.numeric(extract.mirt(model, "AIC")),
    BIC = as.numeric(extract.mirt(model, "BIC")),
    warning = paste(unique(warning_messages), collapse = " | "), error = ""
  )

  # Never emit abilities from a pooled item calibration that did not converge.
  if (!converged) {
    rm(model)
    invisible(gc())
    next
  }

  is_primary_run <- is_primary_specification
  if (is_primary_run) {
    item_fit_warnings <- character()
    item_fit <- tryCatch(
      as_tibble(withCallingHandlers(
        itemfit(model, fit_stats = "X2"),
        warning = function(warning) {
          item_fit_warnings <<- c(item_fit_warnings, conditionMessage(warning))
          invokeRestart("muffleWarning")
        }
      )) %>%
        transmute(
          item = item, fit_statistic = X2, fit_df = df.X2,
          fit_rmsea = RMSEA.X2, fit_p = p.X2
        ),
      error = function(error) tibble(
        item = NA_character_, fit_statistic = NA_real_, fit_df = NA_real_,
        fit_rmsea = NA_real_, fit_p = NA_real_,
        diagnostic_error = conditionMessage(error)
      )
    )
    if ("item" %in% names(item_fit)) {
      item_fit_rows[[scope_id]] <- item_fit %>%
        rename(item_code = item) %>%
        left_join(code_map, by = "item_code") %>%
        mutate(
          scope_id = scope_id, subject = subject_value,
          diagnostic_warning = paste(unique(item_fit_warnings), collapse = " | "),
          p_holm = p.adjust(.data$fit_p, method = "holm"),
          item_fit_warning = as.integer(
            (!is.na(.data$p_holm) & .data$p_holm < 0.05) |
              (!is.na(.data$fit_rmsea) & .data$fit_rmsea > 0.06)
          )
        )
    } else {
      item_fit_rows[[scope_id]] <- item_fit %>%
        mutate(scope_id = scope_id, subject = subject_value)
    }

  }

  target_nodes <- scope_nodes %>% filter(year %in% c(2L, 3L), wave %in% c("baseline", "endline"))
  for (target_index in seq_len(nrow(target_nodes))) {
    target <- target_nodes[target_index, ]
    node_id <- target$node_id[[1]]
    node_rows <- meta_all$node_id == node_id
    node_response_all <- response_all[node_rows, , drop = FALSE]
    node_meta <- meta_all[node_rows, , drop = FALSE]
    available <- colSums(!is.na(node_response_all)) > 0
    node_response_all <- node_response_all[, available, drop = FALSE]
    node_params <- item_parameters %>% filter(item_code %in% colnames(node_response_all))
    node_response_all <- node_response_all[, node_params$item_code, drop = FALSE]
    node_calibration_keep <- if (sample_mode == "all") {
      rep(TRUE, nrow(node_meta))
    } else if (sample_mode == "comparison_only") {
      !is.na(node_meta$treatment) & node_meta$treatment == 0
    } else {
      node_meta$school_split == "development"
    }
    node_response_calibration <- node_response_all[node_calibration_keep, , drop = FALSE]
    node_variable <- apply(node_response_calibration, 2, function(x) length(unique(x[!is.na(x)])) == 2)
    node_response_calibration <- node_response_calibration[, node_variable, drop = FALSE]
    node_response_all <- node_response_all[, colnames(node_response_calibration), drop = FALSE]
    node_params <- node_params %>% filter(item_code %in% colnames(node_response_calibration))
    if (nrow(node_response_calibration) < 100 || ncol(node_response_calibration) < 5) {
      node_score_rows[[node_id]] <- tibble(
        scope_id = scope_id, node_id = node_id, n_all = nrow(node_response_all),
        n_distribution_calibration = nrow(node_response_calibration), item_n = ncol(node_response_calibration),
        node_model_converged = 0L,
        score_status = "not_scored_insufficient_node_distribution_sample", warning = "", error = ""
      )
      next
    }
    node_warnings <- character()
    node_fit <- tryCatch(
      list(model = withCallingHandlers(
        fit_fixed_item_scoring_model(node_response_calibration, node_params),
        warning = function(warning) {
          node_warnings <<- c(node_warnings, conditionMessage(warning)); invokeRestart("muffleWarning")
        }
      ), error = ""),
      error = function(error) list(model = NULL, error = conditionMessage(error))
    )
    if (is.null(node_fit$model)) {
      node_score_rows[[node_id]] <- tibble(
        scope_id = scope_id, node_id = node_id, n_all = nrow(node_response_all),
        n_distribution_calibration = nrow(node_response_calibration), item_n = ncol(node_response_calibration),
        node_model_converged = 0L,
        score_status = "node_scoring_model_error", warning = paste(unique(node_warnings), collapse = " | "), error = node_fit$error
      )
      next
    }
    node_converged <- isTRUE(extract.mirt(node_fit$model, "converged"))
    if (!node_converged) {
      node_score_rows[[node_id]] <- tibble(
        scope_id = scope_id, node_id = node_id, n_all = nrow(node_response_all),
        n_distribution_calibration = nrow(node_response_calibration), item_n = ncol(node_response_calibration),
        node_model_converged = 0L,
        score_status = "node_scoring_not_converged",
        warning = paste(unique(node_warnings), collapse = " | "), error = ""
      )
      rm(node_fit)
      invisible(gc())
      next
    }
    if (is_primary_run) {
      node_global_fit <- tryCatch(
        as_tibble(suppressWarnings(M2(node_fit$model, type = "C2", na.rm = TRUE)),
                  rownames = "statistic_set") %>%
          mutate(diagnostic_status = "estimated", diagnostic_error = ""),
        error = function(error) tibble(
          statistic_set = "C2", diagnostic_status = "not_estimated",
          diagnostic_error = conditionMessage(error)
        )
      )
      global_fit_rows[[node_id]] <- node_global_fit %>%
        mutate(
          scope_id = scope_id, node_id = node_id, subject = subject_value,
          complete_case_n = sum(complete.cases(node_response_calibration)),
          calibration_row_n = nrow(node_response_calibration)
        )

      q3_warnings <- character()
      q3 <- tryCatch(
        withCallingHandlers(
          residuals(node_fit$model, type = "Q3", verbose = FALSE),
          warning = function(warning) {
            q3_warnings <<- c(q3_warnings, conditionMessage(warning))
            invokeRestart("muffleWarning")
          }
        ),
        error = function(error) structure(NULL, diagnostic_error = conditionMessage(error))
      )
      if (!is.null(q3)) {
        q3_index <- which(upper.tri(q3), arr.ind = TRUE)
        local_dependence_rows[[node_id]] <- tibble(
          left_item_code = rownames(q3)[q3_index[, 1]],
          right_item_code = colnames(q3)[q3_index[, 2]],
          q3 = q3[q3_index]
        ) %>%
          mutate(abs_q3 = abs(q3)) %>%
          arrange(desc(abs_q3)) %>%
          slice_head(n = 20L) %>%
          mutate(
            scope_id = scope_id, node_id = node_id, subject = subject_value,
            local_dependence_warning = as.integer(abs_q3 > 0.20),
            diagnostic_warning = paste(unique(q3_warnings), collapse = " | ")
          )
      } else {
        local_dependence_rows[[node_id]] <- tibble(
          left_item_code = NA_character_, right_item_code = NA_character_,
          q3 = NA_real_, abs_q3 = NA_real_, scope_id = scope_id,
          node_id = node_id, subject = subject_value,
          local_dependence_warning = NA_integer_,
          diagnostic_warning = paste(unique(q3_warnings), collapse = " | "),
          diagnostic_error = attr(q3, "diagnostic_error")
        )
      }
    }
    score <- withCallingHandlers(
      fscores(node_fit$model, response.pattern = node_response_all,
              method = "EAP", full.scores.SE = TRUE),
      warning = function(warning) {
        node_warnings <<- c(node_warnings, paste0("EAP scoring: ", conditionMessage(warning)))
        invokeRestart("muffleWarning")
      }
    )
    wle_score <- tryCatch(
      withCallingHandlers(
        fscores(node_fit$model, response.pattern = node_response_all,
                method = "WLE", full.scores.SE = TRUE),
        warning = function(warning) {
          node_warnings <<- c(node_warnings, paste0("WLE scoring: ", conditionMessage(warning)))
          invokeRestart("muffleWarning")
        }
      ),
      error = function(error) {
        node_warnings <<- c(node_warnings, paste0("WLE scoring failed: ", conditionMessage(error)))
        matrix(NA_real_, nrow = nrow(node_response_all), ncol = 2L,
               dimnames = list(NULL, c("F1", "SE_F1")))
      }
    )
    reference <- occurrences %>% filter(node_id == .env$node_id) %>% slice(1)
    ref_mean <- reference$y1_reference_mean[[1]]; ref_sd <- reference$y1_reference_sd[[1]]
    validation_split_value <- if (identical(sample_mode, "development_schools")) {
      node_meta$school_split
    } else {
      rep("not_applicable", nrow(node_meta))
    }
    outcome_rows[[paste(scope_id, node_id, sep = "|")]] <- tibble(
      id_student_panel = node_meta$source_id,
      year = as.integer(target$year[[1]]),
      wave = node_meta$wave,
      cohort = node_meta$cohort,
      subject = node_meta$subject,
      administered_grade = node_meta$administered_grade,
      model_id = paste("joint", model_scope, sample_mode, anchor_mode, scope_id, sep = "|"),
      anchor_mode = anchor_mode, sample_mode = sample_mode, model_scope = model_scope,
      validation_split = validation_split_value,
      theta_y1_metric = as.numeric(score[, "F1"]),
      se_theta_y1_metric = as.numeric(score[, "SE_F1"]),
      theta_y1_published_z = (theta_y1_metric - ref_mean) / ref_sd,
      se_theta_y1_published_z = se_theta_y1_metric / ref_sd,
      theta_y1_metric_wle = as.numeric(wle_score[, "F1"]),
      se_theta_y1_metric_wle = as.numeric(wle_score[, "SE_F1"]),
      theta_y1_published_z_wle = (theta_y1_metric_wle - ref_mean) / ref_sd,
      se_theta_y1_published_z_wle = se_theta_y1_metric_wle / ref_sd,
      scale_status = "development_only_joint_y1_metric",
      final_outcome_approved = 0L
    )
    node_score_rows[[paste(scope_id, node_id, sep = "|")]] <- tibble(
      scope_id = scope_id, node_id = node_id, n_all = nrow(node_response_all),
      n_distribution_calibration = nrow(node_response_calibration), item_n = ncol(node_response_calibration),
      node_model_converged = 1L,
      score_status = if (length(node_warnings)) "scored_with_warning" else "scored_development_only",
      wle_scored_n = sum(is.finite(wle_score[, "F1"])),
      wle_missing_n = sum(!is.finite(wle_score[, "F1"])),
      warning = paste(unique(node_warnings), collapse = " | "), error = ""
    )
    rm(node_fit)
    invisible(gc())
  }
  rm(model, assembled, response_all, response_calibration)
  invisible(gc())
}

models <- bind_rows(model_rows); parameters <- bind_rows(parameter_rows)
groups <- bind_rows(group_rows_output)
outcomes <- bind_rows(
  tibble(
    id_student_panel = character(), year = integer(), wave = character(), cohort = character(),
    subject = character(), administered_grade = character(), model_id = character(),
    anchor_mode = character(), sample_mode = character(), model_scope = character(),
    validation_split = character(), theta_y1_metric = double(),
    se_theta_y1_metric = double(), theta_y1_published_z = double(),
    se_theta_y1_published_z = double(), theta_y1_metric_wle = double(),
    se_theta_y1_metric_wle = double(), theta_y1_published_z_wle = double(),
    se_theta_y1_published_z_wle = double(), scale_status = character(),
    final_outcome_approved = integer()
  ),
  bind_rows(outcome_rows)
)
node_scores <- bind_rows(
  tibble(
    scope_id = character(), node_id = character(), n_all = integer(),
    n_distribution_calibration = integer(), item_n = integer(),
    node_model_converged = integer(), score_status = character(),
    wle_scored_n = integer(), wle_missing_n = integer(),
    warning = character(), error = character()
  ),
  bind_rows(node_score_rows)
)
run_id <- paste(model_scope, sample_mode, anchor_mode, sep = "_")
out_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/04_joint_multigroup", run_id))
derived_dir <- assert_output(file.path(work_root, "derived/y1_y3_irt"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE); dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(models, file.path(out_dir, "joint_model_summary.csv"), na = "")
write_csv(parameters, file.path(out_dir, "joint_item_parameters.csv"), na = "")
write_csv(groups, file.path(out_dir, "joint_group_distributions.csv"), na = "")
write_csv(node_scores, file.path(out_dir, "joint_node_scoring_summary.csv"), na = "")
write_csv(bind_rows(duplicate_rows), file.path(out_dir, "joint_duplicate_resolution_audit.csv"), na = "")
if (identical(anchor_mode, "purified_andy_core_math_bridge5") &&
    identical(sample_mode, "all") && identical(model_scope, "subject_pooled_mixture")) {
  item_fit_output <- bind_rows(item_fit_rows)
  global_fit_output <- bind_rows(global_fit_rows)
  local_dependence_output <- bind_rows(local_dependence_rows)
  write_csv(item_fit_output, file.path(out_dir, "primary_item_fit_diagnostics.csv"), na = "")
  write_csv(global_fit_output, file.path(out_dir, "primary_global_fit_diagnostics.csv"), na = "")
  write_csv(local_dependence_output, file.path(out_dir, "primary_local_dependence_top_pairs.csv"), na = "")
  diagnostic_summary <- tibble(subject = c("Arabic", "French", "Maths")) %>%
    left_join(
      item_fit_output %>%
        group_by(subject) %>%
        summarise(
          item_fit_tested_n = n_distinct(item_code[!is.na(item_code)]),
          item_fit_warning_n = sum(item_fit_warning == 1L, na.rm = TRUE),
          .groups = "drop"
        ),
      by = "subject"
    ) %>%
    left_join(
      local_dependence_output %>% group_by(subject) %>%
        summarise(
          max_abs_q3 = if (all(is.na(abs_q3))) NA_real_ else max(abs_q3, na.rm = TRUE),
          q3_over_020_n = sum(abs_q3 > 0.20, na.rm = TRUE),
          .groups = "drop"
        ),
      by = "subject"
    )
  if (all(c("subject", "p", "RMSEA", "SRMSR", "diagnostic_status") %in% names(global_fit_output))) {
    diagnostic_summary <- diagnostic_summary %>%
      left_join(global_fit_output %>%
                  group_by(subject) %>%
                  summarise(
                    global_fit_node_n = sum(diagnostic_status == "estimated"),
                    global_fit_p = if (all(is.na(p))) NA_real_ else min(p, na.rm = TRUE),
                    global_fit_rmsea = if (all(is.na(RMSEA))) NA_real_ else max(RMSEA, na.rm = TRUE),
                    global_fit_srmsr = if (all(is.na(SRMSR))) NA_real_ else max(SRMSR, na.rm = TRUE),
                    .groups = "drop"
                  ),
                by = "subject")
  } else {
    diagnostic_summary <- diagnostic_summary %>%
      mutate(global_fit_node_n = 0L, global_fit_p = NA_real_,
             global_fit_rmsea = NA_real_, global_fit_srmsr = NA_real_)
  }
  write_csv(diagnostic_summary, file.path(out_dir, "primary_diagnostic_summary.csv"), na = "")
}
outcome_csv <- assert_output(file.path(derived_dir, paste0("multiyear_irt_outcomes_joint_", run_id, ".csv")))
outcome_dta <- assert_output(file.path(derived_dir, paste0("multiyear_irt_outcomes_joint_", run_id, ".dta")))
y3_outcome_csv <- assert_output(file.path(derived_dir, paste0("y3_irt_outcomes_joint_", run_id, ".csv")))
y3_outcome_dta <- assert_output(file.path(derived_dir, paste0("y3_irt_outcomes_joint_", run_id, ".dta")))
write_csv(outcomes, outcome_csv, na = ""); write_dta(outcomes, outcome_dta, version = 15)
write_csv(filter(outcomes, year == 3L), y3_outcome_csv, na = "")
write_dta(filter(outcomes, year == 3L), y3_outcome_dta, version = 15)

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  model_scope = model_scope, sample_mode = sample_mode, anchor_mode = anchor_mode,
  subject_or_grade_model_n = nrow(models),
  converged_model_n = sum(models$converged == 1),
  warning_model_n = sum(models$calibration_status == "estimated_with_warning"),
  node_scored_n = sum(str_starts(node_scores$score_status, "scored_")),
  node_scoring_warning_n = sum(node_scores$score_status == "scored_with_warning"),
  outcome_row_n = nrow(outcomes),
  y2_outcome_row_n = sum(outcomes$year == 2L),
  y3_outcome_row_n = sum(outcomes$year == 3L),
  treatment_use = if (sample_mode == "comparison_only") "used only to restrict calibration and node-prior samples; all Year 2 and Year 3 students were scored" else "not used",
  school_split_use = if (sample_mode == "development_schools") "deterministic school-level development split used for calibration and node priors; all eligible students were scored" else "not used",
  construct_scope = "Separate subject models; no cross-subject latent scale was fit.",
  status = "development_only_not_approved"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "joint_run_summary.json"))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
