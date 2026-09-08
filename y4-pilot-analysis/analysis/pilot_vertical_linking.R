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
psych_dir <- file.path(output_root, "pilot_psychometrics")
output_dir <- file.path(output_root, "pilot_vertical_linking")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

min_final_anchors_per_edge <- 2L
max_negative_anchor_swing <- -0.10

binary_flag <- function(x) {
  vals <- unique(as.numeric(zap_labels(x)))
  vals <- vals[!is.na(vals)]
  length(vals) > 0L && all(vals %in% c(0, 1))
}

item_label <- function(x) {
  lab <- attr(x, "label")
  if (is.null(lab)) {
    return("")
  }
  as.character(lab)
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
    return(list(
      model = NULL,
      model_used = "not_fit",
      fit_reason = "fewer_than_3_nonconstant_items",
      converged = FALSE,
      x_irt = x_irt,
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
    return(list(
      model = fit_2pl,
      model_used = "2PL",
      fit_reason = fit_2pl_status$reason,
      converged = fit_2pl_status$converged,
      x_irt = x_irt,
      constant_items = constant_items
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

  list(
    model = if (inherits(fit_1pl, "try-error")) NULL else fit_1pl,
    model_used = "1PL",
    fit_reason = paste("2PL_failed:", fit_2pl_status$reason, "| 1PL:", fit_1pl_status$reason),
    converged = fit_1pl_status$converged,
    x_irt = x_irt,
    constant_items = constant_items
  )
}

find_components <- function(nodes, edges) {
  nodes <- unique(nodes)
  if (length(nodes) == 0L) {
    return(list())
  }
  adj <- setNames(vector("list", length(nodes)), as.character(nodes))
  for (nd in nodes) {
    adj[[as.character(nd)]] <- integer(0)
  }
  if (nrow(edges) > 0L) {
    for (i in seq_len(nrow(edges))) {
      a <- as.character(edges$from[i])
      b <- as.character(edges$to[i])
      adj[[a]] <- unique(c(adj[[a]], as.integer(b)))
      adj[[b]] <- unique(c(adj[[b]], as.integer(a)))
    }
  }

  visited <- setNames(rep(FALSE, length(nodes)), as.character(nodes))
  comps <- list()
  comp_counter <- 0L

  for (nd in nodes) {
    key <- as.character(nd)
    if (visited[[key]]) {
      next
    }
    stack <- as.integer(nd)
    comp <- integer(0)
    while (length(stack) > 0L) {
      cur <- stack[[1]]
      stack <- stack[-1]
      cur_key <- as.character(cur)
      if (visited[[cur_key]]) {
        next
      }
      visited[[cur_key]] <- TRUE
      comp <- c(comp, cur)
      nbrs <- adj[[cur_key]]
      if (length(nbrs) > 0L) {
        for (nb in nbrs) {
          if (!visited[[as.character(nb)]]) {
            stack <- c(nb, stack)
          }
        }
      }
    }
    comp_counter <- comp_counter + 1L
    comps[[comp_counter]] <- sort(unique(comp))
  }
  comps
}

raw <- read_dta(input_path)

item_like <- grep("^[maf][0-9]", names(raw), value = TRUE)
binary_items <- item_like[vapply(raw[item_like], binary_flag, logical(1))]

item_values <- lapply(raw[binary_items], function(x) as.numeric(zap_labels(x)))
item_values <- as.data.frame(item_values, check.names = FALSE)
item_mat <- as.matrix(item_values)

context_df <- data.frame(
  row_id = seq_len(nrow(raw)),
  id_student_panel = as.character(raw$id_student_panel),
  subject = as.character(as_factor(raw$subject)),
  grade = as.integer(raw$grade),
  treated = as.numeric(zap_labels(raw$treated)),
  school = as.character(raw$school),
  cd_etab = as.character(raw$cd_etab),
  duration_num = suppressWarnings(as.numeric(as.character(raw$duration))),
  stringsAsFactors = FALSE
)
context_df$duration_num[is.na(context_df$duration_num)] <- -Inf
context_df$n_binary_nonmissing <- rowSums(!is.na(item_mat))
context_df$binary_score_observed <- rowSums(ifelse(is.na(item_mat), 0, item_mat))

analysis_df <- cbind(context_df, item_values)
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

item_label_df <- data.frame(
  item = binary_items,
  item_label = vapply(raw[binary_items], item_label, character(1)),
  stringsAsFactors = FALSE
)

anchor_item_summary <- read.csv(file.path(psych_dir, "pilot_anchor_item_summary.csv"), stringsAsFactors = FALSE)

final_anchor_items <- anchor_item_summary %>%
  mutate(
    final_anchor = anchor_flag == "usable_anchor" & treated_p_swing > max_negative_anchor_swing
  )

anchor_pair_final <- final_anchor_items %>%
  group_by(subject, grade_pair) %>%
  summarise(
    shared_items = n(),
    usable_anchor_candidates = sum(anchor_flag == "usable_anchor"),
    final_anchors = sum(final_anchor),
    .groups = "drop"
  ) %>%
  mutate(chain_edge = final_anchors >= min_final_anchors_per_edge)

pair_index <- anchor_pair_final %>%
  mutate(
    grade_lo = as.integer(sub("g([0-9]+)-g([0-9]+)", "\\1", grade_pair)),
    grade_hi = as.integer(sub("g([0-9]+)-g([0-9]+)", "\\2", grade_pair))
  )

chain_summary_list <- list()
chain_grade_summary_list <- list()
chain_student_summary_list <- list()
chain_item_map_list <- list()
chain_anchor_use_list <- list()
chain_param_list <- list()

chain_counter <- 0L
grade_summary_counter <- 0L
student_counter <- 0L
item_map_counter <- 0L
anchor_use_counter <- 0L
param_counter <- 0L

subjects <- sort(unique(dedup_df$subject))

for (subj in subjects) {
  subj_rows <- dedup_df %>%
    filter(subject == subj)
  subj_grades <- sort(unique(subj_rows$grade))
  subj_pairs <- pair_index %>%
    filter(subject == subj, chain_edge)

  grade_edges <- data.frame(from = integer(0), to = integer(0))
  if (nrow(subj_pairs) > 0L) {
    grade_edges <- data.frame(from = subj_pairs$grade_lo, to = subj_pairs$grade_hi)
  }

  grade_components <- find_components(subj_grades, grade_edges)

  for (comp_id in seq_along(grade_components)) {
    comp_grades <- sort(grade_components[[comp_id]])
    chain_id <- paste0(tolower(subj), "_chain", comp_id)
    chain_rows <- subj_rows %>%
      filter(grade %in% comp_grades) %>%
      arrange(grade, id_student_panel)

    item_present <- binary_items[colSums(!is.na(chain_rows[, binary_items, drop = FALSE])) > 0]
    if (length(item_present) < 3L) {
      next
    }

    comp_pair_labels <- character(0)
    if (length(comp_grades) > 1L) {
      comp_pair_labels <- paste0("g", comp_grades[-length(comp_grades)], "-g", comp_grades[-1])
    }

    subj_final_anchors <- final_anchor_items %>%
      filter(subject == subj, final_anchor, grade_pair %in% comp_pair_labels) %>%
      select(subject, grade_pair, item, item_label, treated_p_swing)

    chain_item_map <- list()
    chain_anchor_use <- list()

    for (it in item_present) {
      item_grades <- sort(unique(chain_rows$grade[!is.na(chain_rows[[it]])]))
      item_edges <- data.frame(from = integer(0), to = integer(0))
      if (length(item_grades) > 1L) {
        edge_rows <- subj_final_anchors %>%
          filter(item == it) %>%
          mutate(
            grade_lo = as.integer(sub("g([0-9]+)-g([0-9]+)", "\\1", grade_pair)),
            grade_hi = as.integer(sub("g([0-9]+)-g([0-9]+)", "\\2", grade_pair))
          )
        if (nrow(edge_rows) > 0L) {
          item_edges <- data.frame(from = edge_rows$grade_lo, to = edge_rows$grade_hi)
        }
      }

      item_components <- find_components(item_grades, item_edges)
      for (k in seq_along(item_components)) {
        comp <- sort(item_components[[k]])
        col_name <- if (length(comp) == 1L) {
          paste0("g", comp, "__", it)
        } else {
          paste0("g", min(comp), "_to_g", max(comp), "__", it)
        }

        for (gr in comp) {
          chain_item_map[[length(chain_item_map) + 1L]] <- data.frame(
            subject = subj,
            chain_id = chain_id,
            grade = gr,
            source_item = it,
            linked_item = col_name,
            linked_across_grades = length(comp) > 1L,
            component_grades = paste(comp, collapse = ","),
            stringsAsFactors = FALSE
          )
        }

        if (length(comp) > 1L) {
          chain_anchor_use[[length(chain_anchor_use) + 1L]] <- data.frame(
            subject = subj,
            chain_id = chain_id,
            source_item = it,
            linked_item = col_name,
            component_grades = paste(comp, collapse = ","),
            stringsAsFactors = FALSE
          )
        }
      }
    }

    item_map_df <- bind_rows(chain_item_map)
    anchor_use_df <- bind_rows(chain_anchor_use)

    linked_items <- sort(unique(item_map_df$linked_item))
    linked_matrix <- matrix(NA_real_, nrow = nrow(chain_rows), ncol = length(linked_items))
    colnames(linked_matrix) <- linked_items

    for (i in seq_len(nrow(item_map_df))) {
      mp <- item_map_df[i, ]
      use_rows <- chain_rows$grade == mp$grade
      linked_matrix[use_rows, mp$linked_item] <- chain_rows[use_rows, mp$source_item]
    }

    linked_df <- as.data.frame(linked_matrix, check.names = FALSE)
    item_response_rates <- colMeans(!is.na(linked_matrix))
    keep_cols <- names(item_response_rates)[item_response_rates > 0]
    linked_df <- linked_df[, keep_cols, drop = FALSE]

    x <- as.matrix(linked_df)
    x[is.na(x)] <- 0

    irt_fit <- fit_irt_model(x)
    theta <- rep(NA_real_, nrow(chain_rows))

    if (!is.null(irt_fit$model)) {
      theta <- as.numeric(fscores(irt_fit$model, method = "EAP")[, 1])
      item_params <- tryCatch({
        params <- coef(irt_fit$model, IRTpars = TRUE, simplify = TRUE)$items
        data.frame(
          subject = subj,
          chain_id = chain_id,
          linked_item = rownames(params),
          irt_discrimination = unname(params[, "a"]),
          irt_difficulty = unname(params[, "b"]),
          stringsAsFactors = FALSE,
          row.names = NULL
        )
      }, error = function(e) data.frame())
      if (nrow(item_params) > 0L) {
        param_counter <- param_counter + 1L
        chain_param_list[[param_counter]] <- item_params
      }
    }

    chain_rows$theta_linked <- theta
    chain_rows$chain_id <- chain_id
    chain_rows$scale_linked <- length(comp_grades) > 1L

    grade_summary <- chain_rows %>%
      group_by(subject, chain_id, grade) %>%
      summarise(
        n_students = n(),
        n_treated = sum(treated == 1, na.rm = TRUE),
        n_control = sum(treated == 0, na.rm = TRUE),
        theta_mean_all = mean(theta_linked, na.rm = TRUE),
        theta_sd_all = stats::sd(theta_linked, na.rm = TRUE),
        theta_mean_treated = mean(theta_linked[treated == 1], na.rm = TRUE),
        theta_mean_control = mean(theta_linked[treated == 0], na.rm = TRUE),
        treated_minus_control = theta_mean_treated - theta_mean_control,
        .groups = "drop"
      )

    chain_summary <- data.frame(
      subject = subj,
      chain_id = chain_id,
      grades = paste(comp_grades, collapse = ","),
      linked_across_multiple_grades = length(comp_grades) > 1L,
      n_students = nrow(chain_rows),
      n_linked_items = ncol(linked_df),
      n_anchor_items_used = if (nrow(anchor_use_df) == 0L) 0L else length(unique(anchor_use_df$source_item)),
      n_linked_anchor_columns = nrow(anchor_use_df),
      model_used = irt_fit$model_used,
      converged = irt_fit$converged,
      fit_reason = irt_fit$fit_reason,
      stringsAsFactors = FALSE
    )

    chain_counter <- chain_counter + 1L
    chain_summary_list[[chain_counter]] <- chain_summary
    grade_summary_counter <- grade_summary_counter + 1L
    chain_grade_summary_list[[grade_summary_counter]] <- grade_summary
    student_counter <- student_counter + 1L
    chain_student_summary_list[[student_counter]] <- chain_rows %>%
      select(id_student_panel, subject, grade, treated, school, cd_etab, chain_id, scale_linked, theta_linked)

    if (nrow(item_map_df) > 0L) {
      item_map_counter <- item_map_counter + 1L
      chain_item_map_list[[item_map_counter]] <- item_map_df
    }
    if (nrow(anchor_use_df) > 0L) {
      anchor_use_counter <- anchor_use_counter + 1L
      chain_anchor_use_list[[anchor_use_counter]] <- anchor_use_df
    }
  }
}

chain_summary_df <- bind_rows(chain_summary_list) %>%
  arrange(subject, chain_id)

grade_summary_df <- bind_rows(chain_grade_summary_list) %>%
  arrange(subject, chain_id, grade)

student_summary_df <- bind_rows(chain_student_summary_list) %>%
  arrange(subject, grade, id_student_panel)

item_map_summary_df <- bind_rows(chain_item_map_list) %>%
  arrange(subject, chain_id, linked_item, grade)

anchor_use_summary_df <- bind_rows(chain_anchor_use_list) %>%
  arrange(subject, chain_id, source_item)

param_summary_df <- bind_rows(chain_param_list) %>%
  arrange(subject, chain_id, linked_item)

write.csv(
  anchor_pair_final,
  file = file.path(output_dir, "pilot_vertical_anchor_pair_summary.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  final_anchor_items,
  file = file.path(output_dir, "pilot_vertical_anchor_item_audit.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  chain_summary_df,
  file = file.path(output_dir, "pilot_vertical_link_summary.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  grade_summary_df,
  file = file.path(output_dir, "pilot_vertical_linked_grade_summary.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  student_summary_df,
  file = file.path(output_dir, "pilot_vertical_student_scores.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  item_map_summary_df,
  file = file.path(output_dir, "pilot_vertical_item_map.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  anchor_use_summary_df,
  file = file.path(output_dir, "pilot_vertical_anchor_items_used.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  param_summary_df,
  file = file.path(output_dir, "pilot_vertical_item_parameters.csv"),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

summary_path <- file.path(output_dir, "pilot_vertical_linking_summary.md")
con <- file(summary_path, open = "wt", encoding = "UTF-8")

writeLines("# Pilot vertical linking", con)
writeLines("", con)
writeLines(paste0("- Input file: `", input_path, "`"), con)
writeLines("- Linking method: concurrent single-factor calibration within subject using only vetted common items as shared columns.", con)
writeLines(paste0("- Final anchor rule: `usable_anchor` from the anchor audit, treated swing >", max_negative_anchor_swing, ", and at least ", min_final_anchors_per_edge, " final anchors to sustain an adjacent-grade link."), con)
writeLines("- If an adjacent-grade link failed that threshold, the chain was broken rather than forced.", con)
writeLines("", con)
writeLines("## Anchor edges", con)
writeLines("", con)

for (i in seq_len(nrow(anchor_pair_final))) {
  row <- anchor_pair_final[i, ]
  writeLines(
    paste0(
      "- ", row$subject, " ", row$grade_pair,
      ": ", row$final_anchors, " final anchors out of ",
      row$usable_anchor_candidates, " usable candidates",
      if (isTRUE(row$chain_edge)) " -> kept as a link" else " -> chain broken"
    ),
    con
  )
}

writeLines("", con)
writeLines("## Linked chains", con)
writeLines("", con)

for (i in seq_len(nrow(chain_summary_df))) {
  row <- chain_summary_df[i, ]
  writeLines(
    paste0(
      "- ", row$subject, " ", row$chain_id,
      " (grades ", row$grades, "): N=", row$n_students,
      ", items=", row$n_linked_items,
      ", anchor items used=", row$n_anchor_items_used,
      ", model=", row$model_used,
      ", fit=", row$fit_reason
    ),
    con
  )
}

writeLines("", con)
writeLines("## Grade means on linked scales", con)
writeLines("", con)

for (i in seq_len(nrow(grade_summary_df))) {
  row <- grade_summary_df[i, ]
  writeLines(
    paste0(
      "- ", row$subject, " ", row$chain_id, " grade ", row$grade,
      ": theta mean=", sprintf("%.3f", row$theta_mean_all),
      ", treated=", sprintf("%.3f", row$theta_mean_treated),
      ", control=", sprintf("%.3f", row$theta_mean_control),
      ", treated-control gap=", sprintf("%.3f", row$treated_minus_control)
    ),
    con
  )
}

close(con)

cat("Wrote outputs to:", output_dir, "\n")
