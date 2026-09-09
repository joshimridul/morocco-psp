#!/usr/bin/env Rscript

# Aggregate coefficient plot for the validated strict-core treatment-effect
# comparison. Reads and writes only below the configured work_root.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(stringr)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("Usage: plot_y3_irt_treatment_sensitivity.R config/paths.local.yml")
}

paths <- yaml::read_yaml(normalizePath(args[[1]], mustWork = TRUE))$dropbox
source_roots <- normalizePath(
  c(paths$y1_root, paths$y2_root, paths$y3_root),
  mustWork = TRUE
)
work_root <- normalizePath(paths$work_root, mustWork = TRUE)

is_within <- function(path, root) {
  candidate <- normalizePath(path, mustWork = FALSE)
  boundary <- normalizePath(root, mustWork = FALSE)
  identical(candidate, boundary) ||
    startsWith(candidate, paste0(boundary, .Platform$file.sep))
}

assert_work_input <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  if (!is_within(candidate, work_root)) stop("Input is outside work_root")
  candidate
}

assert_output <- function(path) {
  candidate <- normalizePath(path, mustWork = FALSE)
  if (!is_within(candidate, work_root) || identical(candidate, work_root)) {
    stop("Output must be below work_root")
  }
  if (any(vapply(
    source_roots,
    function(root) is_within(candidate, root) && !is_within(work_root, root),
    logical(1)
  ))) {
    stop("Output resolves inside a source root")
  }
  candidate
}

out_dir <- file.path(
  work_root,
  "outputs/y1_y3_irt/06_treatment_effect_sensitivity"
)
estimate_path <- assert_work_input(file.path(out_dir, "treatment_effect_estimates.csv"))
figure_dir <- assert_output(file.path(out_dir, "figures"))
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

estimates <- read_csv(estimate_path, show_col_types = FALSE)
plain <- estimates %>%
  filter(
    sample_variant == "listed_panel",
    estimand_sample == "chained_strict",
    score_method == "plain_code",
    pairing_role == "plain_companion_same_student_panel",
    cohort_scope == "Pooled_equal_weight",
    grade_scope == "All_grades"
  )
irt <- estimates %>%
  filter(
    sample_variant == "listed_panel",
    score_method %in% c(
      "chained_strict", "pooled_strict_all", "pooled_strict_comparison"
    ),
    pairing_role == "irt_target",
    cohort_scope == "Pooled_equal_weight",
    grade_scope == "All_grades"
  )
plot_data <- bind_rows(plain, irt) %>%
  mutate(
    method = recode(
      score_method,
      plain_code = "Plain binary total",
      chained_strict = "Strict chained IRT",
      pooled_strict_all = "Strict pooled IRT (all)",
      pooled_strict_comparison = "Strict pooled IRT (controls)"
    ),
    method = factor(
      method,
      levels = rev(c(
        "Plain binary total",
        "Strict chained IRT",
        "Strict pooled IRT (all)",
        "Strict pooled IRT (controls)"
      ))
    ),
    subject = factor(
      subject,
      levels = c("Overall", "Arabic", "French", "Maths")
    ),
    method_family = if_else(
      score_method == "plain_code", "Plain score", "IRT score"
    )
  )

if (nrow(plot_data) != 16) stop("Expected four methods for four panels")
if (any(plot_data$estimation_status != "estimated_development_only")) {
  stop("Plot data include a non-estimated row")
}
facet_labels <- plot_data %>%
  distinct(subject, n_students) %>%
  mutate(
    label = paste0(
      as.character(subject), "  (N=", format(n_students, big.mark = ","), ")"
    )
  ) %>%
  { setNames(.$label, as.character(.$subject)) }

chart_source_path <- assert_output(file.path(
  figure_dir,
  "strict_core_treatment_effect_plot_data.csv"
))
write_csv(
  plot_data %>%
    transmute(
      subject = as.character(subject),
      method = as.character(method),
      method_family,
      estimate, std_error, conf_low, conf_high,
      n_students, n_schools, n_pairs,
      sample_variant, cohort_scope,
      final_outcome_approved
    ),
  chart_source_path,
  na = ""
)

palette <- c("Plain score" = "#B7791F", "IRT score" = "#2B6CB0")
shapes <- c("Plain score" = 21, "IRT score" = 16)

figure <- ggplot(
  plot_data,
  aes(
    x = estimate,
    y = method,
    color = method_family,
    shape = method_family
  )
) +
  geom_vline(xintercept = 0, color = "#4A5568", linewidth = 0.45) +
  geom_errorbarh(
    aes(xmin = conf_low, xmax = conf_high),
    height = 0,
    linewidth = 0.7
  ) +
  geom_point(size = 2.8, stroke = 0.8, fill = "white") +
  facet_wrap(~ subject, ncol = 2, labeller = as_labeller(facet_labels)) +
  scale_color_manual(values = palette) +
  scale_shape_manual(values = shapes) +
  scale_x_continuous(
    breaks = seq(0, 0.7, by = 0.1),
    labels = function(x) sprintf("%.1f", x)
  ) +
  coord_cartesian(xlim = c(-0.10, 0.72), clip = "off") +
  labs(
    title = "Year 3 matched-DiD estimates across strict score constructions",
    subtitle = paste(
      "Common student panel within each subject; effects in score-SD units;",
      "matched-pair-by-grade fixed effects and pair-clustered 95% CIs"
    ),
    x = "Treatment effect (SD)",
    y = NULL,
    color = NULL,
    shape = NULL,
    caption = paste(
      "Listed-panel development analysis. IRT uses the fixed Year 1 endline-comparison metric;",
      "plain scores use Year 3 subject x cohort x wave control standardization. No covariate adjustment."
    )
  ) +
  theme_minimal(base_size = 11, base_family = "Helvetica") +
  theme(
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(color = "#E2E8F0", linewidth = 0.4),
    strip.text = element_text(face = "bold", color = "#1A202C", size = 11),
    axis.text = element_text(color = "#2D3748"),
    axis.title.x = element_text(color = "#1A202C", margin = margin(t = 8)),
    plot.title = element_text(face = "bold", color = "#1A202C", size = 15),
    plot.subtitle = element_text(color = "#4A5568", margin = margin(b = 12)),
    plot.caption = element_text(color = "#718096", hjust = 0, size = 8.5),
    legend.position = "top",
    legend.justification = "left",
    plot.margin = margin(12, 18, 12, 12)
  )

png_path <- assert_output(file.path(
  figure_dir,
  "strict_core_treatment_effects.png"
))
pdf_path <- assert_output(file.path(
  figure_dir,
  "strict_core_treatment_effects.pdf"
))
ggsave(png_path, figure, width = 12, height = 7.4, dpi = 200, bg = "white")
ggsave(pdf_path, figure, width = 12, height = 7.4, device = cairo_pdf, bg = "white")
cat(png_path, "\n", pdf_path, "\n", sep = "")
