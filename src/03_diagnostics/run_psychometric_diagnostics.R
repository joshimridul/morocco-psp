#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(haven)
  library(mirt)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: run_psychometric_diagnostics.R config/paths.local.yml [form_limit]")
paths <- yaml::read_yaml(args[[1]])$dropbox
form_limit <- if (length(args) >= 2) as.integer(args[[2]]) else Inf
set.seed(20260804)

y3 <- paths$y3_root
work <- paths$work_root
files <- c(
  baseline = file.path(y3, "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta"),
  pilot = file.path(y3, "4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta"),
  endline = file.path(y3, "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta")
)
registry <- read_csv(file.path(work, "derived/y3_ministry/y3_item_version_registry.csv"), show_col_types = FALSE) %>%
  mutate(form_grade = as.character(form_grade))
operational <- read_csv(file.path(work, "derived/y3_ministry/y3_item_operational_stats.csv"), show_col_types = FALSE) %>%
  mutate(grade = as.character(grade))
form_scores <- read_csv(file.path(work, "derived/y3_ministry/y3_form_score_summary.csv"), show_col_types = FALSE) %>%
  mutate(grade = as.character(grade))
out_dir <- file.path(work, "outputs/y3_ministry/01_item_quality")
derived_dir <- file.path(work, "derived/y3_ministry")
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
  answered <- rowSums(sapply(form[item_vars], function(x) {
    tag <- haven::na_tag(x)
    !is.na(x) | (!is.na(tag) & tag == "a")
  }))
  duration_value <- if ("duration" %in% names(form)) suppressWarnings(as.numeric(form$duration)) else 0
  id_key <- as.character(form$id_student_panel)
  id_key[is.na(id_key) | id_key == ""] <- paste0("__row_", form$.source_row[is.na(id_key) | id_key == ""])
  form %>%
    mutate(.id_key = id_key, .answered = answered, .duration_value = duration_value) %>%
    arrange(.id_key, desc(.answered), desc(.duration_value), .source_row) %>%
    distinct(.id_key, .keep_all = TRUE) %>%
    arrange(.source_row) %>%
    select(-.id_key, -.answered, -.duration_value)
}

binary_matrix <- function(form, item_ids) {
  items <- intersect(item_ids, names(form))
  kinds <- map_lgl(items, function(item) {
    values <- unique(as.numeric(form[[item]][!is.na(form[[item]])]))
    all(values %in% c(0, 1))
  })
  items <- items[kinds]
  if (!length(items)) return(matrix(numeric(), nrow = nrow(form), ncol = 0))
  matrix <- sapply(form[items], function(x) {
    value <- suppressWarnings(as.numeric(x))
    scored <- rep(NA_real_, length(x))
    scored[!is.na(x)] <- as.numeric(value[!is.na(x)] == 1)
    tag <- haven::na_tag(x)
    scored[!is.na(tag) & tag == "a"] <- 0
    scored
  })
  if (length(items) == 1) matrix <- matrix(matrix, ncol = 1, dimnames = list(NULL, items))
  matrix
}

safe_value <- function(x, name) {
  if (is.null(x) || !name %in% names(x)) return(NA_real_)
  suppressWarnings(as.numeric(x[[name]][1]))
}

fit_mirt_model <- function(matrix, model_type) {
  itemtype <- if (model_type == "Rasch") "Rasch" else "2PL"
  result <- tryCatch(
    mirt(matrix, 1, itemtype = itemtype, verbose = FALSE, technical = list(NCYCLES = 1000)),
    error = function(e) e
  )
  if (inherits(result, "error")) return(list(model = NULL, error = conditionMessage(result)))
  list(model = result, error = "")
}

model_summary_row <- function(model, error, wave, subject, grade, model_type, n, k, primary) {
  if (is.null(model)) {
    return(tibble(
      wave = wave, subject = subject, grade = grade, model_type = model_type,
      primary_model = as.integer(primary), n = n, calibrated_item_n = k,
      converged = 0L, log_likelihood = NA_real_, AIC = NA_real_, BIC = NA_real_,
      M2 = NA_real_, M2_df = NA_real_, M2_p = NA_real_, RMSEA = NA_real_,
      RMSEA_5 = NA_real_, RMSEA_95 = NA_real_, SRMSR = NA_real_, CFI = NA_real_, TLI = NA_real_,
      error = error
    ))
  }
  fit <- tryCatch(M2(model, type = "C2"), error = function(e) NULL)
  tibble(
    wave = wave, subject = subject, grade = grade, model_type = model_type,
    primary_model = as.integer(primary), n = n, calibrated_item_n = k,
    converged = as.integer(isTRUE(extract.mirt(model, "converged"))),
    log_likelihood = as.numeric(extract.mirt(model, "logLik")),
    AIC = as.numeric(extract.mirt(model, "AIC")),
    BIC = as.numeric(extract.mirt(model, "BIC")),
    M2 = safe_value(fit, "M2"), M2_df = safe_value(fit, "df"), M2_p = safe_value(fit, "p"),
    RMSEA = safe_value(fit, "RMSEA"), RMSEA_5 = safe_value(fit, "RMSEA_5"),
    RMSEA_95 = safe_value(fit, "RMSEA_95"), SRMSR = safe_value(fit, "SRMSR"),
    CFI = safe_value(fit, "CFI"), TLI = safe_value(fit, "TLI"), error = error
  )
}

extract_item_parameters <- function(model, wave, subject, grade, model_type, primary) {
  if (is.null(model)) return(tibble())
  parameters <- as.data.frame(coef(model, IRTpars = TRUE, simplify = TRUE)$items)
  parameters$item_id <- rownames(parameters)
  fit <- tryCatch(itemfit(model, fit_stats = "S_X2", verbose = FALSE), error = function(e) NULL)
  if (!is.null(fit)) {
    fit <- as_tibble(fit) %>% rename(item_id = item)
    parameters <- left_join(parameters, fit, by = "item_id")
  }
  as_tibble(parameters) %>%
    transmute(
      wave = wave, subject = subject, grade = grade, model_type = model_type,
      primary_model = as.integer(primary), item_id,
      discrimination_a = if ("a" %in% names(.)) a else NA_real_,
      difficulty_b = if ("b" %in% names(.)) b else NA_real_,
      guessing_g = if ("g" %in% names(.)) g else NA_real_,
      upper_u = if ("u" %in% names(.)) u else NA_real_,
      S_X2 = if ("S_X2" %in% names(.)) S_X2 else NA_real_,
      S_X2_df = if ("df.S_X2" %in% names(.)) df.S_X2 else NA_real_,
      S_X2_RMSEA = if ("RMSEA.S_X2" %in% names(.)) RMSEA.S_X2 else NA_real_,
      S_X2_p = if ("p.S_X2" %in% names(.)) p.S_X2 else NA_real_
    ) %>%
    mutate(S_X2_p_holm = if_else(!is.na(S_X2_p), p.adjust(S_X2_p, method = "holm"), NA_real_))
}

extract_q3 <- function(model, response_matrix, wave, subject, grade) {
  if (is.null(model)) return(tibble())
  q3 <- tryCatch({
    theta <- fscores(model, method = "EAP", full.scores = TRUE)
    probability <- sapply(seq_len(ncol(response_matrix)), function(index) {
      trace <- probtrace(extract.item(model, index), theta)
      trace[, ncol(trace)]
    })
    colnames(probability) <- colnames(response_matrix)
    cor(response_matrix - probability)
  }, error = function(e) NULL)
  if (is.null(q3)) return(tibble())
  idx <- which(lower.tri(q3) & is.finite(q3), arr.ind = TRUE)
  if (!nrow(idx)) return(tibble())
  raw <- q3[idx]
  adjusted <- raw - mean(raw, na.rm = TRUE)
  tibble(
    wave = wave, subject = subject, grade = grade,
    item_id_1 = rownames(q3)[idx[, 1]], item_id_2 = colnames(q3)[idx[, 2]],
    q3_raw = raw, q3_adjusted = adjusted,
    local_dependence_warning = as.integer(abs(adjusted) >= 0.20)
  ) %>%
    arrange(desc(abs(q3_adjusted))) %>%
    mutate(pair_rank_within_form = row_number()) %>%
    filter(local_dependence_warning == 1 | pair_rank_within_form <= 10)
}

dimension_row <- function(matrix, wave, subject, grade) {
  p <- colMeans(matrix)
  usable <- matrix[, p > 0 & p < 1, drop = FALSE]
  if (ncol(usable) < 3) {
    return(tibble(wave = wave, subject = subject, grade = grade, n = nrow(matrix), item_n = ncol(matrix),
                  nondegenerate_item_n = ncol(usable), eigen1 = NA_real_, eigen2 = NA_real_, eigen3 = NA_real_,
                  eigen1_eigen2_ratio = NA_real_, first_eigen_variance_share = NA_real_,
                  random_first_eigen_95 = NA_real_, first_eigen_exceeds_parallel_95 = NA_integer_))
  }
  correlation <- suppressWarnings(cor(usable))
  correlation[!is.finite(correlation)] <- 0
  diag(correlation) <- 1
  values <- sort(eigen(correlation, symmetric = TRUE, only.values = TRUE)$values, decreasing = TRUE)
  random_first <- replicate(25, {
    shuffled <- apply(usable, 2, sample)
    rc <- suppressWarnings(cor(shuffled))
    rc[!is.finite(rc)] <- 0
    diag(rc) <- 1
    max(eigen(rc, symmetric = TRUE, only.values = TRUE)$values)
  })
  tibble(
    wave = wave, subject = subject, grade = grade, n = nrow(matrix), item_n = ncol(matrix),
    nondegenerate_item_n = ncol(usable), eigen1 = values[1], eigen2 = values[2], eigen3 = values[3],
    eigen1_eigen2_ratio = values[1] / values[2], first_eigen_variance_share = values[1] / sum(pmax(values, 0)),
    random_first_eigen_95 = as.numeric(quantile(random_first, 0.95)),
    first_eigen_exceeds_parallel_95 = as.integer(values[1] > quantile(random_first, 0.95))
  )
}

dimension_rows <- list()
model_rows <- list()
parameter_rows <- list()
q3_rows <- list()
split_rows <- list()
form_counter <- 0L

for (wave in names(files)) {
  data <- read_dta(files[[wave]])
  wave_registry <- registry %>% filter(.data$wave == .env$wave)
  forms <- wave_registry %>% distinct(subject, form_grade) %>% arrange(subject, as.numeric(form_grade))
  for (f in seq_len(nrow(forms))) {
    form_counter <- form_counter + 1L
    if (form_counter > form_limit) break
    subject_value <- forms$subject[f]
    grade_value <- forms$form_grade[f]
    message(sprintf("FORM %d: %s %s grade %s", form_counter, wave, subject_value, grade_value))
    map <- wave_registry %>% filter(subject == subject_value, form_grade == grade_value) %>% distinct(item_id, .keep_all = TRUE)
    form <- prepare_form(data, map)
    matrix <- binary_matrix(form, map$item_id)
    dimension_rows[[paste(wave, subject_value, grade_value)]] <- dimension_row(matrix, wave, subject_value, grade_value)

    p <- if (ncol(matrix)) colMeans(matrix) else numeric()
    eligible <- names(p)[p >= 0.005 & p <= 0.995]
    calibration <- matrix[, eligible, drop = FALSE]
    if (nrow(calibration) < 150 || ncol(calibration) < 10) {
      model_rows[[paste(wave, subject_value, grade_value, "notfit")]] <- model_summary_row(
        NULL, "Sample/item count below calibration minimum", wave, subject_value, grade_value,
        ifelse(wave == "pilot", "Rasch", "2PL"), nrow(calibration), ncol(calibration), TRUE
      )
      next
    }

    rasch_fit <- fit_mirt_model(calibration, "Rasch")
    two_fit <- if (wave != "pilot") fit_mirt_model(calibration, "2PL") else list(model = NULL, error = "Pilot 2PL not fit: sample too small for stable free discrimination estimates")
    use_two <- wave != "pilot" && !is.null(two_fit$model) && isTRUE(extract.mirt(two_fit$model, "converged"))
    primary_model <- if (use_two) two_fit$model else rasch_fit$model
    primary_type <- if (use_two) "2PL" else "Rasch"

    model_rows[[paste(wave, subject_value, grade_value, "Rasch")]] <- model_summary_row(
      rasch_fit$model, rasch_fit$error, wave, subject_value, grade_value, "Rasch",
      nrow(calibration), ncol(calibration), primary_type == "Rasch"
    )
    if (wave != "pilot") {
      model_rows[[paste(wave, subject_value, grade_value, "2PL")]] <- model_summary_row(
        two_fit$model, two_fit$error, wave, subject_value, grade_value, "2PL",
        nrow(calibration), ncol(calibration), primary_type == "2PL"
      )
    }
    parameter_rows[[paste(wave, subject_value, grade_value)]] <- extract_item_parameters(
      primary_model, wave, subject_value, grade_value, primary_type, TRUE
    )
    q3_rows[[paste(wave, subject_value, grade_value)]] <- extract_q3(
      primary_model, calibration, wave, subject_value, grade_value
    )

    if (wave == "endline" && !is.null(two_fit$model) && "school" %in% names(form)) {
      schools <- sort(unique(as.character(form$school)))
      split_lookup <- set_names(rep(c("A", "B"), length.out = length(schools)), schools)
      split <- unname(split_lookup[as.character(form$school)])
      split_parameters <- list()
      for (half in c("A", "B")) {
        half_matrix <- calibration[split == half, , drop = FALSE]
        half_fit <- if (nrow(half_matrix) >= 200) fit_mirt_model(half_matrix, "2PL") else list(model = NULL, error = "split n < 200")
        if (!is.null(half_fit$model) && isTRUE(extract.mirt(half_fit$model, "converged"))) {
          pars <- as.data.frame(coef(half_fit$model, IRTpars = TRUE, simplify = TRUE)$items)
          pars$item_id <- rownames(pars)
          split_parameters[[half]] <- as_tibble(pars) %>% select(item_id, a, b)
        }
      }
      if (length(split_parameters) == 2) {
        stability <- inner_join(split_parameters$A, split_parameters$B, by = "item_id", suffix = c("_A", "_B")) %>%
          mutate(
            wave = wave, subject = subject_value, grade = grade_value,
            log_discrimination_abs_difference = abs(log(a_A) - log(a_B)),
            difficulty_abs_difference = abs(b_A - b_B),
            split_stability_warning = as.integer(log_discrimination_abs_difference > log(2) | difficulty_abs_difference > 1)
          ) %>%
          select(wave, subject, grade, everything())
        split_rows[[paste(wave, subject_value, grade_value)]] <- stability
      }
    }
  }
  rm(data)
  invisible(gc())
  if (form_counter >= form_limit) break
}

dimensions <- bind_rows(dimension_rows)
models <- bind_rows(model_rows)
parameters <- bind_rows(parameter_rows)
q3_pairs <- bind_rows(q3_rows)
split_stability <- bind_rows(split_rows)

if (!nrow(q3_pairs)) {
  q3_pairs <- tibble(
    wave = character(), subject = character(), grade = character(),
    item_id_1 = character(), item_id_2 = character(), q3_raw = double(),
    q3_adjusted = double(), local_dependence_warning = integer(),
    pair_rank_within_form = integer()
  )
}
if (!nrow(split_stability)) {
  split_stability <- tibble(
    wave = character(), subject = character(), grade = character(), item_id = character(),
    a_A = double(), b_A = double(), a_B = double(), b_B = double(),
    log_discrimination_abs_difference = double(), difficulty_abs_difference = double(),
    split_stability_warning = integer()
  )
}

q3_item_flags <- bind_rows(
  q3_pairs %>% filter(local_dependence_warning == 1) %>% transmute(wave, subject, grade, item_id = item_id_1),
  q3_pairs %>% filter(local_dependence_warning == 1) %>% transmute(wave, subject, grade, item_id = item_id_2)
) %>% distinct() %>% mutate(local_dependence_item_warning = 1L)

split_flags <- if (nrow(split_stability)) {
  split_stability %>%
    group_by(wave, subject, grade, item_id) %>%
    summarize(
      split_stability_warning = max(split_stability_warning),
      split_log_a_difference = first(log_discrimination_abs_difference),
      split_b_difference = first(difficulty_abs_difference), .groups = "drop"
    )
} else {
  tibble(
    wave = character(), subject = character(), grade = character(), item_id = character(),
    split_stability_warning = integer(), split_log_a_difference = double(), split_b_difference = double()
  )
}

decision_evidence <- operational %>%
  filter(item_type == "binary") %>%
  left_join(form_scores %>% select(wave, subject, grade, form_alpha = cronbach_alpha_primary_noncorr_zero),
            by = c("wave", "subject", "grade")) %>%
  left_join(parameters %>% filter(primary_model == 1) %>% select(
    wave, subject, grade, item_id, irt_model_type = model_type, discrimination_a, difficulty_b,
    S_X2_RMSEA, S_X2_p, S_X2_p_holm
  ), by = c("wave", "subject", "grade", "item_id")) %>%
  left_join(q3_item_flags, by = c("wave", "subject", "grade", "item_id")) %>%
  left_join(split_flags, by = c("wave", "subject", "grade", "item_id")) %>%
  mutate(
    local_dependence_item_warning = coalesce(local_dependence_item_warning, 0L),
    split_stability_warning = coalesce(split_stability_warning, 0L),
    extreme_facility_warning = as.integer(pct_correct < 5 | pct_correct > 95),
    severe_facility_warning = as.integer(pct_correct < 1 | pct_correct > 99),
    low_discrimination_warning = as.integer(is.na(point_biserial_rest) | point_biserial_rest < 0.15),
    negative_discrimination_warning = as.integer(!is.na(point_biserial_rest) & point_biserial_rest < 0),
    nonresponse_warning = as.integer(pct_dont_know + pct_missing > 10),
    alpha_deletion_warning = as.integer(!is.na(alpha_if_deleted) & alpha_if_deleted > form_alpha + 0.01),
    irt_parameter_warning = as.integer(
      (!is.na(discrimination_a) & (discrimination_a < 0.5 | discrimination_a > 3.5)) |
        (!is.na(difficulty_b) & abs(difficulty_b) > 3)
    ),
    irt_item_fit_warning = as.integer(!is.na(S_X2_p_holm) & S_X2_p_holm < 0.01),
    empirical_warning_count = extreme_facility_warning + low_discrimination_warning +
      nonresponse_warning + alpha_deletion_warning + irt_parameter_warning +
      irt_item_fit_warning + local_dependence_item_warning + split_stability_warning,
    empirical_quality_status = case_when(
      severe_facility_warning == 1 | negative_discrimination_warning == 1 ~ "requires review",
      empirical_warning_count >= 2 ~ "multiple warnings",
      empirical_warning_count == 1 ~ "one warning",
      TRUE ~ "no empirical warning"
    ),
    substantive_necessity_status = "requires Ministry/content-specialist judgment",
    anchor_eligibility_status = "not determined by item quality alone"
  )

write_csv(dimensions, file.path(out_dir, "y3_form_dimensionality.csv"), na = "")
write_csv(models, file.path(out_dir, "y3_irt_model_summary.csv"), na = "")
write_csv(parameters, file.path(out_dir, "y3_irt_item_parameters.csv"), na = "")
write_csv(q3_pairs, file.path(out_dir, "y3_local_dependence_pairs.csv"), na = "")
write_csv(split_stability, file.path(out_dir, "y3_endline_school_split_stability.csv"), na = "")
write_csv(decision_evidence, file.path(derived_dir, "y3_item_decision_evidence.csv"), na = "")

summary <- list(
  treatment_fields_used = FALSE,
  form_diagnostics_n = nrow(dimensions),
  fitted_model_rows = nrow(models),
  converged_model_rows = sum(models$converged == 1),
  primary_item_parameter_rows = nrow(parameters),
  local_dependence_warning_pairs = sum(q3_pairs$local_dependence_warning == 1),
  school_split_item_rows = nrow(split_stability),
  school_split_warning_rows = sum(split_stability$split_stability_warning == 1),
  item_form_decision_rows = nrow(decision_evidence),
  empirical_status_counts = as.list(table(decision_evidence$empirical_quality_status)),
  threshold_policy = "All numerical thresholds are warning flags for review, never automatic keep/drop rules.",
  pilot_model_policy = "Pilot forms use Rasch fallback only because roughly 180-200 respondents per form do not support stable free discrimination estimates for 26-52 items.",
  baseline_endline_model_policy = "One-dimensional 2PL is primary when converged; Rasch is retained as a sensitivity comparison. Dimensionality, item-fit, and Q3 diagnostics govern interpretation."
)
writeLines(jsonlite::toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "y3_diagnostics_summary.json"))
cat(jsonlite::toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
