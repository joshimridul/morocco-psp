# Analysis Specification

## Phase 0 — Data readiness and score reconstruction

1. Inventory every file, sheet/table, row count, column, data type, and date range.
2. Identify the canonical keys for students, administrations, forms, items, item versions, stimuli/testlets, and raters.
3. Build normalized tables for administrations, responses, items, forms, stimuli/testlets, scoring, students, and study design.
4. Identify duplicate keys, conflicting labels, orphan responses, undocumented missing codes, invalid scores, and impossible grade/form mappings.
5. Recalculate all totals and subscores from item scores and compare them with supplied scores. Report every discrepancy.
6. Build a crosswalk between item IDs and actual item versions. Create fingerprints incorporating prompt, options, key/rubric, stimulus asset, and administration/scoring metadata. Flag all apparent matches requiring human review.
7. Produce a form-link graph showing which forms share exact eligible items and which intended links are weak or disconnected.
8. Do not fit psychometric models until the analysis-ready subsets and unresolved blockers are explicit.

## Phase 1 — Operational and classical item diagnostics

Analyze each item-version separately by grade, form, wave, and relevant language/scoring context.

For dichotomous items report:
- N administered and N valid;
- omission, invalid, and not-reached rates;
- proportion correct with uncertainty;
- corrected item-rest correlation;
- distractor selection and distractor-rest relationships where options exist;
- response time where available;
- cluster-bootstrap stability by school/cohort.

For polytomous or rubric-scored units report:
- category frequencies and thresholds;
- mean/variance and corrected item-rest or polyserial relationship;
- unused or disordered categories;
- rater agreement, rater severity, and double-scoring evidence where available.

Assess score precision and structure:
- total-score and proposed subscore reliability with uncertainty;
- omega/alpha only where their assumptions are defensible;
- factor/dimensionality diagnostics appropriate to categorical data;
- residual/local dependence and testlet effects;
- floor/ceiling and conditional information;
- consequences of treating rubric criteria or passage items as independent.

Item flags are diagnostic, not automatic retention decisions. Every flagged item requires substantive review.

## Phase 2 — IRT, DIF, drift, and anchor evaluation

1. Define anchor candidates separately for each intended link: within-grade pre/post, adjacent-grade vertical, and across-year trend.
2. Require exact operational equivalence before psychometric eligibility. A changed key, option, image, passage, rubric, administration mode, or exposure status creates a new version unless justified.
3. Choose the simplest defensible model. Compare Rasch/1PL with 2PL where sample size and diagnostics permit; use partial-credit/generalized partial-credit models for polytomous data. Do not default to 3PL.
4. Check item fit, category functioning, local dependence, dimensionality, and convergence.
5. Evaluate parameter drift and DIF with effect sizes, uncertainty, plots, and multiplicity controls. Large samples must not turn trivial effects into automatic exclusions.
6. Use iterative anchor purification and compare multiple substantively balanced anchor sets.
7. Evaluate stability of linking constants, student ranks/scores, and conclusions under alternate models and anchor sets.
8. Validate decisions in a held-out wave, cohort, or set of schools. Avoid random individual splits inside the same school.
9. Candidate anchor sets must cover the intended construct and difficulty range. Do not select only the statistically cleanest narrow items.
10. Initial screening must not be driven by treatment effects. After candidate scoring and anchors are frozen, test treatment-related item-function sensitivity separately and interpret it cautiously.

## Phase 3 — Form design and field-experiment precision

Construct and compare candidate forms under explicit constraints:
- curriculum objective coverage;
- content and cognitive score-point targets;
- number of independent tasks/testlets;
- difficulty distribution;
- conditional measurement information;
- oral/written/rater burden;
- expected duration;
- repeated-item exposure;
- anchor coverage for each link.

For each candidate form report:
- expected reliability/conditional standard errors;
- floor and ceiling behavior;
- domain-score defensibility;
- baseline-endline correlation where relevant;
- expected precision of the planned RCT estimand using the observed cluster structure, without selecting items based on observed treatment effects;
- performance under plausible missingness and attrition scenarios.

Compare at least:
- the existing form;
- a minimally revised form preserving strong anchors;
- a redesigned form meeting grade-specific blueprint constraints.

## Phase 4 — Decisions and reporting

Create an item-level decision table with:
- item/version/form/wave/grade identifiers;
- stimulus/testlet and rubric structure;
- curriculum, content, and cognitive classifications;
- operational and empirical statistics;
- model/DIF/drift evidence;
- exact-match and exposure status;
- substantive-review status;
- anchor role and anchor-set ID;
- recommendation: strong anchor, provisional anchor, scored non-anchor, diagnostic only, revise/new version, replace/retire;
- confidence and concise rationale.

Produce a technical report, a concise Ministry memo, and a human-review workbook. Clearly distinguish empirical evidence, substantive judgment, assumptions, and unresolved limitations.

## Phase 5 — Independent quality control

In a fresh Codex chat:
- reproduce all headline counts and score tie-outs from raw files;
- inspect code for silent exclusions, leakage, treatment-driven item selection, incorrect clustering, or collapsing of item versions;
- independently review a random stratified sample of items against the actual forms, keys, assets, and maps;
- rerun key analyses under alternate reasonable specifications;
- verify that every report table and figure is generated by code;
- create a pass/fail QC checklist with unresolved issues.
