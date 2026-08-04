# Codex Prompts

Run these sequentially in separate chats within the same local project. All data-bearing outputs named below are logical paths under the configured Dropbox `work_root`, not directories to be committed to GitHub.

## Phase 0 — GitHub/Dropbox boundary and Year 3 source readiness

Read `AGENTS.md`, `README.md`, and `docs/DROPBOX_Y1_Y2_Y3_DATA_AND_CODE_ARCHITECTURE.md` before doing anything else. The current priority is the Year 3 Ministry item and anchor audit. Year 1 and Year 2 are deferred except for documenting later source candidates.

For this phase:

- do not open or execute any inherited `.do` or `.R` files;
- do not fit IRT, factor, DIF, or treatment-effect models;
- do not write anywhere under the Year 1, Year 2, or Year 3 Dropbox roots;
- do not copy or symlink data into the GitHub repository;
- do not enter PII volumes, master-key folders, preload folders, or named student-list folders.

First verify the repository/data boundary. Load the untracked `config/paths.local.yml`, resolve all four Dropbox roots, and implement tested path guards that fail if any generated output is inside a legacy root or equals an input path. Confirm that all data, local paths, derived files, logs, and rendered data-bearing outputs are excluded from Git.

Then inventory only the targeted Year 3 wave-specific data, item maps, actual instruments, keys/rubrics, and prior item/score outputs needed for the Ministry audit. Treat every apparent clean or latest-dated file as a candidate until provenance is verified. Record root alias, relative path, file metadata, SHA-256, schema, candidate role, PII risk, and selection status in the source registry. Do not start from the combined `y1y2y3_tested_data.dta`; list it as a later reconciliation target.

For the selected deidentified Year 3 candidates, inspect schemas and labels, identify student, school, class, cohort/sample, wave, subject, administered grade, form, item, score, missingness, timing, and rater fields. Do not infer undocumented values. Build a blocking-issues register.

Only after sources are provisionally verified, build a normalized Year 3 item-response model in the dedicated Dropbox `work_root`. Reconstruct every available total and subscore from item-level fields, forms, keys, and rubrics; compare them with supplied scores and prior tables; and list every discrepancy. Preserve item-version, form, grade, wave, cohort/sample, stimulus/testlet, and scoring context.

Produce under the Dropbox `work_root`:

- `private_manifests/y3_source_registry.csv`
- `outputs/y3_ministry/00_readiness/source_readiness_report.html`
- `outputs/y3_ministry/00_readiness/blocking_issues.csv`
- `outputs/y3_ministry/00_readiness/score_tieout.xlsx`
- `outputs/y3_ministry/00_readiness/item_version_crosswalk.xlsx`
- analysis-ready Year 3 normalized files under `derived/y3_ministry/`
- logs with input hashes, row counts, schemas, exclusions, and software versions

Finish by stating exactly which Year 3 analyses are valid, provisional, or blocked. Do not begin the legacy-code audit or the Y1–Y3 model.

## Phase 1 — Item performance and score structure

Use only the validated derived tables from Phase 0. Read `docs/ANALYSIS_SPEC.md`. Do not inspect or optimize against treatment-effect estimates. Prefer pre-treatment data and prior control cohorts for initial item screening.

Run operational and classical item diagnostics separately by item-version, grade, form, wave, and scoring context. Handle dichotomous, polytomous, oral, written, and rater-scored tasks appropriately. Report N, missing/not-reached rates, difficulty/category distribution, corrected item-rest relationships, distractor behavior, timing, and cluster-bootstrap uncertainty.

Evaluate total-score and proposed domain-score precision, dimensionality, local dependence, testlet effects, and rater reliability. Do not treat rows sharing a passage, image, oral task, or rubric as independent items. Explain whether each proposed content/cognitive subscore has enough independent evidence to support heterogeneity analysis.

Use configurable warning flags from `config/analysis.yml`; never make automatic item decisions from a threshold or p-value. Produce:
- `outputs/y3_ministry/01_item_quality/item_diagnostics.xlsx`
- `outputs/y3_ministry/01_item_quality/domain_score_audit.xlsx`
- `outputs/y3_ministry/01_item_quality/reliability_and_structure.html`
- plots for item response, distractors, timing, local dependence, and score information
- a provisional item review table separating statistical flags from substantive-review needs.

## Phase 2 — Anchor analysis and linking

Use the validated data and actual item materials. Build three distinct anchor analyses: within-grade baseline/endline, adjacent-grade vertical links, and across-year trend links. An item can qualify for one role and not another.

First restrict to items with verified operational equivalence. Then select the simplest defensible model for each subject and response format. Compare Rasch/1PL with 2PL where justified; use partial-credit/generalized partial-credit models for polytomous tasks; do not default to 3PL. Check fit, category functioning, dimensionality, local dependence, and convergence.

Evaluate drift and DIF with effect sizes, uncertainty, and plots. Use iterative anchor purification. Construct multiple substantively balanced anchor sets spanning curriculum content, cognitive processes, and difficulty. Validate them in a held-out wave, cohort, or set of schools. Compare linking constants, score/rank stability, and conclusions under alternate models and anchor sets.

Do not remove an item because it shows a large raw treatment difference. Initial anchors must be developed without using treatment-effect estimates. After candidate sets are frozen, perform treatment-related item-function sensitivity analyses separately and interpret them cautiously.

Produce:
- `outputs/y3_ministry/02_anchors/anchor_eligibility.xlsx`
- `outputs/y3_ministry/02_anchors/anchor_sets_primary_and_backup.xlsx`
- `outputs/y3_ministry/02_anchors/dif_and_drift.xlsx`
- `outputs/y3_ministry/02_anchors/linking_sensitivity.html`
- a clear recommendation for each intended link, including links that are not defensible.

## Phase 3 — Candidate forms and recommendations

Using the evidence from Phases 0–2 and the constraints in `docs/STUDY_DESIGN.md`, construct and compare at least three forms for every relevant subject/grade: the existing form, a minimally revised form preserving defensible anchors, and a redesigned grade-specific form.

Optimize under explicit constraints rather than a single psychometric statistic: official curriculum objectives, content/cognitive score-point targets, independent tasks/testlets, difficulty range, conditional information, administration time, rater burden, exposure, and anchor coverage.

Estimate expected total and domain-score precision, floor/ceiling behavior, baseline-endline correlation, and expected precision for the planned clustered RCT design without selecting items based on observed treatment effects. Compare simple pre-specified sum/percentage scoring with IRT-based scoring as a robustness and development tool; do not assume IRT scores must be the primary RCT outcome.

Produce:
- `outputs/y3_ministry/03_forms/form_comparison.xlsx`
- `outputs/y3_ministry/03_forms/recommended_item_map.xlsx`
- `outputs/y3_ministry/03_forms/item_decision_workbook.xlsx`
- `outputs/y3_ministry/03_forms/form_simulation_report.html`
- `outputs/y3_ministry/04_report/technical_report.html`
- `outputs/y3_ministry/04_report/ministry_memo.md`

The decision workbook must classify each item as strong anchor, provisional anchor, scored non-anchor, diagnostic only, revise/new version, or replace/retire, with evidence, confidence, and rationale.

## Phase 4 — Independent audit

Act as a skeptical independent reviewer who did not write the original analysis. Read the raw data, documentation, code, and outputs. Recompute headline counts and score tie-outs from scratch. Search for silent exclusions, incorrect joins, treatment leakage, mis-specified clustering, collapsed item versions, ignored testlet dependence, unstable models, and unsupported anchor claims.

Independently inspect a stratified random sample of at least 30 item-version/form combinations against the actual original-language forms, options, keys, stimuli, rubrics, and administration information. Re-run key results under alternate reasonable specifications and anchor sets.

Produce `outputs/y3_ministry/05_qc/independent_qc_report.html` and `outputs/y3_ministry/05_qc/qc_findings.xlsx`, with each issue marked pass, warning, or fail; severity; evidence; affected outputs; and required correction.
## Phase 5 — Deferred legacy-code and Y1–Y3 measurement audit

Run this phase only after the Year 3 Ministry deliverable is complete and the project lead explicitly authorizes inspection of inherited code.

First perform a static, read-only audit of the selected master and dependency scripts. Do not execute them against live Dropbox folders. Catalogue inputs, outputs, destructive commands, absolute paths, globals, includes, scoring rules, anchor mappings, exclusions, and sample construction. If execution is needed, run a byte-identical copy in an isolated workspace with source inputs read-only and every output redirected to the configured Dropbox `work_root`. Never edit the original script.

Then build separate source, sample, form, and item-version registries for Year 1, Year 2, and Year 3. Treat Year 1 as a different paper and do not force it onto a common scale. Construct subject-specific form-and-sample graphs with nodes defined by year × wave × cohort × sample role × administered grade × form/version and edges defined only by verified operationally equivalent item versions.

Determine whether the networks support a single linked scale, multi-group linked models, separate scales, or only limited common-item comparisons. Compare parsimonious models first, evaluate drift and DIF by year/wave/grade/sample/treatment exposure, preserve testlets and rater structure, validate anchors in held-out groups, and report linking uncertainty. A combined legacy file is a reconciliation target, not proof of a common scale.

Produce all data-bearing outputs under `outputs/y1_y3_irt/` and `derived/y1_y3_harmonization/` in the Dropbox `work_root`.
