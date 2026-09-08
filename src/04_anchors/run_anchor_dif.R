#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(haven)
  library(lmtest)
  library(purrr)
  library(readr)
  library(sandwich)
  library(stringr)
  library(tibble)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: run_anchor_dif.R config/paths.local.yml")
paths <- yaml::read_yaml(args[[1]])$dropbox
set.seed(20260804)
y3 <- paths$y3_root
work <- paths$work_root

files <- c(
  baseline = file.path(y3, "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta"),
  endline = file.path(y3, "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta")
)
registry <- read_csv(file.path(work, "derived/y3_ministry/y3_item_version_registry.csv"), show_col_types = FALSE) %>%
  mutate(form_grade = as.character(form_grade))
evidence <- read_csv(file.path(work, "derived/y3_ministry/y3_item_decision_evidence.csv"), show_col_types = FALSE) %>%
  mutate(grade = as.character(grade))
parameters <- read_csv(file.path(work, "outputs/y3_ministry/01_item_quality/y3_irt_item_parameters.csv"), show_col_types = FALSE) %>%
  filter(primary_model == 1) %>% mutate(grade = as.character(grade))
out_dir <- file.path(work, "outputs/y3_ministry/02_anchors")
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
  if (!nrow(form)) return(form)
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

binary_matrix <- function(form, items) {
  items <- intersect(items, names(form))
  binary <- map_lgl(items, function(item) {
    values <- unique(as.numeric(form[[item]][!is.na(form[[item]])]))
    all(values %in% c(0, 1))
  })
  items <- items[binary]
  if (!length(items)) return(matrix(numeric(), nrow = nrow(form), ncol = 0))
  matrix <- sapply(form[items], function(x) as.numeric(!is.na(x) & as.numeric(x) == 1))
  if (length(items) == 1) matrix <- matrix(matrix, ncol = 1, dimnames = list(NULL, items))
  matrix
}

form_cache <- list()
for (wave in names(files)) {
  message("Preparing treatment-blind ", wave, " form cache")
  data <- read_dta(files[[wave]]) %>% select(-any_of(c("treated", "treatment", "p_treated")))
  wave_map <- registry %>% filter(.data$wave == .env$wave)
  forms <- wave_map %>% distinct(subject, form_grade)
  for (f in seq_len(nrow(forms))) {
    subject_value <- forms$subject[f]
    grade_value <- forms$form_grade[f]
    map <- wave_map %>% filter(subject == subject_value, form_grade == grade_value) %>% distinct(item_id, .keep_all = TRUE)
    form_cache[[paste(wave, subject_value, grade_value, sep = "|")]] <- prepare_form(data, map)
  }
  rm(data)
  invisible(gc())
}

endpoint_evidence <- function(wave, subject, grade, items, suffix) {
  result <- evidence %>%
    filter(.data$wave == .env$wave, .data$subject == .env$subject, .data$grade == .env$grade, item_id %in% items) %>%
    select(
      item_id, pct_correct, point_biserial_rest, empirical_quality_status,
      negative_discrimination_warning, severe_facility_warning, extreme_facility_warning,
      irt_item_fit_warning, local_dependence_item_warning, split_stability_warning
    )
  names(result)[-1] <- paste0(names(result)[-1], suffix)
  result
}

endpoint_parameters <- function(wave, subject, grade, items, suffix) {
  result <- parameters %>%
    filter(.data$wave == .env$wave, .data$subject == .env$subject, .data$grade == .env$grade, item_id %in% items) %>%
    select(item_id, model_type, discrimination_a, difficulty_b)
  names(result)[-1] <- paste0(names(result)[-1], suffix)
  result
}

dif_for_item <- function(y, rest, group, cluster) {
  rest_z <- as.numeric(scale(rest))
  if (!is.finite(sd(rest_z)) || length(unique(y)) < 2) {
    return(tibble(
      beta_uniform = NA_real_, uniform_or = NA_real_, uniform_se_cluster = NA_real_, uniform_p_cluster = NA_real_,
      beta_nonuniform = NA_real_, nonuniform_or = NA_real_, nonuniform_se_cluster = NA_real_,
      nonuniform_p_cluster = NA_real_, incremental_pseudo_r2 = NA_real_, model_warning = "degenerate response or conditioning score"
    ))
  }
  frame <- tibble(y = y, rest_z = rest_z, group = factor(group, levels = c("A", "B")), cluster = cluster)
  base <- tryCatch(glm(y ~ rest_z, data = frame, family = binomial()), error = function(e) NULL)
  full <- tryCatch(suppressWarnings(glm(y ~ rest_z * group, data = frame, family = binomial())), error = function(e) NULL)
  if (is.null(base) || is.null(full)) {
    return(tibble(
      beta_uniform = NA_real_, uniform_or = NA_real_, uniform_se_cluster = NA_real_, uniform_p_cluster = NA_real_,
      beta_nonuniform = NA_real_, nonuniform_or = NA_real_, nonuniform_se_cluster = NA_real_,
      nonuniform_p_cluster = NA_real_, incremental_pseudo_r2 = NA_real_, model_warning = "logistic model failed"
    ))
  }
  robust <- tryCatch(coeftest(full, vcov. = vcovCL(full, cluster = frame$cluster, type = "HC1")), error = function(e) NULL)
  uniform_name <- "groupB"
  interaction_name <- "rest_z:groupB"
  get_coef <- function(name, column) {
    if (is.null(robust) || !name %in% rownames(robust)) return(NA_real_)
    as.numeric(robust[name, column])
  }
  beta_u <- get_coef(uniform_name, 1)
  beta_n <- get_coef(interaction_name, 1)
  increment <- as.numeric((logLik(full) - logLik(base)) / abs(logLik(base)))
  tibble(
    beta_uniform = beta_u, uniform_or = exp(beta_u),
    uniform_se_cluster = get_coef(uniform_name, 2), uniform_p_cluster = get_coef(uniform_name, 4),
    beta_nonuniform = beta_n, nonuniform_or = exp(beta_n),
    nonuniform_se_cluster = get_coef(interaction_name, 2), nonuniform_p_cluster = get_coef(interaction_name, 4),
    incremental_pseudo_r2 = increment,
    model_warning = ifelse(any(abs(coef(full)) > 10), "possible separation", "")
  )
}

analyze_link <- function(link_type, link_id, subject, grade_a, grade_b, wave_a, wave_b, items, version_table) {
  key_a <- paste(wave_a, subject, grade_a, sep = "|")
  key_b <- paste(wave_b, subject, grade_b, sep = "|")
  form_a <- form_cache[[key_a]]
  form_b <- form_cache[[key_b]]
  matrix_a <- binary_matrix(form_a, items)
  matrix_b <- binary_matrix(form_b, items)
  common <- intersect(colnames(matrix_a), colnames(matrix_b))
  if (length(common) < 5) return(tibble())
  matrix_a <- matrix_a[, common, drop = FALSE]
  matrix_b <- matrix_b[, common, drop = FALSE]
  pooled <- rbind(matrix_a, matrix_b)
  group <- c(rep("A", nrow(matrix_a)), rep("B", nrow(matrix_b)))
  cluster <- c(as.character(form_a$school), as.character(form_b$school))
  total <- rowSums(pooled)
  rows <- map_dfr(common, function(item) {
    y <- pooled[, item]
    rest <- total - y
    dif <- dif_for_item(y, rest, group, cluster)
    bind_cols(tibble(
      link_type = link_type, link_id = link_id, subject = subject,
      wave_a = wave_a, grade_a = grade_a, wave_b = wave_b, grade_b = grade_b,
      item_id = item, n_a = nrow(matrix_a), n_b = nrow(matrix_b), common_item_n = length(common),
      p_correct_a = mean(matrix_a[, item]), p_correct_b = mean(matrix_b[, item]),
      unconditional_p_difference = mean(matrix_b[, item]) - mean(matrix_a[, item])
    ), dif)
  })
  rows %>%
    left_join(version_table %>% filter(item_id %in% common), by = "item_id") %>%
    left_join(endpoint_evidence(wave_a, subject, grade_a, common, "_a"), by = "item_id") %>%
    left_join(endpoint_evidence(wave_b, subject, grade_b, common, "_b"), by = "item_id") %>%
    left_join(endpoint_parameters(wave_a, subject, grade_a, common, "_a"), by = "item_id") %>%
    left_join(endpoint_parameters(wave_b, subject, grade_b, common, "_b"), by = "item_id")
}

link_rows <- list()

for (subject_value in c("Arabic", "French", "Maths")) {
  for (grade_value in as.character(1:6)) {
    a <- registry %>% filter(wave == "baseline", subject == subject_value, form_grade == grade_value) %>% distinct(item_id, .keep_all = TRUE)
    b <- registry %>% filter(wave == "endline", subject == subject_value, form_grade == grade_value) %>% distinct(item_id, .keep_all = TRUE)
    version <- inner_join(
      a %>% select(item_id, prompt_hash_a = prompt_summary_sha256, fingerprint_a = provisional_version_fingerprint),
      b %>% select(item_id, prompt_hash_b = prompt_summary_sha256, fingerprint_b = provisional_version_fingerprint),
      by = "item_id"
    ) %>% mutate(prompt_hash_consistent = as.integer(prompt_hash_a != "" & prompt_hash_a == prompt_hash_b))
    link_id <- paste("within_grade_pre_post", subject_value, grade_value, sep = "|")
    message(link_id)
    link_rows[[link_id]] <- analyze_link(
      "within_grade_pre_post", link_id, subject_value, grade_value, grade_value,
      "baseline", "endline", version$item_id, version
    )
  }
  for (lower in 1:5) {
    upper <- lower + 1
    a <- registry %>% filter(wave == "endline", subject == subject_value, form_grade == as.character(lower)) %>% distinct(item_id, .keep_all = TRUE)
    b <- registry %>% filter(wave == "endline", subject == subject_value, form_grade == as.character(upper)) %>% distinct(item_id, .keep_all = TRUE)
    version <- inner_join(
      a %>% select(item_id, prompt_hash_a = prompt_summary_sha256, fingerprint_a = provisional_version_fingerprint),
      b %>% select(item_id, prompt_hash_b = prompt_summary_sha256, fingerprint_b = provisional_version_fingerprint),
      by = "item_id"
    ) %>% mutate(prompt_hash_consistent = as.integer(prompt_hash_a != "" & prompt_hash_a == prompt_hash_b))
    link_id <- paste("adjacent_grade_vertical", subject_value, paste0(lower, "-", upper), sep = "|")
    message(link_id)
    link_rows[[link_id]] <- analyze_link(
      "adjacent_grade_vertical", link_id, subject_value, as.character(lower), as.character(upper),
      "endline", "endline", version$item_id, version
    )
  }
}

anchor_results <- bind_rows(link_rows) %>%
  group_by(link_id) %>%
  mutate(
    uniform_p_holm = if_else(!is.na(uniform_p_cluster), p.adjust(uniform_p_cluster, method = "holm"), NA_real_),
    nonuniform_p_holm = if_else(!is.na(nonuniform_p_cluster), p.adjust(nonuniform_p_cluster, method = "holm"), NA_real_)
  ) %>% ungroup() %>%
  mutate(
    version_warning = as.integer(is.na(prompt_hash_consistent) | prompt_hash_consistent != 1),
    dif_warning = as.integer(
      is.na(uniform_or) | uniform_or < 0.67 | uniform_or > 1.50 |
        is.na(beta_nonuniform) | abs(beta_nonuniform) > 0.50 |
        is.na(incremental_pseudo_r2) | incremental_pseudo_r2 > 0.02 |
        (!is.na(uniform_p_holm) & uniform_p_holm < 0.01) |
        (!is.na(nonuniform_p_holm) & nonuniform_p_holm < 0.01)
    ),
    endpoint_quality_failure = as.integer(
      negative_discrimination_warning_a == 1 | negative_discrimination_warning_b == 1 |
        severe_facility_warning_a == 1 | severe_facility_warning_b == 1 |
        point_biserial_rest_a < 0.15 | point_biserial_rest_b < 0.15
    ),
    strong_quality = as.integer(
      point_biserial_rest_a >= 0.25 & point_biserial_rest_b >= 0.25 &
        pct_correct_a >= 10 & pct_correct_a <= 90 & pct_correct_b >= 10 & pct_correct_b <= 90 &
        irt_item_fit_warning_a == 0 & irt_item_fit_warning_b == 0 &
        split_stability_warning_b == 0
    ),
    adequate_quality = as.integer(
      point_biserial_rest_a >= 0.15 & point_biserial_rest_b >= 0.15 &
        pct_correct_a >= 5 & pct_correct_a <= 95 & pct_correct_b >= 5 & pct_correct_b <= 95
    ),
    anchor_candidate_tier = case_when(
      version_warning == 1 ~ "not eligible: prompt-summary mismatch",
      dif_warning == 1 | endpoint_quality_failure == 1 ~ "not eligible empirically",
      strong_quality == 1 ~ "Tier A core candidate",
      adequate_quality == 1 ~ "Tier B expanded candidate",
      TRUE ~ "reserve: requires review"
    ),
    full_version_review_status = "required before operational anchor use",
    exposure_review_status = "required before operational anchor use",
    treatment_used_for_selection = 0L
  )

sensitivity_rows <- list()
for (link in unique(anchor_results$link_id)) {
  link_data <- anchor_results %>% filter(link_id == link)
  sets <- list(
    core = link_data %>% filter(anchor_candidate_tier == "Tier A core candidate"),
    expanded = link_data %>% filter(anchor_candidate_tier %in% c("Tier A core candidate", "Tier B expanded candidate")),
    all_empirically_eligible = link_data %>% filter(!str_starts(anchor_candidate_tier, "not eligible"))
  )
  for (set_name in names(sets)) {
    set <- sets[[set_name]] %>% filter(!is.na(difficulty_b_a), !is.na(difficulty_b_b))
    if (nrow(set) >= 3 && sd(set$difficulty_b_b) > 0) {
      slope <- sd(set$difficulty_b_a) / sd(set$difficulty_b_b)
      intercept <- mean(set$difficulty_b_a) - slope * mean(set$difficulty_b_b)
      residual <- set$difficulty_b_a - (slope * set$difficulty_b_b + intercept)
      sensitivity_rows[[paste(link, set_name)]] <- tibble(
        link_type = first(set$link_type), link_id = link, anchor_set = set_name,
        anchor_n = nrow(set), mean_sigma_slope_b_to_a = slope, mean_sigma_intercept_b_to_a = intercept,
        difficulty_correlation = cor(set$difficulty_b_a, set$difficulty_b_b),
        difficulty_link_rmse = sqrt(mean(residual^2)),
        discrimination_correlation = suppressWarnings(cor(set$discrimination_a_a, set$discrimination_a_b)),
        mixed_model_type_warning = as.integer(length(unique(c(set$model_type_a, set$model_type_b))) > 1)
      )
    } else {
      sensitivity_rows[[paste(link, set_name)]] <- tibble(
        link_type = first(link_data$link_type), link_id = link, anchor_set = set_name,
        anchor_n = nrow(set), mean_sigma_slope_b_to_a = NA_real_, mean_sigma_intercept_b_to_a = NA_real_,
        difficulty_correlation = NA_real_, difficulty_link_rmse = NA_real_,
        discrimination_correlation = NA_real_, mixed_model_type_warning = NA_integer_
      )
    }
  }
}
sensitivity <- bind_rows(sensitivity_rows)
set_summary <- anchor_results %>% count(link_type, link_id, subject, grade_a, grade_b, anchor_candidate_tier, name = "item_n")

expected_links <- bind_rows(lapply(c("Arabic", "French", "Maths"), function(subject_value) {
  bind_rows(
    tibble(
      link_type = "within_grade_pre_post",
      link_id = paste("within_grade_pre_post", subject_value, 1:6, sep = "|"),
      subject = subject_value, grade_a = as.character(1:6), grade_b = as.character(1:6)
    ),
    tibble(
      link_type = "adjacent_grade_vertical",
      link_id = paste("adjacent_grade_vertical", subject_value, paste0(1:5, "-", 2:6), sep = "|"),
      subject = subject_value, grade_a = as.character(1:5), grade_b = as.character(2:6)
    )
  )
}))
coverage <- anchor_results %>%
  group_by(link_type, link_id, subject, grade_a, grade_b) %>%
  summarize(
    common_binary_item_n = n(),
    tier_a_n = sum(anchor_candidate_tier == "Tier A core candidate"),
    tier_b_n = sum(anchor_candidate_tier == "Tier B expanded candidate"),
    reserve_n = sum(anchor_candidate_tier == "reserve: requires review"),
    empirically_ineligible_n = sum(str_starts(anchor_candidate_tier, "not eligible")),
    .groups = "drop"
  ) %>%
  right_join(expected_links, by = c("link_type", "link_id", "subject", "grade_a", "grade_b")) %>%
  mutate(
    across(c(common_binary_item_n, tier_a_n, tier_b_n, reserve_n, empirically_ineligible_n), ~ coalesce(.x, 0L)),
    preliminary_coverage_status = case_when(
      common_binary_item_n == 0 ~ "no common binary items",
      tier_a_n + tier_b_n == 0 ~ "no empirically eligible candidate",
      tier_a_n + tier_b_n < 5 ~ "fewer than 5 core/expanded candidates",
      TRUE ~ "at least 5 core/expanded candidates"
    )
  ) %>% arrange(link_type, subject, as.numeric(grade_a))

write_csv(anchor_results, file.path(derived_dir, "y3_anchor_candidate_evidence.csv"), na = "")
write_csv(set_summary, file.path(out_dir, "y3_anchor_candidate_counts.csv"), na = "")
write_csv(sensitivity, file.path(out_dir, "y3_anchor_set_sensitivity.csv"), na = "")
write_csv(coverage, file.path(out_dir, "y3_anchor_link_coverage.csv"), na = "")

summary <- list(
  treatment_fields_used = FALSE,
  required_link_count = nrow(expected_links),
  estimable_link_count = length(unique(anchor_results$link_id)),
  within_grade_pre_post_link_count = length(unique(anchor_results$link_id[anchor_results$link_type == "within_grade_pre_post"])),
  adjacent_grade_link_count = length(unique(anchor_results$link_id[anchor_results$link_type == "adjacent_grade_vertical"])),
  item_link_rows = nrow(anchor_results),
  candidate_tier_counts = as.list(table(anchor_results$anchor_candidate_tier)),
  coverage_status_counts = as.list(table(coverage$preliminary_coverage_status)),
  sensitivity_rows = nrow(sensitivity),
  anchor_rule = "Candidates require prompt-summary consistency, acceptable endpoint behavior, and no material uniform/nonuniform DIF warning. Full prompt/stimulus/options/key/rubric/layout/scoring/exposure review remains mandatory.",
  dif_rule = "Logistic DIF conditions on the common-item rest score and uses school-clustered standard errors. Odds ratios, interaction size, incremental pseudo-R2 relative to the reduced item model, and Holm-adjusted p-values are warning evidence, not automatic decisions."
)
writeLines(jsonlite::toJSON(summary, pretty = TRUE, auto_unbox = TRUE), file.path(out_dir, "y3_anchor_summary.json"))
cat(jsonlite::toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
