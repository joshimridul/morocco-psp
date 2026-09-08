suppressPackageStartupMessages({
  library(dplyr)
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
output_dir <- file.path(output_root, "pilot_psychometrics")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

safe_var <- function(x) {
  if (length(x) <= 1L) {
    return(NA_real_)
  }
  stats::var(x)
}

safe_mean <- function(x) {
  if (length(x) == 0L || all(is.na(x))) {
    return(NA_real_)
  }
  mean(x, na.rm = TRUE)
}

safe_cor <- function(x, y) {
  if (length(x) <= 1L || length(y) <= 1L) {
    return(NA_real_)
  }
  if (isTRUE(all.equal(stats::sd(x), 0)) || isTRUE(all.equal(stats::sd(y), 0))) {
    return(NA_real_)
  }
  suppressWarnings(stats::cor(x, y))
}

scalar_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA_real_)
  }
  as.numeric(x[1])
}

first_or_default <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0L) {
    return(default)
  }
  x[1]
}

cronbach_alpha <- function(x) {
  if (ncol(x) < 2L || nrow(x) < 2L) {
    return(NA_real_)
  }
  item_vars <- apply(x, 2, safe_var)
  total_score <- rowSums(x)
  total_var <- safe_var(total_score)
  if (is.na(total_var) || total_var <= 0) {
    return(NA_real_)
  }
  k <- ncol(x)
  (k / (k - 1)) * (1 - sum(item_vars, na.rm = TRUE) / total_var)
}

item_label <- function(x) {
  lab <- attr(x, "label")
  if (is.null(lab)) {
    return("")
  }
  as.character(lab)
}

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

  converged <- FALSE
  converged <- tryCatch({
    isTRUE(extract.mirt(mod, "converged"))
  }, error = function(e) FALSE)

  params <- tryCatch({
    coef(mod, IRTpars = TRUE, simplify = TRUE)$items
  }, error = function(e) NULL)

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
    return(list(
      item_params = data.frame(),
      model_summary = data.frame(
        model_used = "not_fit",
        irt_items = ncol(x_irt),
        constant_items_excluded = length(constant_items),
        converged = FALSE,
        fit_reason = "fewer_than_3_nonconstant_items",
        logLik = NA_real_,
        AIC = NA_real_,
        BIC = NA_real_
      ),
      constant_items = constant_items
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
    model_used <- "2PL"
    mod <- fit_2pl
    fit_reason <- fit_2pl_status$reason
    converged <- fit_2pl_status$converged
  } else {
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
    model_used <- "1PL"
    mod <- fit_1pl
    fit_reason <- paste("2PL_failed:", fit_2pl_status$reason, "| 1PL:", fit_1pl_status$reason)
    converged <- fit_1pl_status$converged
  }

  if (inherits(mod, "try-error")) {
    return(list(
      item_params = data.frame(),
      model_summary = data.frame(
        model_used = model_used,
        irt_items = ncol(x_irt),
        constant_items_excluded = length(constant_items),
        converged = FALSE,
        fit_reason = fit_reason,
        logLik = NA_real_,
        AIC = NA_real_,
        BIC = NA_real_
      ),
      constant_items = constant_items
    ))
  }

  item_params <- tryCatch({
    params <- coef(mod, IRTpars = TRUE, simplify = TRUE)$items
    data.frame(
      item = rownames(params),
      irt_discrimination = unname(params[, "a"]),
      irt_difficulty = unname(params[, "b"]),
      stringsAsFactors = FALSE,
      row.names = NULL
    )
  }, error = function(e) data.frame())

  model_summary <- data.frame(
    model_used = first_or_default(model_used, "not_fit"),
    irt_items = ncol(x_irt),
    constant_items_excluded = length(constant_items),
    converged = isTRUE(converged),
    fit_reason = first_or_default(fit_reason, "unknown"),
    logLik = scalar_or_na(tryCatch(stats::logLik(mod), error = function(e) NA_real_)),
    AIC = scalar_or_na(tryCatch(AIC(mod), error = function(e) NA_real_)),
    BIC = scalar_or_na(tryCatch(BIC(mod), error = function(e) NA_real_)),
    stringsAsFactors = FALSE
  )

  list(
    item_params = item_params,
    model_summary = model_summary,
    constant_items = constant_items
  )
}

raw <- read_dta(input_path)

context_df <- data.frame(
  row_id = seq_len(nrow(raw)),
  id_student_panel = as.character(raw$id_student_panel),
  subject = as.character(as_factor(raw$subject)),
  grade = as.integer(raw$grade),
  treated = as.numeric(zap_labels(raw$treated)),
  school = as.character(raw$school),
  cd_etab = as.character(raw$cd_etab),
  duplicate_flag = as.numeric(zap_labels(raw$duplicate_flag)),
  duration_raw = as.character(raw$duration),
  duration_num = suppressWarnings(as.numeric(as.character(raw$duration))),
  stringsAsFactors = FALSE
)
context_df$duration_num[is.na(context_df$duration_num)] <- -Inf

item_like <- grep("^[maf][0-9]", names(raw), value = TRUE)
binary_items <- item_like[vapply(raw[item_like], binary_flag, logical(1))]
excluded_nonbinary_items <- setdiff(item_like, binary_items)

item_labels <- data.frame(
  item = binary_items,
  item_label = vapply(raw[binary_items], item_label, character(1)),
  stringsAsFactors = FALSE
)

item_obs <- lapply(raw[binary_items], function(x) as.numeric(zap_labels(x)))
item_obs <- as.data.frame(item_obs, check.names = FALSE)
item_obs_mat <- as.matrix(item_obs)

context_df$n_binary_nonmissing <- rowSums(!is.na(item_obs_mat))
context_df$binary_score_observed <- rowSums(ifelse(is.na(item_obs_mat), 0, item_obs_mat))

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
analysis_df$duplicate_group_size <- ave(dup_key, dup_key, FUN = length)
analysis_df$kept_after_dedup <- !duplicated(dup_key)

dedup_df <- analysis_df[analysis_df$kept_after_dedup, , drop = FALSE]
duplicate_resolution <- analysis_df[analysis_df$duplicate_group_size > 1, c(
  "row_id", "id_student_panel", "subject", "grade", "treated", "school", "cd_etab",
  "duplicate_flag", "duration_raw", "n_binary_nonmissing", "binary_score_observed",
  "kept_after_dedup"
)]

form_summaries <- list()
item_summaries <- list()
irt_summaries <- list()
anchor_pair_summaries <- list()
anchor_item_summaries <- list()

form_counter <- 0L
item_counter <- 0L
irt_counter <- 0L
anchor_pair_counter <- 0L
anchor_item_counter <- 0L

subjects <- sort(unique(dedup_df$subject))
grades <- sort(unique(dedup_df$grade))

for (subj in subjects) {
  for (gr in grades) {
    form_df <- dedup_df[dedup_df$subject == subj & dedup_df$grade == gr, , drop = FALSE]
    if (nrow(form_df) == 0L) {
      next
    }

    eligible_items <- binary_items[colSums(!is.na(form_df[, binary_items, drop = FALSE])) > 0]
    if (length(eligible_items) == 0L) {
      next
    }

    x_obs <- as.matrix(form_df[, eligible_items, drop = FALSE])
    x <- x_obs
    x[is.na(x)] <- 0

    treated_mask <- form_df$treated == 1
    control_mask <- form_df$treated == 0

    p_all <- colMeans(x)
    p_treated <- if (sum(treated_mask) > 0L) colMeans(x[treated_mask, , drop = FALSE]) else rep(NA_real_, ncol(x))
    p_control <- if (sum(control_mask) > 0L) colMeans(x[control_mask, , drop = FALSE]) else rep(NA_real_, ncol(x))

    obs_correct_all <- apply(x_obs, 2, safe_mean)
    obs_correct_treated <- if (sum(treated_mask) > 0L) apply(x_obs[treated_mask, , drop = FALSE], 2, safe_mean) else rep(NA_real_, ncol(x_obs))
    obs_correct_control <- if (sum(control_mask) > 0L) apply(x_obs[control_mask, , drop = FALSE], 2, safe_mean) else rep(NA_real_, ncol(x_obs))

    response_rate_all <- colMeans(!is.na(x_obs))
    response_rate_treated <- if (sum(treated_mask) > 0L) colMeans(!is.na(x_obs[treated_mask, , drop = FALSE])) else rep(NA_real_, ncol(x_obs))
    response_rate_control <- if (sum(control_mask) > 0L) colMeans(!is.na(x_obs[control_mask, , drop = FALSE])) else rep(NA_real_, ncol(x_obs))

    total_scores <- rowSums(x)
    corrected_item_total <- vapply(
      seq_len(ncol(x)),
      function(j) safe_cor(x[, j], total_scores - x[, j]),
      numeric(1)
    )

    ctt_flag_treated <- ifelse(
      p_treated >= 0.90, "very_easy",
      ifelse(p_treated <= 0.10, "very_hard", "in_range")
    )
    ctt_flag_all <- ifelse(
      p_all >= 0.90, "very_easy",
      ifelse(p_all <= 0.10, "very_hard", "in_range")
    )

    irt_fit <- fit_irt_model(x)
    irt_items <- irt_fit$item_params
    irt_summary <- irt_fit$model_summary

    if (nrow(irt_items) > 0L) {
      irt_items$form_subject <- subj
      irt_items$form_grade <- gr
      irt_items$irt_flag <- ifelse(
        irt_items$irt_difficulty <= -2, "very_easy",
        ifelse(irt_items$irt_difficulty >= 2, "very_hard", "in_range")
      )
      irt_counter <- irt_counter + 1L
      irt_summaries[[irt_counter]] <- irt_items
    }

    form_summary <- data.frame(
      subject = subj,
      grade = gr,
      n_students = nrow(form_df),
      n_treated = sum(treated_mask, na.rm = TRUE),
      n_control = sum(control_mask, na.rm = TRUE),
      n_binary_items = length(eligible_items),
      avg_response_rate = mean(response_rate_all, na.rm = TRUE),
      mean_pct_correct_all = mean(total_scores / length(eligible_items), na.rm = TRUE),
      mean_pct_correct_treated = if (sum(treated_mask) > 0L) mean(total_scores[treated_mask] / length(eligible_items), na.rm = TRUE) else NA_real_,
      mean_pct_correct_control = if (sum(control_mask) > 0L) mean(total_scores[control_mask] / length(eligible_items), na.rm = TRUE) else NA_real_,
      alpha = cronbach_alpha(x),
      ctt_very_easy_treated = sum(ctt_flag_treated == "very_easy", na.rm = TRUE),
      ctt_very_hard_treated = sum(ctt_flag_treated == "very_hard", na.rm = TRUE),
      ctt_very_easy_all = sum(ctt_flag_all == "very_easy", na.rm = TRUE),
      ctt_very_hard_all = sum(ctt_flag_all == "very_hard", na.rm = TRUE),
      irt_model_used = irt_summary$model_used[1],
      irt_items_fit = irt_summary$irt_items[1],
      irt_constant_items_excluded = irt_summary$constant_items_excluded[1],
      irt_converged = irt_summary$converged[1],
      irt_fit_reason = irt_summary$fit_reason[1],
      irt_logLik = irt_summary$logLik[1],
      irt_AIC = irt_summary$AIC[1],
      irt_BIC = irt_summary$BIC[1],
      stringsAsFactors = FALSE
    )

    form_counter <- form_counter + 1L
    form_summaries[[form_counter]] <- form_summary

    item_summary <- data.frame(
      subject = subj,
      grade = gr,
      item = eligible_items,
      p_all = unname(p_all),
      p_treated = unname(p_treated),
      p_control = unname(p_control),
      observed_correct_all = unname(obs_correct_all),
      observed_correct_treated = unname(obs_correct_treated),
      observed_correct_control = unname(obs_correct_control),
      response_rate_all = unname(response_rate_all),
      response_rate_treated = unname(response_rate_treated),
      response_rate_control = unname(response_rate_control),
      missing_rate_all = unname(1 - response_rate_all),
      corrected_item_total = unname(corrected_item_total),
      ctt_flag_treated = unname(ctt_flag_treated),
      ctt_flag_all = unname(ctt_flag_all),
      irt_constant_excluded = eligible_items %in% irt_fit$constant_items,
      stringsAsFactors = FALSE
    ) %>%
      left_join(item_labels, by = "item")

    item_counter <- item_counter + 1L
    item_summaries[[item_counter]] <- item_summary
  }
}

form_summary_df <- bind_rows(form_summaries) %>%
  arrange(subject, grade)

item_summary_df <- bind_rows(item_summaries) %>%
  arrange(subject, grade, item)

irt_summary_df <- bind_rows(irt_summaries) %>%
  left_join(item_labels, by = "item") %>%
  rename(subject = form_subject, grade = form_grade) %>%
  arrange(subject, grade, item)

item_summary_df <- item_summary_df %>%
  left_join(
    irt_summary_df %>%
      select(subject, grade, item, irt_discrimination, irt_difficulty, irt_flag),
    by = c("subject", "grade", "item")
  )

item_summary_df <- item_summary_df %>%
  mutate(
    treated_minus_control = p_treated - p_control,
    review_bucket = case_when(
      p_treated <= 0.15 & response_rate_all >= 0.75 ~ "hard_high_coverage",
      p_treated <= 0.15 & response_rate_all < 0.75 ~ "hard_low_coverage",
      p_treated >= 0.90 & response_rate_all >= 0.90 ~ "easy_high_coverage",
      p_treated >= 0.90 & response_rate_all < 0.90 ~ "easy_low_coverage",
      treated_minus_control <= -0.10 & response_rate_all >= 0.75 ~ "treated_below_control",
      TRUE ~ NA_character_
    )
  )

excluded_item_df <- data.frame(
  item = excluded_nonbinary_items,
  item_label = vapply(raw[excluded_nonbinary_items], item_label, character(1)),
  stringsAsFactors = FALSE
)

extreme_items_df <- item_summary_df %>%
  filter(ctt_flag_treated != "in_range" | (!is.na(irt_flag) & irt_flag != "in_range")) %>%
  arrange(subject, grade, desc(ctt_flag_treated), desc(irt_flag), p_treated)

priority_review_df <- item_summary_df %>%
  filter(!is.na(review_bucket)) %>%
  arrange(
    factor(
      review_bucket,
      levels = c(
        "hard_high_coverage",
        "hard_low_coverage",
        "treated_below_control",
        "easy_high_coverage",
        "easy_low_coverage"
      )
    ),
    p_treated,
    desc(response_rate_all)
  )

for (subj in subjects) {
  subj_items <- item_summary_df %>%
    filter(subject == subj)
  subj_grades <- sort(unique(subj_items$grade))

  if (length(subj_grades) < 2L) {
    next
  }

  for (j in seq_len(length(subj_grades) - 1L)) {
    g1 <- subj_grades[j]
    g2 <- subj_grades[j + 1L]

    left_df <- subj_items %>%
      filter(grade == g1) %>%
      select(
        item, item_label,
        p_treated_g1 = p_treated,
        p_control_g1 = p_control,
        response_rate_g1 = response_rate_all,
        corrected_item_total_g1 = corrected_item_total,
        irt_difficulty_g1 = irt_difficulty,
        irt_discrimination_g1 = irt_discrimination
      )
    right_df <- subj_items %>%
      filter(grade == g2) %>%
      select(
        item,
        p_treated_g2 = p_treated,
        p_control_g2 = p_control,
        response_rate_g2 = response_rate_all,
        corrected_item_total_g2 = corrected_item_total,
        irt_difficulty_g2 = irt_difficulty,
        irt_discrimination_g2 = irt_discrimination
      )

    shared_df <- inner_join(left_df, right_df, by = "item") %>%
      mutate(
        subject = subj,
        grade_pair = paste0("g", g1, "-g", g2),
        anchor_flag = case_when(
          response_rate_g1 >= 0.75 &
            response_rate_g2 >= 0.75 &
            p_treated_g1 >= 0.20 & p_treated_g1 <= 0.80 &
            p_treated_g2 >= 0.20 & p_treated_g2 <= 0.80 &
            corrected_item_total_g1 >= 0.15 &
            corrected_item_total_g2 >= 0.15 ~ "usable_anchor",
          response_rate_g1 < 0.75 | response_rate_g2 < 0.75 ~ "low_coverage_anchor",
          p_treated_g1 < 0.20 | p_treated_g1 > 0.80 | p_treated_g2 < 0.20 | p_treated_g2 > 0.80 ~ "extreme_anchor",
          corrected_item_total_g1 < 0.15 | corrected_item_total_g2 < 0.15 ~ "weak_discrimination_anchor",
          TRUE ~ "review_anchor"
        ),
        treated_p_swing = p_treated_g2 - p_treated_g1
      ) %>%
      arrange(item)

    anchor_pair_counter <- anchor_pair_counter + 1L
    anchor_pair_summaries[[anchor_pair_counter]] <- data.frame(
      subject = subj,
      grade_pair = paste0("g", g1, "-g", g2),
      shared_items = nrow(shared_df),
      usable_anchors = sum(shared_df$anchor_flag == "usable_anchor"),
      low_coverage_anchors = sum(shared_df$anchor_flag == "low_coverage_anchor"),
      extreme_anchors = sum(shared_df$anchor_flag == "extreme_anchor"),
      weak_discrimination_anchors = sum(shared_df$anchor_flag == "weak_discrimination_anchor"),
      review_anchors = sum(shared_df$anchor_flag == "review_anchor"),
      stringsAsFactors = FALSE
    )

    anchor_item_counter <- anchor_item_counter + 1L
    anchor_item_summaries[[anchor_item_counter]] <- shared_df
  }
}

anchor_pair_summary_df <- bind_rows(anchor_pair_summaries) %>%
  arrange(subject, grade_pair)

anchor_item_summary_df <- bind_rows(anchor_item_summaries) %>%
  arrange(subject, grade_pair, item)

write.csv(
  duplicate_resolution,
  file = file.path(output_dir, "pilot_duplicate_resolution.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  excluded_item_df,
  file = file.path(output_dir, "pilot_nonbinary_items_excluded.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  form_summary_df,
  file = file.path(output_dir, "pilot_form_summary.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  item_summary_df,
  file = file.path(output_dir, "pilot_item_summary.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  irt_summary_df,
  file = file.path(output_dir, "pilot_irt_item_summary.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  extreme_items_df,
  file = file.path(output_dir, "pilot_extreme_items.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  priority_review_df,
  file = file.path(output_dir, "pilot_priority_review.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  anchor_pair_summary_df,
  file = file.path(output_dir, "pilot_anchor_pair_summary.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  anchor_item_summary_df,
  file = file.path(output_dir, "pilot_anchor_item_summary.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

summary_path <- file.path(output_dir, "pilot_psychometrics_summary.md")
con <- file(summary_path, open = "wt", encoding = "UTF-8")

writeLines("# Pilot psychometrics review", con)
writeLines("", con)
writeLines(paste0("- Input file: `", input_path, "`"), con)
writeLines(paste0("- Records in raw file: ", nrow(raw)), con)
writeLines(paste0("- Records after deduplication: ", nrow(dedup_df)), con)
writeLines(paste0("- Duplicate rows removed: ", nrow(raw) - nrow(dedup_df)), con)
writeLines(paste0("- Binary scored items reviewed: ", length(binary_items)), con)
writeLines(paste0("- Non-binary item fields excluded from CTT/IRT: ", length(excluded_nonbinary_items)), con)
writeLines("- Primary easy/hard flag is based on the treated group (`p_treated`) so control underperformance does not drive the review.", con)
writeLines("- Missing responses are counted as incorrect for difficulty and IRT; observed-only correctness is shown alongside response rates to distinguish hard items from sparsely administered items.", con)
writeLines("", con)
writeLines("## Form lay of the land", con)
writeLines("", con)

for (i in seq_len(nrow(form_summary_df))) {
  row <- form_summary_df[i, ]
  line <- paste0(
    "- ", row$subject, " grade ", row$grade,
    ": N=", row$n_students,
    " (treated ", row$n_treated, ", control ", row$n_control, "), ",
    row$n_binary_items, " binary items, avg response rate ",
    sprintf("%.1f%%", 100 * row$avg_response_rate),
    ", treated mean score ",
    sprintf("%.1f%%", 100 * row$mean_pct_correct_treated),
    ", control mean score ",
    sprintf("%.1f%%", 100 * row$mean_pct_correct_control),
    ", alpha ", sprintf("%.2f", row$alpha),
    ", IRT model ", row$irt_model_used
  )
  writeLines(line, con)
}

writeLines("", con)
writeLines("## CTT easy and hard items", con)
writeLines("", con)

for (subj in subjects) {
  for (gr in grades) {
    form_items <- item_summary_df %>%
      filter(subject == subj, grade == gr)
    if (nrow(form_items) == 0L) {
      next
    }

    easy_items <- form_items %>%
      arrange(desc(p_treated), desc(observed_correct_treated), desc(response_rate_treated)) %>%
      slice_head(n = 3)
    hard_items <- form_items %>%
      arrange(p_treated, observed_correct_treated, response_rate_treated) %>%
      slice_head(n = 3)

    writeLines(paste0("### ", subj, " grade ", gr), con)
    writeLines("", con)
    writeLines("Most easy in treated schools:", con)
    for (i in seq_len(nrow(easy_items))) {
      row <- easy_items[i, ]
      writeLines(
        paste0(
          "- `", row$item, "`: treated p=", sprintf("%.3f", row$p_treated),
          ", control p=", sprintf("%.3f", row$p_control),
          ", response rate=", sprintf("%.1f%%", 100 * row$response_rate_all),
          ", observed-only treated correctness=", sprintf("%.1f%%", 100 * row$observed_correct_treated),
          ". ", row$item_label
        ),
        con
      )
    }
    writeLines("Most hard in treated schools:", con)
    for (i in seq_len(nrow(hard_items))) {
      row <- hard_items[i, ]
      writeLines(
        paste0(
          "- `", row$item, "`: treated p=", sprintf("%.3f", row$p_treated),
          ", control p=", sprintf("%.3f", row$p_control),
          ", response rate=", sprintf("%.1f%%", 100 * row$response_rate_all),
          ", observed-only treated correctness=", sprintf("%.1f%%", 100 * row$observed_correct_treated),
          ". ", row$item_label
        ),
        con
      )
    }
    writeLines("", con)
  }
}

writeLines("## IRT extreme items", con)
writeLines("", con)

for (subj in subjects) {
  for (gr in grades) {
    form_items <- item_summary_df %>%
      filter(subject == subj, grade == gr, !is.na(irt_difficulty))
    if (nrow(form_items) == 0L) {
      next
    }

    easy_items <- form_items %>%
      arrange(irt_difficulty, desc(irt_discrimination)) %>%
      slice_head(n = 3)
    hard_items <- form_items %>%
      arrange(desc(irt_difficulty), desc(irt_discrimination)) %>%
      slice_head(n = 3)
    model_used <- form_summary_df %>%
      filter(subject == subj, grade == gr) %>%
      pull(irt_model_used)
    fit_reason <- form_summary_df %>%
      filter(subject == subj, grade == gr) %>%
      pull(irt_fit_reason)

    writeLines(paste0("### ", subj, " grade ", gr, " (", model_used[1], ")"), con)
    writeLines(paste0("- Fit note: ", fit_reason[1]), con)
    writeLines("Most easy by IRT difficulty:", con)
    for (i in seq_len(nrow(easy_items))) {
      row <- easy_items[i, ]
      writeLines(
        paste0(
          "- `", row$item, "`: b=", sprintf("%.2f", row$irt_difficulty),
          ", a=", sprintf("%.2f", row$irt_discrimination),
          ", treated p=", sprintf("%.3f", row$p_treated),
          ". ", row$item_label
        ),
        con
      )
    }
    writeLines("Most hard by IRT difficulty:", con)
    for (i in seq_len(nrow(hard_items))) {
      row <- hard_items[i, ]
      writeLines(
        paste0(
          "- `", row$item, "`: b=", sprintf("%.2f", row$irt_difficulty),
          ", a=", sprintf("%.2f", row$irt_discrimination),
          ", treated p=", sprintf("%.3f", row$p_treated),
          ". ", row$item_label
        ),
        con
      )
    }
    writeLines("", con)
  }
}

writeLines("## Anchor review", con)
writeLines("", con)

for (i in seq_len(nrow(anchor_pair_summary_df))) {
  row <- anchor_pair_summary_df[i, ]
  writeLines(
    paste0(
      "- ", row$subject, " ", row$grade_pair,
      ": ", row$shared_items, " shared items, ",
      row$usable_anchors, " usable anchors, ",
      row$low_coverage_anchors, " low-coverage anchors, ",
      row$extreme_anchors, " extreme anchors, ",
      row$weak_discrimination_anchors, " weak-discrimination anchors."
    ),
    con
  )
}

close(con)

cat("Wrote outputs to:", output_dir, "\n")
