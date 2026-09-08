suppressPackageStartupMessages({
  library(haven)
  library(mirt)
})

project_root <- Sys.getenv("PROJECT_ROOT", unset = "/Users/mriduljoshi/Github/morocco-psp")
output_root <- Sys.getenv("PILOT_OUTPUT_ROOT")
if (!nzchar(output_root)) stop("PILOT_OUTPUT_ROOT must be set by run_pilot_pipeline.py")
input_path <- Sys.getenv(
  "PILOT_DATA_PATH",
  unset = "/Users/mriduljoshi/Dropbox/DID - Morocco Pioneer Schools Year 3/4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta"
)
report_dir <- file.path(output_root, "pilot_reports")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

binary_flag <- function(x) {
  vals <- unique(as.numeric(zap_labels(x)))
  vals <- vals[!is.na(vals)]
  length(vals) > 0L && all(vals %in% c(0, 1))
}

model_status <- function(mod, itemtype) {
  out <- list(ok = FALSE, converged = FALSE, reason = "not_fit")
  if (inherits(mod, "try-error") || is.null(mod)) {
    out$reason <- "estimation_error"
    return(out)
  }

  converged <- tryCatch(isTRUE(extract.mirt(mod, "converged")), error = function(e) FALSE)
  params <- tryCatch(coef(mod, IRTpars = TRUE, simplify = TRUE)$items, error = function(e) NULL)
  if (is.null(params)) {
    out$reason <- "parameter_extraction_error"
    return(out)
  }

  a_ok <- TRUE
  if ("a" %in% colnames(params)) {
    a_ok <- all(is.finite(params[, "a"])) &&
      all(params[, "a"] > 0.05) &&
      all(params[, "a"] < 5)
  }
  b_ok <- "b" %in% colnames(params) &&
    all(is.finite(params[, "b"])) &&
    all(abs(params[, "b"]) < 8)

  out$converged <- converged
  out$ok <- converged && a_ok && b_ok
  out$reason <- if (out$ok) {
    "ok"
  } else if (!converged) {
    "not_converged"
  } else if (!a_ok) {
    paste0(itemtype, "_bad_discrimination")
  } else {
    paste0(itemtype, "_bad_difficulty")
  }
  out
}

fit_irt_model <- function(x) {
  varying <- apply(x, 2, function(col) length(unique(col)) > 1L)
  constant_items <- colnames(x)[!varying]
  x_irt <- x[, varying, drop = FALSE]

  if (ncol(x_irt) < 3L) {
    return(data.frame(
      irt_model_used_refit = "not_fit",
      irt_items_fit_refit = ncol(x_irt),
      irt_constant_items_excluded_refit = length(constant_items),
      irt_converged_refit = FALSE,
      irt_fit_reason_refit = "fewer_than_3_nonconstant_items",
      stringsAsFactors = FALSE
    ))
  }

  fit_2pl <- try(
    mirt(
      data = as.data.frame(x_irt),
      model = 1,
      itemtype = "2PL",
      verbose = FALSE,
      SE = FALSE,
      technical = list(NCYCLES = 1500)
    ),
    silent = TRUE
  )
  fit_2pl_status <- model_status(fit_2pl, "2PL")

  if (fit_2pl_status$ok) {
    return(data.frame(
      irt_model_used_refit = "2PL",
      irt_items_fit_refit = ncol(x_irt),
      irt_constant_items_excluded_refit = length(constant_items),
      irt_converged_refit = fit_2pl_status$converged,
      irt_fit_reason_refit = fit_2pl_status$reason,
      stringsAsFactors = FALSE
    ))
  }

  fit_1pl <- try(
    mirt(
      data = as.data.frame(x_irt),
      model = 1,
      itemtype = "Rasch",
      verbose = FALSE,
      SE = FALSE,
      technical = list(NCYCLES = 1500)
    ),
    silent = TRUE
  )
  fit_1pl_status <- model_status(fit_1pl, "1PL")

  data.frame(
    irt_model_used_refit = "1PL",
    irt_items_fit_refit = ncol(x_irt),
    irt_constant_items_excluded_refit = length(constant_items),
    irt_converged_refit = fit_1pl_status$converged,
    irt_fit_reason_refit = paste0(
      "2PL_failed: ",
      fit_2pl_status$reason,
      " | 1PL: ",
      fit_1pl_status$reason
    ),
    stringsAsFactors = FALSE
  )
}

raw <- read_dta(input_path)
item_like <- grep("^[maf][0-9]", names(raw), value = TRUE)
binary_items <- item_like[vapply(raw[item_like], binary_flag, logical(1))]

context_df <- data.frame(
  row_id = seq_len(nrow(raw)),
  id_student_panel = as.character(raw$id_student_panel),
  subject = as.character(as_factor(raw$subject)),
  grade = as.integer(raw$grade),
  duration_num = suppressWarnings(as.numeric(as.character(raw$duration))),
  stringsAsFactors = FALSE
)
context_df$duration_num[is.na(context_df$duration_num)] <- -Inf

item_obs <- as.data.frame(lapply(raw[binary_items], function(x) as.numeric(zap_labels(x))), check.names = FALSE)
item_mat <- as.matrix(item_obs)
context_df$n_binary_nonmissing <- rowSums(!is.na(item_mat))
context_df$binary_score_observed <- rowSums(ifelse(is.na(item_mat), 0, item_mat))

analysis_df <- cbind(context_df, item_obs)
ord <- with(
  analysis_df,
  order(
    id_student_panel,
    subject,
    grade,
    -n_binary_nonmissing,
    -binary_score_observed,
    -duration_num,
    row_id
  )
)
analysis_df <- analysis_df[ord, , drop = FALSE]
dup_key <- paste(analysis_df$id_student_panel, analysis_df$subject, analysis_df$grade, sep = "||")
dedup_df <- analysis_df[!duplicated(dup_key), , drop = FALSE]

rows <- list()
counter <- 0L
for (subj in sort(unique(dedup_df$subject))) {
  for (gr in sort(unique(dedup_df$grade))) {
    form_df <- dedup_df[dedup_df$subject == subj & dedup_df$grade == gr, , drop = FALSE]
    if (nrow(form_df) == 0L) next
    eligible_items <- binary_items[colSums(!is.na(form_df[, binary_items, drop = FALSE])) > 0]
    if (length(eligible_items) == 0L) next
    x <- as.matrix(form_df[, eligible_items, drop = FALSE])
    x[is.na(x)] <- 0
    fit <- fit_irt_model(x)
    counter <- counter + 1L
    rows[[counter]] <- cbind(
      data.frame(subject = subj, grade = gr, stringsAsFactors = FALSE),
      fit
    )
  }
}

out <- do.call(rbind, rows)
write.csv(out, file.path(report_dir, "replication_irt_refit_summary.csv"), row.names = FALSE)
message("Wrote ", file.path(report_dir, "replication_irt_refit_summary.csv"))
