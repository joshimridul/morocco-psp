# Ministry IRT regression pipeline

## Purpose

This pipeline reproduces the student-performance regressions and table order
used in the Year 3 preliminary reports shared with the Ministry, but reports
the preferred release-candidate IRT outcome. It also re-estimates the prior standardized
sum-score outcome as a hidden replication branch. The IRT report is accepted
only if that branch ties out to the earlier Ministry results.

No legacy source file is modified. Analysis-ready student panels and every
data-bearing output are written below the configured Dropbox `work_root`.
GitHub contains code and documentation only.

## One-click run

From a terminal:

```bash
  /Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp -b do \
  /Users/mriduljoshi/Github/morocco-psp/src/30_ministry_irt_report/00_master.do \
  /Users/mriduljoshi/Github/morocco-psp 1 0
```

The master reads the Dropbox work path from `config/paths.local.yml`. The final
second argument is `1` to compile the PDF and `0` to run only the analysis
and table generation. The third argument is `0` for the required full run; use
`1` only to rebuild tables/PDF from already validated estimates during layout
development. The measurement release gate runs in both modes. Each execution
keeps a timestamped Stata log and refreshes `00_master.log` as the latest-run
pointer. The master do-file refreshes the analysis-panel handoff,
runs every regression family, writes LaTeX tables in Stata, executes the
adversarial tie-out, and optionally compiles the report.

## Modules

- `00_master.do`: configuration, dependency checks, orchestration, and PDF build.
- `lib/analysis_programs.do`: shared panel, control-selection, model, and count helpers.
- `10_estimate_headline_stable.do`: headline and stable-sample results.
- `15_estimate_measurement_robustness.do`: pooled headline estimates under 18 declared measurement methods.
- `20_estimate_grade.do`: baseline-grade estimates and Benjamini--Yekutieli adjustment.
- `30_estimate_heterogeneity.do`: gender and baseline-performance heterogeneity.
- `40_export_latex.do`: eleven Stata-generated LaTeX regression and diagnostic tables.
- `90_validate_outputs.do`: structural assertions and independent replication checks.
- `qa/adversarial_review.R`: exact sum-score tie-out and result plausibility audit.
- `report/ministry_irt_report.tex`: report shell that retains the seven Ministry-order tables and appends the technical measurement appendix.
- `report/irt_technical_appendix.tex`: reader-facing documentation of the IRT construction, validation gates, and robustness methods.

## Measurement appendix

The technical appendix documents the primary IRT algorithm in prose and
equations: binary-item eligibility, response coding, treatment-blind DIF
purification, separate subject models, fixed Year 1 parameter counts, EAP
scoring, Year 1 endline comparison-group scaling, the stacked Overall outcome,
validation gates, and the link-retention rule used to preserve the complete
Year 3 baseline/endline grade panel.

Its robustness table reruns the pooled one-year, pooled two-year, and Cohort-1
three-year headline estimates for Overall, Arabic, French, and mathematics. It
contains all eight combinations of three choices: preferred versus more
conservative anchors; estimating new item parameters with all students versus
only students in comparison schools; and estimating one model per subject
versus a separate model for each grade. It also includes sequential and direct
links, EAP-versus-WLE scoring, alternative DIF rules, estimation using a subset
of schools, a broader definition of matching items, and the Ministry
standardized sum score on both the full sum-score sample and the exact primary
IRT sample. All 18 methods are declared in all 12 table cells. Unsupported
cells appear as dashes rather than being silently estimated on a different set
of subjects or cohorts. A companion table reports each method's student count
as a percentage of the primary IRT sample.

The appendix also records methods discussed but not promoted to successful
robustness estimates: an unrestricted group-distribution model registered as
unfinished and therefore not reported, a joint model with broader anchors that
converged but was quarantined because its matching rule is not accepted anchor
evidence, and a Rasch/1PL alternative that would
require a separate link to the fixed Year 1 2PL scale, and later treatment-DIF
analysis reserved for the post-freeze stage.

## Specification

The coefficient of interest is `treatment x post` in a two-period student
panel. Cohort-specific models absorb student fixed effects and include the
legacy matched-pair-by-grade time structure. Standard errors are clustered by
matched pair. Baseline controls are selected with `pdslasso` after removing
the comparison-group matched-pair-by-grade trend; selected controls enter the
final regression interacted with post. The control set is chosen separately
by outcome and analysis panel.

The pooled models make student, school, and pair identifiers unique across
cohorts and weight cohorts to contribute equal total weight. Grade-specific
pooled models recompute those weights within each grade-by-outcome sample.
The hidden full-sample `ministry_sum` benchmark alone preserves the historical
full-stack weights and absorbed fixed-effect form required for exact
replication; the primary IRT and exact-sample sum comparison use the corrected
outcome-specific weights.
Grade-table p-values are adjusted within exposure-by-cohort families across
all grades and outcomes using Benjamini--Yekutieli; other tables retain the
unadjusted p-values used in the Ministry report.

## Outputs

Outputs are under:

`<work_root>/outputs/y1_y3_irt/08_ministry_irt_report/`

- `ministry_irt_report.pdf`: compiled report.
- `tables/`: Stata-generated LaTeX fragments.
- `estimates/`: aggregate `.dta` and `.csv` result files plus selected controls.
- `qa/`: adversarial checks and Ministry sum-score tie-out.
- `logs/`: Stata and LaTeX logs.
