#!/usr/bin/env Rscript

# Treatment-blind Year 2--Year 3 anchor purification.
#
# This script mirrors the structure of the published Year 1 workflow without
# altering Year 1 scores or item parameters. It screens exact-summary common
# binary items for grade DIF, wave/year drift, pilot-to-main drift, and cohort
# DIF. The primary comparison-only pass may define a development sensitivity
# constraint map. An all-student pass is diagnostic only and cannot select
# anchors. All outputs are aggregate and are written below the configured
# work_root; no source data are modified.

suppressPackageStartupMessages({
  library(dplyr)
  library(haven)
  library(jsonlite)
  library(lmtest)
  library(purrr)
  library(readr)
  library(sandwich)
  library(stringr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1 || length(args) > 3) {
  stop(paste(
    "Usage: run_multiyear_anchor_purification.R config/paths.local.yml",
    "[comparison_only|all_students_blinded] [standard|math_bridge5]"
  ))
}
config_path <- normalizePath(args[[1]], mustWork = TRUE)
screen_sample <- if (length(args) >= 2) args[[2]] else "comparison_only"
if (!screen_sample %in% c("comparison_only", "all_students_blinded")) {
  stop("Unknown screening sample: ", screen_sample)
}
rule_profile <- if (length(args) >= 3) args[[3]] else "standard"
if (!rule_profile %in% c("standard", "math_bridge5")) {
  stop("Unknown anchor-screening rule profile: ", rule_profile)
}

local_config <- yaml::read_yaml(config_path)
analysis_config <- yaml::read_yaml(file.path(dirname(config_path), "analysis.yml"))
paths <- local_config$dropbox
thresholds <- analysis_config$anchor_purification
bridge_rule <- thresholds$required_link_bridge_sensitivity
set.seed(analysis_config$seed)

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
  if (!any(map_lgl(source_roots, ~ is_within(candidate, .x)))) {
    stop("Input outside approved source roots: ", candidate)
  }
  candidate
}
assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) {
    stop("Output must be below work_root: ", candidate)
  }
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) {
    stop("Output inside a read-only legacy root: ", candidate)
  }
  candidate
}

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
link_items <- read_csv(file.path(graph_dir, "multiyear_link_item_manifest.csv"), show_col_types = FALSE)
node_edges <- read_csv(file.path(graph_dir, "multiyear_node_edges.csv"), show_col_types = FALSE)

node_metadata <- occurrences %>%
  distinct(node_id, year, wave, subject, administered_grade)

edge_metadata <- node_edges %>%
  filter(strict_summary_anchor_n >= thresholds$minimum_common_items) %>%
  left_join(
    node_metadata %>% rename_with(~ paste0(.x, "_a"), -node_id) %>% rename(node_a = node_id),
    by = "node_a"
  ) %>%
  left_join(
    node_metadata %>% rename_with(~ paste0(.x, "_b"), -node_id) %>% rename(node_b = node_id),
    by = "node_b"
  ) %>%
  mutate(
    grade_num_a = suppressWarnings(as.integer(administered_grade_a)),
    grade_num_b = suppressWarnings(as.integer(administered_grade_b)),
    link_type = case_when(
      year_a == year_b & administered_grade_a == administered_grade_b &
        ((wave_a == "baseline" & wave_b == "endline") | (wave_a == "endline" & wave_b == "baseline")) ~
        "within_year_wave_drift",
      year_a == year_b & wave_a == wave_b & abs(grade_num_a - grade_num_b) == 1 ~
        "within_year_adjacent_grade_dif",
      year_a == year_b & administered_grade_a == administered_grade_b &
        (wave_a == "pilot" | wave_b == "pilot") ~
        "pilot_to_main_drift",
      year_a != year_b & wave_a == wave_b & administered_grade_a == administered_grade_b ~
        "across_year_same_grade_drift",
      year_a < year_b & wave_a == wave_b & grade_num_b == grade_num_a + 1 ~
        "across_year_grade_transition_drift",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(link_type), subject_a == subject_b) %>%
  transmute(
    link_type, link_id = paste(link_type, node_a, node_b, sep = "|"),
    subject = subject_a, node_a, node_b,
    year_a, wave_a, grade_a = administered_grade_a,
    year_b, wave_b, grade_b = administered_grade_b,
    candidate_item_n = strict_summary_anchor_n,
    cohort_a = NA_character_, cohort_b = NA_character_
  )

label_character <- function(x) as.character(haven::as_factor(x))
cohort_values <- function(data, year, wave) {
  if (year == 2L && wave == "baseline") return(rep("2", nrow(data)))
  if (year == 2L && wave == "endline" && all(c("cohort1", "cohort2") %in% names(data))) {
    return(ifelse(as.numeric(data$cohort1) == 1, "1", ifelse(as.numeric(data$cohort2) == 1, "2", "unknown")))
  }
  if ("cohort" %in% names(data)) return(label_character(data$cohort))
  rep("pilot_or_unspecified", nrow(data))
}

data_cache <- list()
node_cache <- list()
nonbinary_rows <- list()

get_source_data <- function(year, wave) {
  key <- paste0("Y", year, "|", wave)
  if (is.null(data_cache[[key]])) {
    spec <- source_specs %>% filter(source_key == key)
    message("Reading source ", key)
    data_cache[[key]] <<- read_dta(spec$path[[1]])
  }
  data_cache[[key]]
}

prepare_node <- function(node_id) {
  if (!is.null(node_cache[[node_id]])) return(node_cache[[node_id]])
  node <- node_metadata %>% filter(.data$node_id == .env$node_id)
  if (nrow(node) != 1) stop("Could not resolve node: ", node_id)
  year_value <- node$year[[1]]
  wave_value <- node$wave[[1]]
  subject_value <- node$subject[[1]]
  grade_value <- node$administered_grade[[1]]
  spec <- source_specs %>% filter(year == year_value, wave == wave_value)
  raw <- get_source_data(year_value, wave_value)
  keep <- label_character(raw$subject) == subject_value & label_character(raw$grade) == grade_value
  form <- raw[keep, , drop = FALSE] %>% mutate(.source_row = row_number())
  node_items <- occurrences %>% filter(.data$node_id == .env$node_id) %>% pull(item_id)
  item_vars <- intersect(node_items, names(form))
  if (!nrow(form) || !length(item_vars)) {
    result <- list(meta = tibble(), response = matrix(numeric(), 0, 0))
    node_cache[[node_id]] <<- result
    return(result)
  }

  answered <- rowSums(sapply(form[item_vars], function(x) {
    tag <- haven::na_tag(x)
    !is.na(x) | (!is.na(tag) & tag == "a")
  }))
  duration_value <- if ("duration" %in% names(form)) suppressWarnings(as.numeric(form$duration)) else rep(0, nrow(form))
  id_key <- as.character(form[[spec$id_column[[1]]]])
  missing_id <- is.na(id_key) | id_key == ""
  id_key[missing_id] <- paste0("__missing_row_", form$.source_row[missing_id])
  form <- form %>%
    mutate(.id_key = id_key, .answered = answered, .duration_value = duration_value) %>%
    arrange(.id_key, desc(.answered), desc(.duration_value), .source_row) %>%
    distinct(.id_key, .keep_all = TRUE) %>%
    arrange(.source_row)

  treatment <- rep(NA_real_, nrow(form))
  if (spec$treatment_column[[1]] != "" && spec$treatment_column[[1]] %in% names(form)) {
    treatment <- suppressWarnings(as.numeric(form[[spec$treatment_column[[1]]]]))
  }
  if (screen_sample == "comparison_only" && spec$treatment_column[[1]] != "") {
    sample_keep <- !is.na(treatment) & treatment == 0
  } else {
    sample_keep <- rep(TRUE, nrow(form))
  }
  form <- form[sample_keep, , drop = FALSE]
  treatment <- treatment[sample_keep]

  school_column <- intersect(c("school_id", "school", "school_cohort"), names(form))
  school_value <- if (length(school_column)) as.character(form[[school_column[[1]]]]) else rep(NA_character_, nrow(form))
  missing_school <- is.na(school_value) | school_value == ""
  school_value[missing_school] <- paste0(node_id, "|row|", form$.source_row[missing_school])

  response_list <- list()
  for (item in item_vars) {
    value <- suppressWarnings(as.numeric(form[[item]]))
    observed <- value[!is.na(value)]
    unexpected <- sort(unique(observed[!observed %in% c(0, 1)]))
    if (length(unexpected)) {
      nonbinary_rows[[paste(node_id, item, sep = "|")]] <<- tibble(
        node_id = node_id, subject = subject_value, item_id = item,
        nonbinary_observed_value_n = length(unexpected),
        exclusion_reason = "observed response outside zero/one"
      )
      next
    }
    scored <- rep(NA_real_, length(value))
    scored[!is.na(value)] <- as.numeric(value[!is.na(value)] == 1)
    tag <- haven::na_tag(form[[item]])
    scored[!is.na(tag) & tag == "a"] <- 0
    response_list[[item]] <- scored
  }
  response <- if (length(response_list)) {
    result <- do.call(cbind, response_list)
    if (is.null(dim(result))) matrix(result, ncol = 1, dimnames = list(NULL, names(response_list))) else result
  } else {
    matrix(numeric(), nrow(form), 0)
  }
  colnames(response) <- names(response_list)
  result <- list(
    meta = tibble(
      cohort = cohort_values(form, year_value, wave_value),
      cluster = school_value,
      treatment_observed = !is.na(treatment)
    ),
    response = response
  )
  node_cache[[node_id]] <<- result
  result
}

empty_fit <- function(warning) {
  tibble(
    n_total = NA_integer_, n_a = NA_integer_, n_b = NA_integer_, cluster_n = NA_integer_,
    p_correct_a = NA_real_, p_correct_b = NA_real_, unconditional_p_difference = NA_real_,
    beta_uniform = NA_real_, uniform_or = NA_real_, uniform_se_cluster = NA_real_, uniform_p_cluster = NA_real_,
    beta_nonuniform = NA_real_, nonuniform_or = NA_real_, nonuniform_se_cluster = NA_real_, nonuniform_p_cluster = NA_real_,
    joint_wald_chisq = NA_real_, joint_p_cluster = NA_real_, incremental_pseudo_r2 = NA_real_,
    mh_common_or = NA_real_, mh_delta = NA_real_, mh_p = NA_real_, mh_stratum_n = NA_integer_,
    inference_reliable = 0L, model_warning = warning
  )
}

mantel_haenszel <- function(y, rest, group) {
  breaks <- unique(quantile(rest, probs = seq(0, 1, 0.1), na.rm = TRUE, type = 2))
  if (length(breaks) < 3) return(list(or = NA_real_, delta = NA_real_, p = NA_real_, strata = 0L))
  strata <- cut(rest, breaks = breaks, include.lowest = TRUE, ordered_result = TRUE)
  frame <- tibble(
    y = factor(y, levels = c(0, 1)),
    group = factor(group, levels = c("A", "B")),
    stratum = strata
  ) %>% filter(!is.na(stratum))
  counts <- frame %>% count(stratum, y, group, .drop = FALSE)
  informative <- counts %>%
    group_by(stratum) %>%
    summarize(
      both_groups = n_distinct(group[n > 0]) == 2,
      both_responses = n_distinct(y[n > 0]) == 2,
      .groups = "drop"
    ) %>% filter(both_groups, both_responses) %>% pull(stratum)
  frame <- frame %>% filter(stratum %in% informative) %>% droplevels()
  if (n_distinct(frame$stratum) < 2) return(list(or = NA_real_, delta = NA_real_, p = NA_real_, strata = n_distinct(frame$stratum)))
  array <- xtabs(~ y + group + stratum, data = frame, drop.unused.levels = TRUE)
  test <- tryCatch(suppressWarnings(mantelhaen.test(array, correct = FALSE)), error = function(e) NULL)
  if (is.null(test)) return(list(or = NA_real_, delta = NA_real_, p = NA_real_, strata = dim(array)[3]))
  odds_ratio <- unname(as.numeric(test$estimate))
  list(
    or = odds_ratio,
    delta = if (is.finite(odds_ratio) && odds_ratio > 0) -2.35 * log(odds_ratio) else NA_real_,
    p = as.numeric(test$p.value),
    strata = dim(array)[3]
  )
}

fit_item_dif <- function(y, rest_matrix, group, cluster) {
  if (!ncol(rest_matrix)) return(empty_fit("no conditioning items"))
  rest_answered <- rowSums(!is.na(rest_matrix))
  rest <- rowMeans(rest_matrix, na.rm = TRUE)
  rest[rest_answered < thresholds$minimum_rest_items_answered] <- NA_real_
  keep <- !is.na(y) & is.finite(rest) & !is.na(group) & !is.na(cluster)
  frame <- tibble(y = y[keep], rest = rest[keep], group = group[keep], cluster = cluster[keep])
  if (!nrow(frame)) return(empty_fit("no analyzable records"))
  group_n <- table(factor(frame$group, levels = c("A", "B")))
  base_values <- list(
    n_total = nrow(frame), n_a = unname(group_n[["A"]]), n_b = unname(group_n[["B"]]),
    cluster_n = n_distinct(frame$cluster),
    p_correct_a = mean(frame$y[frame$group == "A"]),
    p_correct_b = mean(frame$y[frame$group == "B"])
  )
  if (any(group_n < thresholds$minimum_group_n) || length(unique(frame$y)) < 2 ||
      sd(frame$rest) == 0 || !is.finite(sd(frame$rest))) {
    result <- empty_fit("insufficient group size, response variation, or rest-score variation")
    result[1, names(base_values)] <- base_values
    result$unconditional_p_difference <- base_values$p_correct_b - base_values$p_correct_a
    return(result)
  }
  frame <- frame %>% mutate(rest_z = as.numeric(scale(rest)), group = factor(group, levels = c("A", "B")))
  base <- tryCatch(glm(y ~ rest_z, data = frame, family = binomial()), error = function(e) NULL)
  full <- tryCatch(suppressWarnings(glm(y ~ rest_z * group, data = frame, family = binomial())), error = function(e) NULL)
  if (is.null(base) || is.null(full)) {
    result <- empty_fit("logistic model failed")
    result[1, names(base_values)] <- base_values
    result$unconditional_p_difference <- base_values$p_correct_b - base_values$p_correct_a
    return(result)
  }
  cluster_vcov <- tryCatch(vcovCL(full, cluster = frame$cluster, type = "HC1"), error = function(e) NULL)
  robust <- if (!is.null(cluster_vcov)) tryCatch(suppressWarnings(coeftest(full, vcov. = cluster_vcov)), error = function(e) NULL) else NULL
  coefficient_value <- function(name, column) {
    if (is.null(robust) || !name %in% rownames(robust)) return(NA_real_)
    as.numeric(robust[name, column])
  }
  beta_u <- coefficient_value("groupB", 1)
  beta_n <- coefficient_value("rest_z:groupB", 1)
  tested_names <- c("groupB", "rest_z:groupB")
  joint <- c(chisq = NA_real_, p = NA_real_)
  if (!is.null(cluster_vcov) && all(tested_names %in% names(coef(full)))) {
    b <- coef(full)[tested_names]
    v <- cluster_vcov[tested_names, tested_names, drop = FALSE]
    statistic <- tryCatch(as.numeric(t(b) %*% solve(v, b)), error = function(e) NA_real_)
    if (is.finite(statistic)) joint <- c(chisq = statistic, p = pchisq(statistic, df = 2, lower.tail = FALSE))
  }
  mh <- mantel_haenszel(frame$y, frame$rest, frame$group)
  warning <- character()
  if (n_distinct(frame$cluster) < thresholds$minimum_cluster_n_for_automatic_flag) warning <- c(warning, "fewer than minimum clusters")
  if (!isTRUE(full$converged)) warning <- c(warning, "logistic model did not converge")
  if (any(abs(coef(full)) > 10, na.rm = TRUE)) warning <- c(warning, "possible separation")
  if (is.null(robust)) warning <- c(warning, "cluster-robust covariance unavailable")
  tibble(
    n_total = nrow(frame), n_a = unname(group_n[["A"]]), n_b = unname(group_n[["B"]]),
    cluster_n = n_distinct(frame$cluster),
    p_correct_a = base_values$p_correct_a, p_correct_b = base_values$p_correct_b,
    unconditional_p_difference = base_values$p_correct_b - base_values$p_correct_a,
    beta_uniform = beta_u, uniform_or = exp(beta_u),
    uniform_se_cluster = coefficient_value("groupB", 2), uniform_p_cluster = coefficient_value("groupB", 4),
    beta_nonuniform = beta_n, nonuniform_or = exp(beta_n),
    nonuniform_se_cluster = coefficient_value("rest_z:groupB", 2), nonuniform_p_cluster = coefficient_value("rest_z:groupB", 4),
    joint_wald_chisq = unname(joint[["chisq"]]), joint_p_cluster = unname(joint[["p"]]),
    incremental_pseudo_r2 = as.numeric((logLik(full) - logLik(base)) / abs(logLik(base))),
    mh_common_or = mh$or, mh_delta = mh$delta, mh_p = mh$p, mh_stratum_n = mh$strata,
    inference_reliable = as.integer(
      n_distinct(frame$cluster) >= thresholds$minimum_cluster_n_for_automatic_flag &&
        isTRUE(full$converged) && !is.null(robust) && !any(abs(coef(full)) > 10, na.rm = TRUE)
    ),
    model_warning = paste(unique(warning), collapse = " | ")
  )
}

link_candidate_items <- function(node_a, node_b) {
  if (node_a == node_b) {
    return(occurrences %>% filter(.data$node_id == .env$node_a) %>%
      select(subject, item_id, strict_item_version_id))
  }
  left <- min(node_a, node_b)
  right <- max(node_a, node_b)
  link_items %>%
    filter(node_a == left, node_b == right, strict_summary_link == 1) %>%
    select(subject, item_id, strict_item_version_id)
}

analyze_link <- function(link, iteration, active_items) {
  left <- prepare_node(link$node_a[[1]])
  right <- prepare_node(link$node_b[[1]])
  items <- link_candidate_items(link$node_a[[1]], link$node_b[[1]])
  common <- intersect(intersect(items$item_id, colnames(left$response)), colnames(right$response))
  if (!is.na(link$cohort_a[[1]])) {
    keep_left <- left$meta$cohort == link$cohort_a[[1]]
    keep_right <- right$meta$cohort == link$cohort_b[[1]]
  } else {
    keep_left <- rep(TRUE, nrow(left$meta))
    keep_right <- rep(TRUE, nrow(right$meta))
  }
  left_response <- left$response[keep_left, common, drop = FALSE]
  right_response <- right$response[keep_right, common, drop = FALSE]
  response <- rbind(left_response, right_response)
  group <- c(rep("A", nrow(left_response)), rep("B", nrow(right_response)))
  cluster <- c(left$meta$cluster[keep_left], right$meta$cluster[keep_right])
  conditioning <- intersect(active_items, common)
  map_dfr(common, function(item) {
    rest_items <- setdiff(conditioning, item)
    fit <- fit_item_dif(
      response[, item], response[, rest_items, drop = FALSE], group, cluster
    )
    bind_cols(
      link %>% select(link_type, link_id, subject, node_a, node_b, year_a, wave_a, grade_a, year_b, wave_b, grade_b, cohort_a, cohort_b),
      items %>% filter(.data$item_id == .env$item) %>% select(-subject) %>% slice(1),
      tibble(
        screen_sample = screen_sample, iteration = iteration,
        conditioning_item_n = length(rest_items), candidate_active = as.integer(item %in% conditioning)
      ),
      fit
    )
  })
}

# Prepare every planned node once so cohort contrasts can be declared without
# exporting cohort- or student-level records.
planned_nodes <- sort(unique(c(edge_metadata$node_a, edge_metadata$node_b)))
walk(planned_nodes, prepare_node)

cohort_links <- list()
for (node_id in planned_nodes) {
  node <- node_metadata %>% filter(.data$node_id == .env$node_id)
  prepared <- prepare_node(node_id)
  cohorts <- sort(unique(prepared$meta$cohort[!is.na(prepared$meta$cohort) & prepared$meta$cohort != "unknown"]))
  if (length(cohorts) < 2) next
  pairs <- combn(cohorts, 2, simplify = FALSE)
  for (pair in pairs) {
    counts <- table(factor(prepared$meta$cohort, levels = pair))
    if (any(counts < thresholds$minimum_group_n)) next
    key <- paste("within_node_cohort_dif", node_id, pair[[1]], pair[[2]], sep = "|")
    cohort_links[[key]] <- tibble(
      link_type = "within_node_cohort_dif", link_id = key, subject = node$subject,
      node_a = node_id, node_b = node_id,
      year_a = node$year, wave_a = node$wave, grade_a = node$administered_grade,
      year_b = node$year, wave_b = node$wave, grade_b = node$administered_grade,
      candidate_item_n = ncol(prepared$response), cohort_a = pair[[1]], cohort_b = pair[[2]]
    )
  }
}
planned_links <- bind_rows(edge_metadata, bind_rows(cohort_links)) %>% arrange(subject, link_type, link_id)

evidence_rows <- list()
decision_rows <- list()
iteration_rows <- list()
for (link_index in seq_len(nrow(planned_links))) {
  link <- planned_links[link_index, ]
  candidates <- link_candidate_items(link$node_a[[1]], link$node_b[[1]])$item_id
  candidates <- intersect(candidates, intersect(colnames(prepare_node(link$node_a[[1]])$response), colnames(prepare_node(link$node_b[[1]])$response)))
  active <- candidates
  freed <- character()
  bridge_floor_retained <- character()
  last_rows <- tibble()
  message(sprintf("[%d/%d] %s (%d binary candidates)", link_index, nrow(planned_links), link$link_id[[1]], length(candidates)))
  for (iteration in seq_len(thresholds$maximum_iterations)) {
    if (length(active) < thresholds$minimum_common_items) break
    rows <- analyze_link(link, iteration, active) %>%
      group_by(link_id, iteration) %>%
      mutate(
        uniform_p_holm = if_else(!is.na(uniform_p_cluster), p.adjust(uniform_p_cluster, method = thresholds$multiplicity_method), NA_real_),
        nonuniform_p_holm = if_else(!is.na(nonuniform_p_cluster), p.adjust(nonuniform_p_cluster, method = thresholds$multiplicity_method), NA_real_),
        joint_p_holm = if_else(!is.na(joint_p_cluster), p.adjust(joint_p_cluster, method = thresholds$multiplicity_method), NA_real_),
        mh_p_holm = if_else(!is.na(mh_p), p.adjust(mh_p, method = thresholds$multiplicity_method), NA_real_)
      ) %>% ungroup() %>%
      mutate(
        uniform_material = as.integer(!is.na(uniform_or) & (uniform_or < thresholds$uniform_odds_ratio_lower | uniform_or > thresholds$uniform_odds_ratio_upper)),
        nonuniform_material = as.integer(!is.na(beta_nonuniform) & abs(beta_nonuniform) > thresholds$nonuniform_logit_coefficient_abs),
        r2_material = as.integer(!is.na(incremental_pseudo_r2) & incremental_pseudo_r2 > thresholds$incremental_pseudo_r2),
        mh_material = as.integer(!is.na(mh_delta) & abs(mh_delta) > thresholds$mantel_haenszel_delta_abs),
        material_signal = as.integer(uniform_material == 1 | nonuniform_material == 1 | r2_material == 1 | mh_material == 1),
        joint_statistical_signal = as.integer(!is.na(joint_p_holm) & joint_p_holm < thresholds$alpha),
        mh_statistical_signal = as.integer(!is.na(mh_p_holm) & mh_p_holm < thresholds$alpha),
        statistical_signal = as.integer(joint_statistical_signal == 1 | mh_statistical_signal == 1),
        consensus_signal = as.integer(joint_statistical_signal == 1 & mh_statistical_signal == 1),
        material_severity = pmax(
          if_else(!is.na(uniform_or) & uniform_or > 0,
                  abs(log(uniform_or)) / abs(log(thresholds$uniform_odds_ratio_upper)), NA_real_),
          if_else(!is.na(beta_nonuniform),
                  abs(beta_nonuniform) / thresholds$nonuniform_logit_coefficient_abs, NA_real_),
          if_else(!is.na(incremental_pseudo_r2),
                  incremental_pseudo_r2 / thresholds$incremental_pseudo_r2, NA_real_),
          if_else(!is.na(mh_delta),
                  abs(mh_delta) / thresholds$mantel_haenszel_delta_abs, NA_real_),
          na.rm = TRUE
        ),
        material_severity = if_else(is.finite(material_severity), material_severity, NA_real_),
        automatic_free_eligible = as.integer(
          candidate_active == 1 & inference_reliable == 1 & material_signal == 1 &
            (if (rule_profile == "math_bridge5") consensus_signal == 1 else statistical_signal == 1) &
            screen_sample == "comparison_only"
        ),
        rule_profile = rule_profile,
        bridge_free_rank = NA_integer_,
        bridge_floor_retained_iteration = 0L,
        new_free_flag = automatic_free_eligible
      )
    if (rule_profile == "math_bridge5" && screen_sample == "comparison_only") {
      eligible <- rows %>%
        filter(automatic_free_eligible == 1, !item_id %in% freed) %>%
        mutate(
          weakest_adjusted_p = pmax(joint_p_holm, mh_p_holm),
          material_severity_order = coalesce(material_severity, 0)
        ) %>%
        arrange(weakest_adjusted_p, desc(material_severity_order), item_id)
      remaining_slots <- max(
        0L,
        length(candidates) - bridge_rule$minimum_retained_anchors_per_link - length(freed)
      )
      selected_ids <- head(eligible$item_id, remaining_slots)
      ranked_ids <- eligible$item_id
      retained_ids <- setdiff(ranked_ids, selected_ids)
      bridge_floor_retained <- unique(c(bridge_floor_retained, retained_ids))
      rows <- rows %>% mutate(
        bridge_free_rank = match(item_id, ranked_ids),
        bridge_floor_retained_iteration = as.integer(item_id %in% retained_ids),
        new_free_flag = as.integer(automatic_free_eligible == 1 & item_id %in% selected_ids)
      )
    }
    evidence_rows[[paste(link$link_id[[1]], iteration, sep = "|")]] <- rows
    last_rows <- rows
    newly_freed <- rows %>% filter(new_free_flag == 1, !item_id %in% freed) %>% pull(item_id)
    iteration_rows[[paste(link$link_id[[1]], iteration, sep = "|")]] <- tibble(
      screen_sample = screen_sample, rule_profile = rule_profile,
      link_type = link$link_type, link_id = link$link_id,
      iteration = iteration, conditioning_item_n = length(active), newly_freed_n = length(newly_freed),
      cumulative_freed_n = length(unique(c(freed, newly_freed))),
      bridge_floor_retained_n = if_else(
        rule_profile == "math_bridge5",
        length(unique(bridge_floor_retained)),
        0L
      )
    )
    freed <- unique(c(freed, newly_freed))
    if (!length(newly_freed)) break
    active <- setdiff(active, newly_freed)
  }
  if (!length(candidates)) next
  candidate_table <- link_candidate_items(link$node_a[[1]], link$node_b[[1]]) %>% filter(item_id %in% candidates)
  if (!nrow(last_rows)) {
    last_rows <- candidate_table %>% transmute(
      item_id,
      inference_reliable = 0L,
      material_signal = NA_integer_,
      statistical_signal = NA_integer_,
      model_warning = "fewer than minimum binary conditioning items"
    )
  }
  final <- candidate_table %>%
    left_join(last_rows %>% select(item_id, inference_reliable, material_signal, statistical_signal, model_warning), by = "item_id") %>%
    mutate(
      screen_sample = screen_sample, link_type = link$link_type, link_id = link$link_id,
      node_a = link$node_a, node_b = link$node_b,
      cohort_a = link$cohort_a, cohort_b = link$cohort_b,
      ever_freed = as.integer(item_id %in% freed),
      bridge_floor_retained = as.integer(item_id %in% bridge_floor_retained & !item_id %in% freed),
      development_constraint_decision = case_when(
        screen_sample != "comparison_only" ~ "diagnostic_only_no_selection",
        ever_freed == 1 ~ "free_in_development_sensitivity",
        bridge_floor_retained == 1 ~ "retain_required_link_bridge_floor",
        is.na(inference_reliable) | inference_reliable == 0 ~ "review_insufficient_or_unreliable_inference",
        material_signal == 1 & statistical_signal == 0 ~ "review_material_only",
        material_signal == 0 & statistical_signal == 1 ~ "review_statistical_only",
        material_signal == 0 & statistical_signal == 0 ~ "retain_constraint_development_only",
        TRUE ~ "review_other"
      ),
      full_version_review_status = "required",
      treatment_used_as_model_predictor = 0L,
      final_link_item_approved = 0L
    )
  decision_rows[[link$link_id[[1]]]] <- final
}

evidence <- bind_rows(evidence_rows)
decisions <- bind_rows(decision_rows)
iterations <- bind_rows(iteration_rows)
nonbinary <- bind_rows(
  tibble(node_id = character(), subject = character(), item_id = character(), nonbinary_observed_value_n = integer(), exclusion_reason = character()),
  bind_rows(nonbinary_rows)
)

coverage <- planned_links %>%
  select(link_type, link_id, subject, node_a, node_b, cohort_a, cohort_b, candidate_item_n) %>%
  left_join(
    decisions %>% group_by(link_id) %>% summarize(
      analyzed_binary_item_n = n(),
      free_n = sum(development_constraint_decision == "free_in_development_sensitivity"),
      retain_n = sum(development_constraint_decision == "retain_constraint_development_only"),
      required_link_bridge_n = sum(development_constraint_decision == "retain_required_link_bridge_floor"),
      review_n = sum(str_starts(development_constraint_decision, "review_")),
      diagnostic_only_n = sum(development_constraint_decision == "diagnostic_only_no_selection"),
      .groups = "drop"
    ), by = "link_id"
  ) %>%
  mutate(
    across(c(analyzed_binary_item_n, free_n, retain_n, required_link_bridge_n, review_n, diagnostic_only_n), ~ coalesce(.x, 0L)),
    nonfreed_item_n = analyzed_binary_item_n - free_n,
    empirical_edge_status = case_when(
      analyzed_binary_item_n == 0 ~ "not_analyzed",
      screen_sample != "comparison_only" ~ "diagnostic_only",
      nonfreed_item_n < thresholds$minimum_common_items ~ "fewer_than_minimum_nonfreed_items",
      TRUE ~ "at_least_minimum_nonfreed_items"
    )
  )

output_profile <- if (rule_profile == "standard") screen_sample else paste(screen_sample, rule_profile, sep = "_")
out_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/05_anchor_purification", output_profile))
derived_dir <- assert_output(file.path(work_root, "derived/y1_y3_irt"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(evidence, file.path(out_dir, "multiyear_anchor_dif_evidence.csv"), na = "")
write_csv(decisions, file.path(out_dir, "multiyear_anchor_link_decisions.csv"), na = "")
write_csv(iterations, file.path(out_dir, "multiyear_anchor_purification_iterations.csv"), na = "")
write_csv(coverage, file.path(out_dir, "multiyear_anchor_link_coverage.csv"), na = "")
write_csv(nonbinary, file.path(out_dir, "multiyear_nonbinary_exclusions.csv"), na = "")
if (rule_profile == "math_bridge5") {
  arabic_grade_1_2_link_audit <- coverage %>%
    filter(
      subject == "Arabic",
      str_detect(node_a, "^Y3\\|(baseline|endline)\\|Arabic\\|[12]$"),
      str_detect(node_b, "^Y3\\|(baseline|endline)\\|Arabic\\|[12]$")
    ) %>%
    arrange(link_type, node_a, node_b)
  write_csv(
    arabic_grade_1_2_link_audit,
    file.path(out_dir, "arabic_grade_1_2_link_audit.csv"),
    na = ""
  )
}

build_purified_mapping <- function() {
  freed_versions <- decisions %>%
    filter(development_constraint_decision == "free_in_development_sensitivity") %>%
    distinct(subject, strict_item_version_id) %>% mutate(global_empirical_free = 1L)
  mapped <- occurrences %>%
    left_join(freed_versions, by = c("subject", "strict_item_version_id")) %>%
    mutate(global_empirical_free = coalesce(global_empirical_free, 0L))

  accepted <- decisions %>%
    filter(development_constraint_decision != "free_in_development_sensitivity", node_a != node_b) %>%
    distinct(subject, strict_item_version_id, node_a, node_b)

  mapping_rows <- list()
  version_groups <- mapped %>% distinct(subject, item_id, strict_item_version_id)
  for (index in seq_len(nrow(version_groups))) {
    key <- version_groups[index, ]
    members <- mapped %>%
      filter(subject == key$subject, item_id == key$item_id, strict_item_version_id == key$strict_item_version_id) %>%
      arrange(node_id)
    globally_freed <- any(members$global_empirical_free == 1)
    parent <- setNames(members$node_id, members$node_id)
    find_root <- function(value) {
      while (parent[[value]] != value) value <- parent[[value]]
      value
    }
    union_nodes <- function(left, right) {
      left_root <- find_root(left); right_root <- find_root(right)
      if (left_root != right_root) parent[[right_root]] <<- left_root
    }
    if (!globally_freed) {
      item_edges <- accepted %>%
        filter(subject == key$subject, strict_item_version_id == key$strict_item_version_id,
               node_a %in% members$node_id, node_b %in% members$node_id)
      if (nrow(item_edges)) walk2(item_edges$node_a, item_edges$node_b, union_nodes)
      direct_nodes <- members$node_id[members$direct_y1_strict_anchor == 1]
      if (length(direct_nodes) > 1) walk(direct_nodes[-1], ~ union_nodes(direct_nodes[[1]], .x))
    }
    roots <- map_chr(members$node_id, find_root)
    component_labels <- map_chr(unique(roots), function(root) {
      component_nodes <- sort(members$node_id[roots == root])
      if (globally_freed) return(paste0("free|", component_nodes[[1]]))
      if (any(members$direct_y1_strict_anchor[roots == root] == 1)) return("Y1-linked")
      paste0("component|", component_nodes[[1]])
    })
    names(component_labels) <- unique(roots)
    labels <- unname(component_labels[roots])
    mapping_rows[[paste(key$subject, key$strict_item_version_id, sep = "|")]] <- members %>%
      mutate(
        purification_component = labels,
        purified_analysis_key = paste(subject, item_id, strict_item_version_id, labels, sep = "|"),
        purified_direct_y1_anchor = as.integer(direct_y1_strict_anchor == 1 & !globally_freed),
        purification_status = if_else(globally_freed, "globally_freed_after_robust_pairwise_dif", "retained_within_empirically_connected_component"),
        direct_y1_empirical_status = if_else(purified_direct_y1_anchor == 1, "not_retested_against_y1_in_this_pass", "not_applicable_or_freed"),
        final_anchor_approved = 0L
      ) %>%
      select(node_id, year, wave, subject, administered_grade, item_id, strict_item_version_id,
             purified_analysis_key, purified_direct_y1_anchor, global_empirical_free,
             purification_component, purification_status, direct_y1_empirical_status,
             full_version_review_status, final_anchor_approved)
  }
  bind_rows(mapping_rows)
}

build_purified_paths <- function(mapping) {
  edge_counts <- decisions %>%
    filter(node_a != node_b, development_constraint_decision != "free_in_development_sensitivity") %>%
    group_by(subject, node_a, node_b) %>%
    summarize(parent_edge_anchor_n = n_distinct(strict_item_version_id), .groups = "drop") %>%
    filter(parent_edge_anchor_n >= thresholds$minimum_common_items)
  direct_counts <- mapping %>%
    group_by(node_id, subject) %>%
    summarize(root_direct_anchor_n = sum(purified_direct_y1_anchor == 1), .groups = "drop")
  output <- list()
  for (subject_value in sort(unique(node_metadata$subject))) {
    nodes <- node_metadata %>% filter(subject == subject_value) %>% arrange(node_id)
    distance <- setNames(rep(Inf, nrow(nodes)), nodes$node_id)
    bottleneck <- setNames(rep(-Inf, nrow(nodes)), nodes$node_id)
    parent <- setNames(rep("", nrow(nodes)), nodes$node_id)
    parent_n <- setNames(rep(NA_integer_, nrow(nodes)), nodes$node_id)
    path_text <- setNames(rep("", nrow(nodes)), nodes$node_id)
    root_n <- setNames(rep(0L, nrow(nodes)), nodes$node_id)
    direct <- direct_counts %>% filter(subject == subject_value)
    for (i in seq_len(nrow(direct))) {
      node <- direct$node_id[[i]]; count <- direct$root_direct_anchor_n[[i]]
      if (count >= thresholds$minimum_common_items) {
        distance[[node]] <- 1; bottleneck[[node]] <- count
        parent[[node]] <- paste0("Y1|reference|", subject_value); parent_n[[node]] <- count
        root_n[[node]] <- count; path_text[[node]] <- paste(parent[[node]], node, sep = ">")
      }
    }
    visited <- setNames(rep(FALSE, nrow(nodes)), nodes$node_id)
    subject_edges <- edge_counts %>% filter(subject == subject_value)
    repeat {
      candidates <- names(distance)[!visited & is.finite(distance)]
      if (!length(candidates)) break
      order_key <- order(distance[candidates], -bottleneck[candidates], path_text[candidates])
      current <- candidates[order_key[[1]]]
      visited[[current]] <- TRUE
      neighbors <- bind_rows(
        subject_edges %>% filter(node_a == current) %>% transmute(neighbor = node_b, count = parent_edge_anchor_n),
        subject_edges %>% filter(node_b == current) %>% transmute(neighbor = node_a, count = parent_edge_anchor_n)
      )
      if (!nrow(neighbors)) next
      for (j in seq_len(nrow(neighbors))) {
        neighbor <- neighbors$neighbor[[j]]; count <- neighbors$count[[j]]
        candidate_distance <- distance[[current]] + 1
        candidate_bottleneck <- min(bottleneck[[current]], count)
        candidate_path <- paste(path_text[[current]], neighbor, sep = ">")
        better <- candidate_distance < distance[[neighbor]] ||
          (candidate_distance == distance[[neighbor]] && candidate_bottleneck > bottleneck[[neighbor]]) ||
          (candidate_distance == distance[[neighbor]] && candidate_bottleneck == bottleneck[[neighbor]] &&
             (path_text[[neighbor]] == "" || candidate_path < path_text[[neighbor]]))
        if (better) {
          distance[[neighbor]] <- candidate_distance; bottleneck[[neighbor]] <- candidate_bottleneck
          parent[[neighbor]] <- current; parent_n[[neighbor]] <- count
          root_n[[neighbor]] <- root_n[[current]]; path_text[[neighbor]] <- candidate_path
        }
      }
    }
    output[[subject_value]] <- nodes %>% mutate(
      anchor_mode = "purified_strict", path_status = if_else(is.finite(distance[node_id]), "linked_development_only", "unlinked"),
      path_depth = if_else(is.finite(distance[node_id]), as.numeric(distance[node_id]), NA_real_),
      parent_node_id = unname(parent[node_id]), parent_edge_anchor_n = unname(parent_n[node_id]),
      root_direct_anchor_n = unname(root_n[node_id]),
      path_minimum_anchor_n = if_else(is.finite(distance[node_id]), as.numeric(bottleneck[node_id]), NA_real_),
      selected_path = unname(path_text[node_id]), full_version_review_status = "required", final_link_approved = 0L
    ) %>%
      select(anchor_mode, node_id, year, wave, subject, administered_grade, path_status, path_depth,
             parent_node_id, parent_edge_anchor_n, root_direct_anchor_n, path_minimum_anchor_n,
             selected_path, full_version_review_status, final_link_approved)
  }
  list(paths = bind_rows(output), edges = edge_counts, direct = direct_counts)
}

mapping_summary <- NULL
if (screen_sample == "comparison_only" && rule_profile == "standard") {
  mapping <- build_purified_mapping()
  path_results <- build_purified_paths(mapping)
  write_csv(mapping, file.path(derived_dir, "multiyear_purified_strict_occurrence_mapping.csv"), na = "")
  write_csv(path_results$paths, file.path(out_dir, "multiyear_purified_selected_paths.csv"), na = "")
  write_csv(path_results$edges, file.path(out_dir, "multiyear_purified_node_edges.csv"), na = "")
  mapping_summary <- list(
    occurrence_n = nrow(mapping),
    globally_freed_version_n = n_distinct(mapping$strict_item_version_id[mapping$global_empirical_free == 1]),
    retained_direct_y1_anchor_occurrence_n = sum(mapping$purified_direct_y1_anchor == 1),
    linked_node_n = sum(path_results$paths$path_status == "linked_development_only"),
    unlinked_node_n = sum(path_results$paths$path_status == "unlinked")
  )
}

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  screen_sample = screen_sample,
  rule_profile = rule_profile,
  treatment_use = if (screen_sample == "comparison_only") {
    "Treatment assignment used only to restrict sources with assignment to comparison observations; treatment was not a DIF predictor. Sources without an assignment field use all observations."
  } else {
    "Treatment assignment was neither used as a predictor nor used to restrict the sample. This pass is diagnostic only and cannot select anchors."
  },
  binary_rule = "Only observed zero/one item responses enter estimation. Tagged .a is scored zero; ordinary system missing remains missing. Any observed nonbinary item is excluded.",
  planned_link_n = nrow(planned_links), analyzed_link_n = n_distinct(decisions$link_id),
  item_link_decision_n = nrow(decisions), nonbinary_exclusion_n = nrow(nonbinary),
  link_type_counts = as.list(table(planned_links$link_type)),
  decision_counts = as.list(table(decisions$development_constraint_decision)),
  coverage_counts = as.list(table(coverage$empirical_edge_status)),
  required_link_bridge_floor_retained_item_link_n = sum(decisions$bridge_floor_retained == 1),
  mapping = mapping_summary,
  automatic_free_rule = if (rule_profile == "math_bridge5") {
    paste0(
      "For every subject: comparison-only sample; reliable clustered inference; BOTH Holm-adjusted joint logistic and MH p < ",
      thresholds$alpha, "; at least one material flag; and at least ",
      bridge_rule$minimum_retained_anchors_per_link,
      " common items retained per tested link. Eligible frees are ranked by the weaker adjusted p-value and then material severity."
    )
  } else {
    paste0(
      "Comparison-only sample; reliable clustered inference; Holm-adjusted joint logistic or MH p < ", thresholds$alpha,
      "; and at least one material flag (uniform OR outside [", thresholds$uniform_odds_ratio_lower, ", ", thresholds$uniform_odds_ratio_upper,
      "], |nonuniform beta| > ", thresholds$nonuniform_logit_coefficient_abs,
      ", incremental pseudo-R2 > ", thresholds$incremental_pseudo_r2,
      ", or |MH delta| > ", thresholds$mantel_haenszel_delta_abs, ")."
    )
  },
  purification_rule = "Flagged items are removed from the conditioning set and the link is re-estimated for up to the configured maximum iterations. A robust pairwise flag globally frees that item version in the conservative pooled-model sensitivity.",
  status = "development_only_not_approved; full prompt/stimulus/options/key/rubric/layout/scoring/exposure review and direct Y1 empirical retesting remain required"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE, null = "null"), file.path(out_dir, "multiyear_anchor_purification_summary.json"))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE, null = "null"), "\n")
