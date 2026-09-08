#!/usr/bin/env Rscript

# Convert pairwise comparison-only DIF/drift decisions into Andy-style targeted
# parameter frees. A flagged item is split only in the implicated later/upper/
# pilot administration (or focal cohort), rather than discarded everywhere.

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1 || length(args) > 2) {
  stop(paste(
    "Usage: build_targeted_purified_constraints.R config/paths.local.yml",
    "[broad|andy_core|andy_core_math_bridge5]"
  ))
}
config_path <- normalizePath(args[[1]], mustWork = TRUE)
purification_profile <- if (length(args) == 2) args[[2]] else "broad"
if (!purification_profile %in% c("broad", "andy_core", "andy_core_math_bridge5")) {
  stop("Unknown purification profile")
}
paths <- yaml::read_yaml(config_path)$dropbox
analysis <- yaml::read_yaml(file.path(dirname(config_path), "analysis.yml"))
minimum_anchors <- analysis$anchor_purification$minimum_common_items
bridge_minimum_anchors <- analysis$anchor_purification$required_link_bridge_sensitivity$minimum_graph_link_anchors

source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
normalize_for_guard <- function(path) normalizePath(path, mustWork = FALSE)
is_within <- function(path, root) {
  candidate <- normalize_for_guard(path); boundary <- normalize_for_guard(root)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_output <- function(path) {
  candidate <- normalize_for_guard(path)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Output inside a read-only legacy root")
  candidate
}

graph_dir <- file.path(work_root, "outputs/y1_y3_irt/01_multiyear_link_graph")
purification_dir <- file.path(work_root, "outputs/y1_y3_irt/05_anchor_purification/comparison_only")
derived_dir <- assert_output(file.path(work_root, "derived/y1_y3_irt"))
occurrences <- read_csv(file.path(graph_dir, "multiyear_item_occurrence_manifest.csv"), show_col_types = FALSE) %>%
  mutate(administered_grade = as.character(administered_grade))
link_items <- read_csv(file.path(graph_dir, "multiyear_link_item_manifest.csv"), show_col_types = FALSE)
decisions <- read_csv(file.path(purification_dir, "multiyear_anchor_link_decisions.csv"), show_col_types = FALSE)
decision_source <- "comparison_only_standard"
if (purification_profile == "andy_core_math_bridge5") {
  bridge_decisions <- read_csv(
    file.path(
      work_root,
      "outputs/y1_y3_irt/05_anchor_purification/comparison_only_math_bridge5/multiyear_anchor_link_decisions.csv"
    ),
    show_col_types = FALSE
  )
  if (!"bridge_floor_retained" %in% names(bridge_decisions)) {
    stop("Required-link bridge decisions do not contain the audit flag")
  }
  decisions <- bridge_decisions
  decision_source <- "comparison_only_consensus_rule_with_required_link_floor_all_subjects"
}
if (!"bridge_floor_retained" %in% names(decisions)) {
  decisions$bridge_floor_retained <- 0L
}
node_metadata <- occurrences %>% distinct(node_id, year, wave, subject, administered_grade)

node_field <- function(condition, yes, no) ifelse(condition, yes, no)
targeted_decisions <- decisions %>%
  left_join(node_metadata %>% select(node_id, year, wave, administered_grade) %>%
              rename(node_a = node_id, node_year_a = year, node_wave_a = wave, node_grade_a = administered_grade), by = "node_a") %>%
  left_join(node_metadata %>% select(node_id, year, wave, administered_grade) %>%
              rename(node_b = node_id, node_year_b = year, node_wave_b = wave, node_grade_b = administered_grade), by = "node_b") %>%
  mutate(
    full_version_review_status = if (purification_profile == "andy_core_math_bridge5") {
      "verified_by_project_lead_immutable_id_rule_2026_09_08"
    } else {
      full_version_review_status
    },
    robust_free = development_constraint_decision == "free_in_development_sensitivity",
    constraint_free = robust_free & case_when(
      purification_profile == "broad" ~ TRUE,
      link_type == "within_year_wave_drift" ~ TRUE,
      link_type == "within_year_adjacent_grade_dif" & node_wave_a == "endline" & node_wave_b == "endline" ~ TRUE,
      TRUE ~ FALSE
    ),
    required_link_bridge_constraint = as.integer(
      purification_profile == "andy_core_math_bridge5" &
        coalesce(bridge_floor_retained, 0L) == 1L &
        (
          link_type == "within_year_wave_drift" |
            (link_type == "within_year_adjacent_grade_dif" & node_wave_a == "endline" & node_wave_b == "endline")
        )
    ),
    free_target_node = case_when(
      !robust_free ~ "",
      link_type == "within_node_cohort_dif" ~ node_a,
      link_type == "within_year_wave_drift" ~ node_field(node_wave_a == "baseline", node_a, node_b),
      link_type == "within_year_adjacent_grade_dif" ~ node_field(as.integer(node_grade_a) > as.integer(node_grade_b), node_a, node_b),
      link_type %in% c("across_year_same_grade_drift", "across_year_grade_transition_drift") ~ node_field(node_year_a > node_year_b, node_a, node_b),
      link_type == "pilot_to_main_drift" ~ node_field(node_wave_a == "pilot", node_a, node_b),
      TRUE ~ node_b
    ),
    free_target_cohort = if_else(robust_free & link_type == "within_node_cohort_dif", as.character(cohort_b), ""),
    target_rule = case_when(
      !robust_free ~ "no_parameter_free",
      link_type == "within_node_cohort_dif" ~ "free_focal_cohort_b",
      link_type == "within_year_wave_drift" ~ "free_baseline_preserve_endline_reference",
      link_type == "within_year_adjacent_grade_dif" ~ "free_upper_grade",
      link_type %in% c("across_year_same_grade_drift", "across_year_grade_transition_drift") ~ "free_later_year",
      link_type == "pilot_to_main_drift" ~ "free_pilot_preserve_operational_form",
      TRUE ~ "free_node_b"
    )
  )

provisional_bridge_occurrences <- targeted_decisions %>%
  filter(required_link_bridge_constraint == 1L) %>%
  select(subject, strict_item_version_id, item_id, node_a, node_b) %>%
  tidyr::pivot_longer(c(node_a, node_b), values_to = "node_id") %>%
  distinct(subject, strict_item_version_id, item_id, node_id) %>%
  mutate(required_link_bridge = 1L)

node_targets <- targeted_decisions %>%
  filter(constraint_free, free_target_cohort == "") %>%
  distinct(subject, strict_item_version_id, free_target_node) %>%
  rename(node_id = free_target_node) %>%
  mutate(targeted_node_free = 1L)
cohort_overrides <- targeted_decisions %>%
  filter(constraint_free, free_target_cohort != "") %>%
  distinct(subject, strict_item_version_id, item_id, node_id = free_target_node, cohort = free_target_cohort) %>%
  mutate(
    override_analysis_key = paste(subject, item_id, strict_item_version_id, node_id, paste0("cohort=", cohort), sep = "|"),
    override_reason = "robust_within_node_cohort_dif",
    final_anchor_approved = 0L
  )

mapping_rows <- list()
version_groups <- occurrences %>% distinct(subject, item_id, strict_item_version_id)
for (index in seq_len(nrow(version_groups))) {
  key <- version_groups[index, ]
  members <- occurrences %>%
    filter(subject == key$subject, item_id == key$item_id, strict_item_version_id == key$strict_item_version_id) %>%
    arrange(node_id) %>%
    left_join(
      node_targets %>% filter(subject == key$subject, strict_item_version_id == key$strict_item_version_id) %>% select(node_id, targeted_node_free),
      by = "node_id"
    ) %>%
    left_join(
      provisional_bridge_occurrences %>%
        filter(subject == key$subject, strict_item_version_id == key$strict_item_version_id) %>%
        select(node_id, required_link_bridge),
      by = "node_id"
    ) %>%
    mutate(
      targeted_node_free = coalesce(targeted_node_free, 0L),
      required_link_bridge = coalesce(required_link_bridge, 0L),
      full_version_review_status = if (purification_profile == "andy_core_math_bridge5") {
        "verified_by_project_lead_immutable_id_rule_2026_09_08"
      } else {
        full_version_review_status
      }
    )
  parent <- setNames(members$node_id, members$node_id)
  find_root <- function(value) {
    while (parent[[value]] != value) value <- parent[[value]]
    value
  }
  union_nodes <- function(left, right) {
    left_root <- find_root(left); right_root <- find_root(right)
    if (left_root != right_root) parent[[right_root]] <<- left_root
  }
  # Andy's workflow begins with common versions constrained and then frees the
  # implicated administration. Preserve that logic: every non-targeted exact-
  # summary occurrence shares one parameter, while each targeted occurrence is
  # isolated. Operational version review remains pending for every constraint.
  retained_nodes <- members$node_id[members$targeted_node_free == 0]
  if (length(retained_nodes) > 1) walk(retained_nodes[-1], ~ union_nodes(retained_nodes[[1]], .x))
  roots <- map_chr(members$node_id, find_root)
  root_values <- unique(roots)
  component_labels <- map_chr(root_values, function(root) {
    in_component <- roots == root
    component_nodes <- sort(members$node_id[in_component])
    if (any(members$targeted_node_free[in_component] == 1)) return(paste0("freed|", component_nodes[[1]]))
    if (any(members$direct_y1_strict_anchor[in_component] == 1)) return("Y1-linked")
    "shared-strict"
  })
  names(component_labels) <- root_values
  labels <- unname(component_labels[roots])
  mapping_rows[[paste(key$subject, key$strict_item_version_id, sep = "|")]] <- members %>%
    mutate(
      purification_component = labels,
      purified_analysis_key = paste(subject, item_id, strict_item_version_id, labels, sep = "|"),
      purified_direct_y1_anchor = as.integer(direct_y1_strict_anchor == 1 & targeted_node_free == 0),
      purification_status = case_when(
        targeted_node_free == 1 ~ "targeted_parameter_free",
        required_link_bridge == 1 ~ "retained_required_link_bridge_floor",
        str_starts(labels, "Y1-linked") ~ "retained_in_y1_linked_component",
        TRUE ~ "retained_in_empirically_connected_component"
      ),
      direct_y1_empirical_status = if_else(purified_direct_y1_anchor == 1, "not_retested_against_y1_in_this_pass", "not_applicable_or_freed"),
      final_anchor_approved = 0L
    ) %>%
    select(node_id, year, wave, subject, administered_grade, item_id, strict_item_version_id,
           purified_analysis_key, purified_direct_y1_anchor, targeted_node_free,
           required_link_bridge, purification_component, purification_status, direct_y1_empirical_status,
           full_version_review_status, final_anchor_approved)
}
mapping <- bind_rows(mapping_rows)

# Recompute all strict graph edges from actual equality keys after targeted
# splits. The 225 scientific comparisons determine frees; they do not erase
# other exact-summary links that were not separately tested in this pass.
pair_candidates <- link_items %>%
  filter(strict_summary_link == 1) %>%
  distinct(subject, strict_item_version_id, node_a, node_b)
edge_counts <- pair_candidates %>%
  left_join(mapping %>% select(subject, strict_item_version_id, node_id, key_a = purified_analysis_key),
            by = c("subject", "strict_item_version_id", "node_a" = "node_id")) %>%
  left_join(mapping %>% select(subject, strict_item_version_id, node_id, key_b = purified_analysis_key),
            by = c("subject", "strict_item_version_id", "node_b" = "node_id")) %>%
  filter(!is.na(key_a), !is.na(key_b), key_a == key_b) %>%
  group_by(subject, node_a, node_b) %>%
  summarize(parent_edge_anchor_n = n_distinct(strict_item_version_id), .groups = "drop") %>%
  mutate(
    required_anchor_n = if_else(
      purification_profile == "andy_core_math_bridge5",
      bridge_minimum_anchors,
      minimum_anchors
    )
  ) %>%
  filter(parent_edge_anchor_n >= required_anchor_n)
direct_counts <- mapping %>%
  group_by(node_id, subject) %>%
  summarize(root_direct_anchor_n = sum(purified_direct_y1_anchor == 1), .groups = "drop")

build_paths <- function(subject_value) {
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
    root_minimum <- if (purification_profile == "andy_core_math_bridge5") {
      bridge_minimum_anchors
    } else {
      minimum_anchors
    }
    if (count >= root_minimum) {
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
    current <- candidates[order(distance[candidates], -bottleneck[candidates], path_text[candidates])[[1]]]
    visited[[current]] <- TRUE
    neighbors <- bind_rows(
      subject_edges %>% filter(node_a == current) %>% transmute(neighbor = node_b, count = parent_edge_anchor_n),
      subject_edges %>% filter(node_b == current) %>% transmute(neighbor = node_a, count = parent_edge_anchor_n)
    )
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
  nodes %>% mutate(
    anchor_mode = case_when(
      purification_profile == "andy_core" ~ "purified_andy_core",
      purification_profile == "andy_core_math_bridge5" ~ "purified_andy_core_math_bridge5",
      TRUE ~ "purified_strict"
    ),
    path_status = if_else(is.finite(distance[node_id]), "linked_development_only", "unlinked"),
    path_depth = if_else(is.finite(distance[node_id]), as.numeric(distance[node_id]), NA_real_),
    parent_node_id = unname(parent[node_id]), parent_edge_anchor_n = unname(parent_n[node_id]),
    root_direct_anchor_n = unname(root_n[node_id]),
    path_minimum_anchor_n = if_else(is.finite(distance[node_id]), as.numeric(bottleneck[node_id]), NA_real_),
    selected_path = unname(path_text[node_id]),
    full_version_review_status = if_else(
      purification_profile == "andy_core_math_bridge5",
      "verified_by_project_lead_immutable_id_rule_2026_09_08",
      "required"
    ),
    final_link_approved = 0L
  ) %>%
    select(anchor_mode, node_id, year, wave, subject, administered_grade, path_status, path_depth,
           parent_node_id, parent_edge_anchor_n, root_direct_anchor_n, path_minimum_anchor_n,
           selected_path, full_version_review_status, final_link_approved)
}
paths_output <- map_dfr(sort(unique(node_metadata$subject)), build_paths)

profile_suffix <- case_when(
  purification_profile == "andy_core" ~ "andy_core",
  purification_profile == "andy_core_math_bridge5" ~ "andy_core_math_bridge5",
  TRUE ~ "targeted"
)
mapping_name <- case_when(
  purification_profile == "andy_core" ~ "multiyear_purified_andy_core_occurrence_mapping.csv",
  purification_profile == "andy_core_math_bridge5" ~ "multiyear_purified_andy_core_math_bridge5_occurrence_mapping.csv",
  TRUE ~ "multiyear_purified_targeted_occurrence_mapping.csv"
)
override_name <- case_when(
  purification_profile == "andy_core" ~ "multiyear_purified_andy_core_cohort_key_overrides.csv",
  purification_profile == "andy_core_math_bridge5" ~ "multiyear_purified_andy_core_math_bridge5_cohort_key_overrides.csv",
  TRUE ~ "multiyear_purified_cohort_key_overrides.csv"
)
write_csv(targeted_decisions, file.path(purification_dir, paste0("multiyear_anchor_link_decisions_with_targets_", profile_suffix, ".csv")), na = "")
if (purification_profile == "broad") {
  write_csv(targeted_decisions, file.path(purification_dir, "multiyear_anchor_link_decisions_with_targets.csv"), na = "")
}
write_csv(mapping, file.path(derived_dir, mapping_name), na = "")
write_csv(cohort_overrides, file.path(derived_dir, override_name), na = "")
write_csv(paths_output, file.path(purification_dir, paste0("multiyear_", profile_suffix, "_purified_selected_paths.csv")), na = "")
write_csv(edge_counts, file.path(purification_dir, paste0("multiyear_", profile_suffix, "_purified_node_edges.csv")), na = "")

summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  purification_profile = purification_profile,
  decision_source = decision_source,
  item_id_equivalence_status = if (purification_profile == "andy_core_math_bridge5") {
    "verified_by_project_lead_immutable_id_rule_2026_09_08"
  } else {
    "not_applicable"
  },
  robust_pairwise_free_n = sum(targeted_decisions$robust_free),
  applied_pairwise_free_n = sum(targeted_decisions$constraint_free),
  targeted_node_item_free_n = nrow(node_targets),
  targeted_cohort_item_free_n = nrow(cohort_overrides),
  required_link_bridge_item_link_n = sum(targeted_decisions$required_link_bridge_constraint == 1L),
  required_link_bridge_occurrence_n = sum(mapping$required_link_bridge == 1L),
  retained_direct_y1_anchor_occurrence_n = sum(mapping$purified_direct_y1_anchor == 1),
  linked_node_n = sum(paths_output$path_status == "linked_development_only"),
  unlinked_node_n = sum(paths_output$path_status == "unlinked"),
  minimum_linked_path_anchor_n = min(paths_output$path_minimum_anchor_n[paths_output$path_status == "linked_development_only"]),
  standard_minimum_graph_link_anchor_n = minimum_anchors,
  required_link_minimum_graph_anchor_n = if (purification_profile == "andy_core_math_bridge5") bridge_minimum_anchors else minimum_anchors,
  targeting_rules = list(
    wave = "free baseline and preserve the Year 1-style endline reference",
    grade = "free the upper-grade occurrence",
    year = "free the later-year occurrence",
    pilot = "free the pilot occurrence and preserve the operational form",
    cohort = "free focal cohort B only"
  ),
  status = "development_only_not_approved"
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(purification_dir, paste0("multiyear_", profile_suffix, "_constraint_summary.json")))
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
