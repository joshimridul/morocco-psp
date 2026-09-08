#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(yaml))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: config_to_stata.R <paths.yml> <output.do>")
work_root <- normalizePath(
  yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox$work_root,
  mustWork = TRUE
)
escaped <- gsub("\"", "\"\"", work_root, fixed = TRUE)
output_root <- file.path(work_root, "outputs/y1_y3_irt/08_ministry_irt_report")
for (directory in c(output_root, file.path(output_root, c("estimates", "tables", "logs", "qa")))) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(directory)) stop("Could not create output directory: ", directory)
}
writeLines(sprintf("global WORK `\"%s\"'", escaped), args[[2]])
