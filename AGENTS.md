# Project instructions for Codex

## Mission
Build a transparent, reproducible assessment audit for the Moroccan Pioneer Schools project while preserving a strict boundary between read-only Dropbox data and new GitHub code.

The immediate priority is the **Year 3 Ministry item and anchor audit**. The medium-run priority is to determine whether Year 1, Year 2, and Year 3 support defensible subject-specific linked or multi-group IRT models across their different forms, grades, cohorts, waves, and samples. Year 1 supports a different paper and must not be forced onto a common scale.

## Read first
Before editing or running code, read:

- `README.md`
- `docs/DROPBOX_Y1_Y2_Y3_DATA_AND_CODE_ARCHITECTURE.md`
- `docs/MINISTRY_EXCHANGE_AND_DELIVERABLE_STATUS.md`
- `docs/STUDY_DESIGN.md`
- `docs/ANALYSIS_SPEC.md`
- `docs/DATA_PACKAGE_CHECKLIST.md`
- `config/analysis.yml`
- all available data dictionaries, item maps, scoring documents, and form documentation referenced through the approved local path configuration

## Current phase restriction
Until the project lead explicitly authorizes the legacy-code phase:

- do not open or execute inherited `.do` or `.R` files;
- do not infer their logic from filenames;
- inventory their names only when useful for a future dependency map;
- work first from verified deidentified Year 3 data, item maps, instruments, keys/rubrics, and prior output tables.

## Non-negotiable storage and safety rules

1. Treat the Year 1, Year 2, and Year 3 Dropbox roots as read-only source systems. Never edit, overwrite, rename, move, delete, archive, or reorganize any file in them.
2. Never write a generated file anywhere under the three legacy roots. All data-bearing outputs belong under the dedicated Dropbox `work_root` configured in `config/paths.local.yml`.
3. New code, tests, documentation, and configuration templates belong in GitHub. No data, item maps, instruments, answer keys, secure item text, direct identifiers, or data-bearing outputs belong in GitHub.
4. Never print or export direct identifiers. Stop and flag any apparent identifying fields or any need to enter a PII/master-key directory.
5. Build and verify a source registry with hashes before analysis. A file is not canonical merely because it is in `Clean`, has the latest date, or appears in a replication package.
6. Never silently select a Dropbox conflicted copy, recovered file, archive version, or draft.
7. The primary analytic unit is an **item-version within a form, administered grade, wave, cohort/sample, and scoring context**. Never collapse by item ID alone.
8. An item is not an anchor merely because its ID or English summary matches. Verify prompt, stimulus, options, key/rubric, administration, scoring, layout/context where relevant, and exposure. Create a version fingerprint and a human-review flag.
9. Separate three judgments: substantive necessity, empirical item quality, and anchor eligibility.
10. Do not use estimated treatment effects to select, remove, or retain items. Perform initial screening blind to treatment or using pre-treatment/prior-control data. Treatment-related DIF is a later sensitivity analysis.
11. Preserve testlet structure. Items sharing a passage, image, oral task, or rubric must be linked through `stimulus_id` or `testlet_id`; rubric criteria are not independent questions.
12. Respect clustering by school/class and the randomization unit. Use school, cohort, sample, or wave splits for development and validation rather than random individual splits.
13. Numerical thresholds are warning flags only. Do not make automatic decisions from a single statistic or p-value.
14. Report effect sizes, uncertainty, sample sizes, missingness, model assumptions, convergence, and sensitivity to alternate models and anchor sets.
15. Do not fit a complex IRT model unless sample size, response format, dimensionality, and diagnostics support it. Provide a simpler fallback.
16. All transformations must be deterministic, logged, and tested. Set seeds and record software/package versions.
17. Every reported number must be reproducible from tracked scripts and traceable through the source registry.
18. When information is missing, add it to a blocking-issues register and continue only on unambiguous subsets. Never invent mappings, keys, item versions, or sample definitions.
19. Do not begin the immediate Year 3 audit from the legacy combined `y1y2y3_tested_data.dta`. Begin from verified Year 3 wave-specific sources and later reconcile the combined file.
20. A combined dataset is not evidence of a common scale. Build a form-and-sample link graph before any Y1–Y3 model.

## Collaboration rules

- Describe discrepancies neutrally and with evidence.
- Do not alter another author’s code or outputs.
- Maintain `verified`, `likely`, `uncertain`, and `requires collaborator confirmation` statuses.
- Ask narrow questions that identify the candidate files, observed difference, scientific consequence, and provisional recommendation.
- Preserve a decision log for all source, scoring, exclusion, and anchor decisions.

## Required outputs

Produce, in sequence:

- a GitHub/Dropbox boundary check and path-write guards;
- a Year 3 source registry and blocking-issues register;
- Year 3 score reconstruction and tie-out checks;
- Year 3 item-level operational, classical, structural, and IRT diagnostics where justified;
- separate candidate anchor sets for within-grade pre/post, adjacent-grade vertical, and across-year trend links;
- anchor-set sensitivity and validation results;
- a Ministry-facing item decision workbook and memo;
- only then, a read-only legacy-code lineage audit;
- later, a Y1–Y3 form/sample graph, harmonized item-version registry, and defensible subject-specific linked models.
