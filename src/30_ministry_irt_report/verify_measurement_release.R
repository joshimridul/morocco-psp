#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(digest)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop("Usage: verify_measurement_release.R <repo_root> <paths.yml> <success_marker>")
}
repo_root <- normalizePath(args[[1]], mustWork = TRUE)
paths <- yaml::read_yaml(normalizePath(args[[2]], mustWork = TRUE))$dropbox
work_root <- normalizePath(paths$work_root, mustWork = TRUE)
pipeline_dir <- file.path(work_root, "outputs/y1_y3_irt/00_pipeline")

summary_path <- file.path(pipeline_dir, "latest_full_pipeline_run_summary.json")
manifest_path <- file.path(pipeline_dir, "latest_full_pipeline_step_manifest.csv")
code_path <- file.path(pipeline_dir, "latest_full_pipeline_code_manifest.csv")
expected <- c(summary_path, manifest_path, code_path)
if (!all(file.exists(expected))) {
  stop("A complete full measurement-build lineage record is required before regressions")
}

summary <- fromJSON(summary_path)
manifest <- read_csv(manifest_path, show_col_types = FALSE)
code <- read_csv(code_path, show_col_types = FALSE)
if (!identical(summary$mode, "full_measurement_build")) stop("Latest measurement build was not full")
if (summary$failed_step_n != 0L || any(manifest$exit_status != 0L)) stop("Latest full measurement build contains failed steps")
required_steps <- c("outcome_bundle", "measurement_correlations", "adversarial_validation", "unit_tests")
if (!all(required_steps %in% manifest$step_id)) stop("Latest full measurement build is incomplete")

current_paths <- file.path(repo_root, code$relative_path)
if (!all(file.exists(current_paths))) stop("A measurement source file recorded in lineage is missing")
current_hash <- map_chr(current_paths, ~ digest(.x, algo = "sha256", file = TRUE, serialize = FALSE))
if (!all(current_hash == code$sha256)) {
  changed <- code$relative_path[current_hash != code$sha256]
  stop("Measurement source changed after the latest full build: ", paste(changed, collapse = ", "))
}

validation <- fromJSON(file.path(
  work_root, "outputs/y1_y3_irt/08_adversarial_validation/adversarial_validation_summary.json"
))
if (validation$critical_fail_n != 0L) stop("Measurement adversarial validation has critical failures")

# The expected operational panel is known independently of the link graph.
# This prevents a mistakenly disconnected node from disappearing from both the
# outcome and the graph-based coverage check. Year 2 administered Grades 2--6;
# Year 3 administered Grades 1--6, at baseline and endline, in three subjects.
primary_path <- file.path(
  work_root, "derived/y1_y3_irt/multiyear_irt_outcomes_primary.csv"
)
primary <- read_csv(primary_path, show_col_types = FALSE)
observed_nodes <- unique(paste(
  primary$year, primary$wave, primary$subject, primary$administered_grade,
  sep = "|"
))
expected_nodes <- c(
  as.vector(outer(
    c("baseline", "endline"),
    as.vector(outer(c("Arabic", "French", "Maths"), 2:6, paste, sep = "|")),
    function(wave, subject_grade) paste(2, wave, subject_grade, sep = "|")
  )),
  as.vector(outer(
    c("baseline", "endline"),
    as.vector(outer(c("Arabic", "French", "Maths"), 1:6, paste, sep = "|")),
    function(wave, subject_grade) paste(3, wave, subject_grade, sep = "|")
  ))
)
if (length(observed_nodes) != 66L || !setequal(observed_nodes, expected_nodes)) {
  missing_nodes <- setdiff(expected_nodes, observed_nodes)
  stop(
    "Preferred outcome does not contain the complete 66-node operational panel; missing: ",
    paste(missing_nodes, collapse = ", ")
  )
}

arabic_lower <- primary[
  primary$year == 3L & primary$cohort == 3L & primary$subject == "Arabic" &
    primary$administered_grade %in% 1:2 & primary$wave %in% c("baseline", "endline"),
]
arabic_lower_cells <- unique(paste(
  arabic_lower$wave, arabic_lower$administered_grade, sep = "|"
))
if (!setequal(arabic_lower_cells, c("baseline|1", "endline|1", "baseline|2", "endline|2"))) {
  stop("Cohort 3 Arabic Grades 1--2 are not complete at baseline and endline")
}

# Record the exact panel-preparation, regression, QA, and report sources used by
# this run. This is separate from the frozen measurement-build manifest so that
# a prose or table-layout edit does not require re-estimating the IRT models.
regression_roots <- c(
  file.path(repo_root, "src/22_treatment_effects"),
  file.path(repo_root, "src/30_ministry_irt_report")
)
regression_files <- sort(unique(c(
  unlist(map(regression_roots, ~ list.files(.x, recursive = TRUE, full.names = TRUE))),
  file.path(repo_root, "config", c("analysis.yml", "irt_pipeline.yml"))
)))
regression_files <- regression_files[
  file.exists(regression_files) & !file.info(regression_files)$isdir &
    !grepl("/__pycache__/|\\.pyc$", regression_files)
]
regression_manifest <- tibble(
  relative_path = substring(regression_files, nchar(repo_root) + 2L),
  sha256 = map_chr(regression_files, ~ digest(.x, algo = "sha256", file = TRUE, serialize = FALSE))
)
regression_fingerprint <- digest(
  paste(regression_manifest$relative_path, regression_manifest$sha256, sep = "=", collapse = "\n"),
  algo = "sha256", serialize = FALSE
)
lineage_dir <- file.path(work_root, "outputs/y1_y3_irt/08_ministry_irt_report/logs")
dir.create(lineage_dir, recursive = TRUE, showWarnings = FALSE)
lineage_stamp <- format(Sys.time(), tz = "UTC", "%Y%m%dT%H%M%SZ")
write_csv(regression_manifest, file.path(lineage_dir, "latest_regression_code_manifest.csv"), na = "")
write_csv(regression_manifest, file.path(lineage_dir, paste0("regression_code_manifest_", lineage_stamp, ".csv")), na = "")
writeLines(toJSON(list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  measurement_run_stamp = summary$run_stamp,
  regression_code_fingerprint = regression_fingerprint,
  regression_source_file_n = nrow(regression_manifest)
), pretty = TRUE, auto_unbox = TRUE), file.path(lineage_dir, "latest_regression_lineage.json"))
writeLines(as.character(summary$run_stamp), args[[3]])
