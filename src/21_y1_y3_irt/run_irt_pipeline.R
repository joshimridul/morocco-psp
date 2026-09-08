#!/usr/bin/env Rscript

# One-click, measurement-only build. This orchestrator is intentionally boring:
# every command and research choice is enumerated, logged, and checked. It never
# invokes src/22_treatment_effects or any regression program.

suppressPackageStartupMessages({
  library(digest)
  library(dplyr)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(tibble)
  library(tidyr)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || length(args) > 2L) {
  stop("Usage: run_irt_pipeline.R config/paths.local.yml [--assemble-only]")
}
assemble_only <- length(args) == 2L && identical(args[[2]], "--assemble-only")
if (length(args) == 2L && !assemble_only) stop("Only supported option: --assemble-only")

config_path <- normalizePath(args[[1]], mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(config_path), ".."), mustWork = TRUE)
pipeline_spec_path <- normalizePath(file.path(repo_root, "config/irt_pipeline.yml"), mustWork = TRUE)
paths <- yaml::read_yaml(config_path)$dropbox
specification <- yaml::read_yaml(pipeline_spec_path)
source_roots <- normalizePath(c(paths$y1_root, paths$y2_root, paths$y3_root), mustWork = TRUE)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)

is_within <- function(path, root) {
  candidate <- normalizePath(path, mustWork = FALSE); boundary <- normalizePath(root, mustWork = FALSE)
  identical(candidate, boundary) || startsWith(candidate, paste0(boundary, .Platform$file.sep))
}
assert_output <- function(path) {
  candidate <- normalizePath(path, mustWork = FALSE)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) stop("Output must be below work_root")
  if (any(map_lgl(source_roots, ~ is_within(candidate, .x)))) stop("Output inside source root")
  candidate
}
script_path <- function(relative_path) normalizePath(file.path(repo_root, relative_path), mustWork = TRUE)

rscript <- yaml::read_yaml(config_path)$software$rscript
if (is.null(rscript) || is.na(rscript) || rscript == "") rscript <- Sys.which("Rscript")
python <- yaml::read_yaml(config_path)$software$python
if (is.null(python) || is.na(python) || python == "") python <- Sys.which("python3")
if (rscript == "" || python == "") stop("Rscript and python3 must be available")

run_stamp <- format(Sys.time(), tz = "UTC", "%Y%m%dT%H%M%SZ")
pipeline_dir <- assert_output(file.path(work_root, "outputs/y1_y3_irt/00_pipeline"))
log_dir <- assert_output(file.path(pipeline_dir, "logs", run_stamp))
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

# Preserve a stable pointer to the most recent *full* build even when a later
# assemble-only run refreshes reports. Recover it from timestamped manifests on
# older work directories that predate this convention.
latest_full_manifest_path <- file.path(pipeline_dir, "latest_full_pipeline_step_manifest.csv")
latest_full_summary_path <- file.path(pipeline_dir, "latest_full_pipeline_run_summary.json")
if (assemble_only && !file.exists(latest_full_manifest_path)) {
  historical_paths <- list.files(pipeline_dir, pattern = "^pipeline_step_manifest_[0-9TZ]+\\.csv$", full.names = TRUE)
  historical <- map(historical_paths, function(path) {
    candidate <- suppressMessages(read_csv(path, show_col_types = FALSE))
    if (nrow(candidate) > 5L && any(candidate$phase == "estimation")) {
      list(path = path, data = candidate, modified = file.info(path)$mtime)
    } else NULL
  }) %>% compact()
  if (length(historical)) {
    recovered <- historical[[which.max(map_dbl(historical, ~ as.numeric(.x$modified)))]]$data
    write_csv(recovered, latest_full_manifest_path, na = "")
    recovered_summary <- list(
      created_utc = max(recovered$ended_utc), run_stamp = recovered$run_stamp[[1]],
      mode = "full_measurement_build", step_n = nrow(recovered),
      failed_step_n = sum(recovered$exit_status != 0L),
      primary_method = specification$primary_method,
      treatment_regression_step_n = sum(grepl("treatment|regression|src/22", recovered$command, ignore.case = TRUE)),
      status = if (all(recovered$exit_status == 0L)) "completed" else "completed_with_nonrequired_failures"
    )
    writeLines(toJSON(recovered_summary, pretty = TRUE, auto_unbox = TRUE), latest_full_summary_path)
  }
}

# Freeze the exact measurement code used by this run. The regression pipeline
# refuses to consume a primary score when these hashes differ from the current
# source tree, which prevents a cached score from surviving later code edits.
code_roots <- file.path(repo_root, "src", c(
  "00_inventory", "01_harmonize", "02_scores", "04_anchors", "21_y1_y3_irt"
))
code_files <- c(
  unlist(map(code_roots, ~ list.files(.x, recursive = TRUE, full.names = TRUE))),
  file.path(repo_root, "config", c("analysis.yml", "irt_pipeline.yml"))
)
code_files <- sort(unique(code_files[file.exists(code_files) & !file.info(code_files)$isdir]))
code_manifest <- tibble(
  relative_path = substring(code_files, nchar(repo_root) + 2L),
  sha256 = map_chr(code_files, ~ digest(.x, algo = "sha256", file = TRUE, serialize = FALSE))
)
code_fingerprint <- digest(
  paste(code_manifest$relative_path, code_manifest$sha256, sep = "=", collapse = "\n"),
  algo = "sha256", serialize = FALSE
)
run_code_manifest_path <- file.path(pipeline_dir, paste0("pipeline_code_manifest_", run_stamp, ".csv"))
write_csv(code_manifest, run_code_manifest_path, na = "")

# Frozen Year 1 estimates are prerequisites, never regenerated by this build.
y1_reference_paths <- file.path(
  work_root, "outputs/y1_y3_irt/00_y1_reference/ster_probe",
  c("y1_arabic_item_parameters.csv", "y1_french_item_parameters.csv", "y1_maths_item_parameters.csv")
)
walk(y1_reference_paths, ~ if (!file.exists(.x)) stop("Missing frozen Year 1 reference: ", .x))
y1_reference_hashes <- tibble(
  reference_file = basename(y1_reference_paths),
  sha256 = map_chr(y1_reference_paths, ~ digest(.x, algo = "sha256", file = TRUE, serialize = FALSE)),
  role = "read_only_frozen_y1_parameter_input"
)
write_csv(y1_reference_hashes, file.path(pipeline_dir, "frozen_y1_reference_hashes.csv"), na = "")

# Hash the six response sources before any build step. The adversarial validator
# recomputes these hashes at the end, making source immutability a within-run
# test rather than an assumption inherited from a freshly generated registry.
core_sources <- tibble(
  source_key = c("Y2|baseline", "Y2|pilot", "Y2|endline", "Y3|baseline", "Y3|pilot", "Y3|endline"),
  root_alias = c(rep("y2_root", 3), rep("y3_root", 3)),
  relative_path = c(
    "4 - Data processing/04_Baseline/Clean/baseline_data.dta",
    "4 - Data processing/08_Pilot/Clean/pilot_data_20250505_ya.dta",
    "4 - Data processing/09_Endline/Clean/endline_data_20250716_ks.dta",
    "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta",
    "4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta",
    "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta"
  )
) %>% mutate(
  source_path = map2_chr(root_alias, relative_path, ~ normalizePath(file.path(paths[[.x]], .y), mustWork = TRUE)),
  sha256 = map_chr(source_path, ~ digest(.x, algo = "sha256", file = TRUE, serialize = FALSE)),
  role = "read_only_core_response_source"
)
write_csv(core_sources %>% select(-source_path), file.path(pipeline_dir, "core_response_source_hashes.csv"), na = "")

step <- function(id, phase, executable, arguments, required = TRUE, timeout_seconds = 3600L) {
  list(id = id, phase = phase, executable = executable, arguments = arguments,
       required = required, timeout_seconds = timeout_seconds)
}
q <- shQuote
base_steps <- list(
  step("y3_source_registry", "lineage", python, c(
    script_path("src/00_inventory/build_y3_registry.py"), "--config", config_path,
    "--github-root", repo_root, "--out-dir", file.path(work_root, "outputs/y3_ministry/00_readiness")
  )),
  step("y3_item_version_registry", "lineage", python, c(
    script_path("src/01_harmonize/build_item_version_registry.py"), "--config", config_path, "--github-root", repo_root
  )),
  step("y3_score_reconstruction", "lineage", rscript, c(
    script_path("src/02_scores/reconstruct_scores.R"), config_path
  )),
  step("y2_source_registry", "lineage", python, c(
    script_path("src/00_inventory/build_y2_source_registry.py"), "--config", config_path
  )),
  step("y2_operational_registry", "lineage", rscript, c(
    script_path("src/21_y1_y3_irt/build_y2_operational_registry.R"), config_path
  )),
  step("y3_y1_anchor_manifest", "linkage", python, c(
    script_path("src/21_y1_y3_irt/build_y3_y1_anchor_manifest.py"), "--config", config_path, "--github-root", repo_root
  )),
  step("multiyear_link_graph", "linkage", python, c(
    script_path("src/21_y1_y3_irt/build_multiyear_link_graph.py"), "--config", config_path
  ))
)

direct_steps <- map(unlist(specification$node_link_runs$direct), ~ step(
  paste0("direct_", .x), "estimation", rscript,
  c(script_path("src/21_y1_y3_irt/run_y3_direct_fixed_anchor_scoring.R"), config_path, .x), timeout_seconds = 2400L
))
chained_steps <- map(unlist(specification$node_link_runs$chained), ~ step(
  paste0("chained_", .x), "estimation", rscript,
  c(script_path("src/21_y1_y3_irt/run_multiyear_chained_scoring.R"), config_path, .x), timeout_seconds = 2400L
))
purification_steps <- list(
  step("purification_comparison", "anchor_purification", rscript,
       c(script_path("src/21_y1_y3_irt/run_multiyear_anchor_purification.R"), config_path, "comparison_only"), timeout_seconds = 2400L),
  step("purification_all_blinded", "anchor_purification", rscript,
       c(script_path("src/21_y1_y3_irt/run_multiyear_anchor_purification.R"), config_path, "all_students_blinded"), timeout_seconds = 2400L),
  step("purification_math_bridge5", "anchor_purification", rscript,
       c(script_path("src/21_y1_y3_irt/run_multiyear_anchor_purification.R"), config_path, "comparison_only", "math_bridge5"), timeout_seconds = 2400L),
  step("constraints_broad", "anchor_purification", rscript,
       c(script_path("src/21_y1_y3_irt/build_targeted_purified_constraints.R"), config_path, "broad")),
  step("constraints_andy_core", "anchor_purification", rscript,
       c(script_path("src/21_y1_y3_irt/build_targeted_purified_constraints.R"), config_path, "andy_core")),
  step("constraints_final_math", "anchor_purification", rscript,
       c(script_path("src/21_y1_y3_irt/build_targeted_purified_constraints.R"), config_path, "andy_core_math_bridge5"))
)

joint_grid <- tidyr::crossing(
  anchor_mode = unlist(specification$joint_factorial$anchor_modes),
  sample_mode = unlist(specification$joint_factorial$sample_modes),
  model_scope = unlist(specification$joint_factorial$model_scopes)
)
additional <- map_dfr(specification$additional_joint_runs, ~ tibble(
  anchor_mode = .x$anchor_mode, sample_mode = .x$sample_mode, model_scope = .x$model_scope
))
joint_specs <- bind_rows(joint_grid, additional) %>% distinct()
joint_steps <- pmap(joint_specs, function(anchor_mode, sample_mode, model_scope) step(
  paste("joint", model_scope, sample_mode, anchor_mode, sep = "__"), "estimation", rscript,
  c(script_path("src/21_y1_y3_irt/run_joint_multigroup_scoring.R"), config_path, anchor_mode, sample_mode, model_scope),
  timeout_seconds = 3600L
))

post_estimation_steps <- list(
  step("anchor_purification_validation", "validation", rscript,
       c(script_path("src/21_y1_y3_irt/validate_multiyear_anchor_purification.R"), config_path))
)

assembly_steps <- list(
  step("plain_score_robustness", "outcome_construction", rscript,
       c(script_path("src/21_y1_y3_irt/build_plain_score_robustness.R"), config_path)),
  step("outcome_bundle", "outcome_construction", rscript,
       c(script_path("src/21_y1_y3_irt/build_irt_outcome_bundle.R"), config_path, pipeline_spec_path)),
  step("measurement_correlations", "outcome_construction", rscript,
       c(script_path("src/21_y1_y3_irt/build_measurement_correlations.R"), config_path, pipeline_spec_path)),
  step("adversarial_validation", "validation", rscript,
       c(script_path("src/21_y1_y3_irt/validate_irt_pipeline_adversarial.R"), config_path, pipeline_spec_path)),
  step("unit_tests", "validation", python, c("-m", "unittest", "discover", "-s", file.path(repo_root, "tests"), "-v"))
)

steps <- if (assemble_only) assembly_steps else c(base_steps, direct_steps, chained_steps, purification_steps, joint_steps, post_estimation_steps, assembly_steps)
manifest_rows <- list()
for (index in seq_along(steps)) {
  this <- steps[[index]]
  log_path <- file.path(log_dir, paste0(sprintf("%02d", index), "_", this$id, ".log"))
  started <- Sys.time()
  message(sprintf("[%d/%d] %s", index, length(steps), this$id))
  command_text <- paste(shQuote(this$executable), paste(shQuote(this$arguments), collapse = " "))
  exit_status <- tryCatch(
    system2(this$executable, args = shQuote(this$arguments), stdout = log_path, stderr = log_path, timeout = this$timeout_seconds),
    error = function(error) structure(1L, error_message = conditionMessage(error))
  )
  exit_status <- if (is.null(exit_status)) 0L else as.integer(exit_status)
  ended <- Sys.time()
  manifest_rows[[index]] <- tibble(
    run_stamp = run_stamp, step_order = index, step_id = this$id, phase = this$phase,
    required = as.integer(this$required), started_utc = format(started, tz = "UTC", usetz = TRUE),
    ended_utc = format(ended, tz = "UTC", usetz = TRUE), elapsed_seconds = as.numeric(difftime(ended, started, units = "secs")),
    exit_status = exit_status, status = if_else(exit_status == 0L, "completed", "failed"),
    command = command_text, log_relative_path = file.path("logs", run_stamp, basename(log_path))
  )
  manifest <- bind_rows(manifest_rows)
  write_csv(manifest, file.path(pipeline_dir, "latest_pipeline_step_manifest.csv"), na = "")
  write_csv(manifest, file.path(pipeline_dir, paste0("pipeline_step_manifest_", run_stamp, ".csv")), na = "")
  if (!assemble_only) write_csv(manifest, latest_full_manifest_path, na = "")
  if (exit_status != 0L && this$required) {
    tail_lines <- if (file.exists(log_path)) tail(readLines(log_path, warn = FALSE), 30L) else "No log was produced."
    stop("Required step failed: ", this$id, "\n", paste(tail_lines, collapse = "\n"))
  }
  message(sprintf("      completed in %.1f seconds", as.numeric(difftime(ended, started, units = "secs"))))
}

final_manifest <- bind_rows(manifest_rows)
run_summary <- list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), run_stamp = run_stamp,
  mode = if (assemble_only) "assemble_only" else "full_measurement_build",
  step_n = nrow(final_manifest), failed_step_n = sum(final_manifest$exit_status != 0L),
  y1_reference_file_n = nrow(y1_reference_hashes), primary_method = specification$primary_method,
  code_fingerprint = code_fingerprint,
  treatment_regression_step_n = sum(grepl("treatment|regression|src/22", final_manifest$command, ignore.case = TRUE)),
  status = if (all(final_manifest$exit_status == 0L)) "completed" else "completed_with_nonrequired_failures"
)
writeLines(toJSON(run_summary, pretty = TRUE, auto_unbox = TRUE), file.path(pipeline_dir, "latest_pipeline_run_summary.json"))
writeLines(toJSON(run_summary, pretty = TRUE, auto_unbox = TRUE), file.path(pipeline_dir, paste0("pipeline_run_summary_", run_stamp, ".json")))
if (!assemble_only) writeLines(toJSON(run_summary, pretty = TRUE, auto_unbox = TRUE), latest_full_summary_path)
if (!assemble_only) {
  write_csv(code_manifest, file.path(pipeline_dir, "latest_full_pipeline_code_manifest.csv"), na = "")
  writeLines(code_fingerprint, file.path(pipeline_dir, "latest_full_pipeline_code_fingerprint.txt"))
}
cat(toJSON(run_summary, pretty = TRUE, auto_unbox = TRUE), "\n")
