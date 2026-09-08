# Claude adversarial review of the IRT and regression pipelines

Date: 2026-09-08  
Repository revision reviewed by Claude: `0341c62`  
External reviewer: Claude Code 2.1.260, Opus, maximum reasoning effort  
Review mode: source inspection plus execution of independent R, Stata, and test checks; no source edits

## Overall verdict

**Needs revision before sharing.** Claude did not find a fatal error in the
core treatment-effect estimator. It did find one repository-security problem,
several inaccurate or unsupported reader-facing claims, an invalid stable-table
replication check, and insufficient lineage between the current source and the
shipped outputs.

The review covered the IRT construction, the regression pipeline, tests,
validation scripts, generated tables, logs, and the compiled report. Claude was
allowed to execute existing checks but was instructed not to edit source files
or write to any raw-data root. Codex then independently checked the principal
findings below.

## What the review found to be sound

- Only binary items reach the IRT estimator. The scorer has a hard failure for
  an observed response outside zero and one.
- The delivered Year 1 scores and fixed Year 1 item parameters are preserved.
  Claude independently matched 362 manifest anchors to the archived Year 1
  parameter files and found fitted fixed-parameter differences below
  approximately `6e-15`. The fixed counts are 104 Arabic, 85 French, and 66
  mathematics items.
- The main anchor screen is blind to treatment outcomes. The all-student DIF
  screen is diagnostic and cannot select the preferred anchors.
- The matched difference-in-differences code estimates the stated treatment by
  post coefficient with student fixed effects, flexible matched-pair by grade
  time effects, and matched-pair-clustered standard errors.
- Claude independently reproduced the main pooled IRT coefficients, including
  Arabic `0.3922`, French `0.7362`, and mathematics `0.6304` for one-year
  exposure.
- The standardized-sum-score branch reproduces the earlier Ministry headline,
  grade, and heterogeneity result files to numerical precision. The stable-
  sample family is the exception described below.
- The Benjamini--Yekutieli implementation is numerically correct.
- The path guards and observed writes respect the boundary between raw Dropbox
  roots and the configured working-output root.
- All 17 existing Python tests pass. Their coverage is narrow, however, and
  does not exercise the estimators that determine the reported coefficients.

## Highest-priority findings

### P0. Data-bearing files are tracked in GitHub

Claude found a tracked student-level score file containing student and school
identifiers, treatment status, and ability scores under
`y4-pilot-analysis/outputs/`. It also found tracked item-level psychometric
outputs, a file containing secure item text, and three Ministry item-map
workbooks under `exchange-with-ministry/`.

Codex verified that Git currently tracks 33 files under
`y4-pilot-analysis/outputs/`, including the student-score and item-draft files,
and tracks the three item-map workbooks. The current `outputs/**` ignore rule
does not match nested output directories and cannot untrack files already in
history. Repository visibility remains unverified.

**Release implication:** do not circulate the repository until the files are
removed from the index and history, ignore rules are corrected, and repository
visibility is established. If the repository was ever public, this should be
treated as a possible disclosure incident.

### P1. The report gives the wrong reason for missing Cohort 3 Arabic scores

The report says Year 3 baseline Arabic Grades 1 and 2 contain no eligible
binary items. That is contradicted by the pipeline: other declared IRT methods
score those nodes. Under the preferred rule, the relevant nodes are unlinked
after anchor purification. The preferred path file marks Year 3 baseline
Arabic Grades 1 and 2 and Year 3 endline Arabic Grade 1 as unlinked with zero
direct retained anchors.

This matters because the Cohort 3 Arabic result uses a materially different
grade composition from the earlier Ministry sum-score result. Claude's
same-sample check separated the channels:

- standardized sum score on the full Ministry sample: `0.2500` (`0.0450`);
- standardized sum score on the primary-IRT estimable sample: `0.2013`
  (`0.0473`);
- primary IRT on that same estimable sample: `0.3396` (`0.0755`).

Thus both sample composition and measurement affect the comparison. The
appendix should state the anchor-purification reason, list every missing grade
and wave, and show the sum-score effect on the IRT-estimable sample.

### P1. The stable-sample Ministry tie-out is circular and misses real discrepancies

`src/30_ministry_irt_report/qa/adversarial_review.R` uses
`ministry_stable_irt_estimates.csv`, produced by this project, as the reference
for the stable-sample family. The resulting exact match compares the pipeline
to itself.

Codex compared the saved `ministry_sum` estimates with the actual previously
delivered stable-sample LaTeX table. The one-year cells match closely, and the
student and school counts match, but several two- and three-year effects do
not. Examples include:

- Cohort 1, two-year Overall: legacy `0.566` versus new `0.635`;
- Cohort 1, two-year French: legacy `0.880` versus new `1.034`;
- Cohort 1, three-year French: legacy `0.729` versus new `0.940`;
- Cohort 2, two-year Overall: legacy `0.474` versus new `0.580`.

The cause is not yet established. The stable tie-out must point to a genuine
legacy artifact and the specification difference must be reconciled before
Table 2 is described as a reproduction.

### P1. “Finalized” contradicts the saved lineage fields

The report calls the primary IRT outcome finalized. Codex confirmed:

- `final_outcome_approved = 0` for all 52,483 rows in the primary outcome;
- `scale_status = development_only_joint_y1_metric` for all rows;
- `final_anchor_approved = 0` for all 3,519 mapped occurrences;
- Arabic and French have 2,565 occurrences whose full version-review status is
  `required`;
- the analysis-panel preparation summary is
  `development_only_not_approved`;
- all six analysis-panel source records require collaborator confirmation.

The report should use development/provisional language until these gates are
closed, and should list the open gates explicitly.

### P1. Measurement robustness changes both the score and the sample

The robustness table currently shows coefficients and standard errors but no
sample information. Some methods score far fewer grades and students than the
primary method, so differences across rows cannot be interpreted as pure
measurement sensitivity.

The compact coefficient/standard-error format was an explicit presentation
choice. The statistical issue can be addressed without undoing that choice by
adding a companion sample-retention table, marking low-retention cells, and
adding same-sample comparisons for the most important methods.

### P1. Full item-version review is not complete

The appendix currently suggests that prompt, stimulus, options, key, scoring,
format, and position were compared where possible. The mapping file instead
marks every Arabic and French occurrence as still requiring full review.
Mathematics rests on the project lead's immutable-item-ID attestation dated
2026-09-08, rather than an item-by-item content review.

The appendix should distinguish the completed mathematics attestation from the
outstanding Arabic and French operational review.

### P1. The preferred rule applies only 144 of 528 robust DIF frees

The preferred constraint summary reports 528 robust pairwise frees but only
144 applied frees. The code applies the preferred frees to within-year wave
drift and selected adjacent-grade endline comparisons; robust across-year,
pilot-to-main, and cohort signals are not generally freed. The standard screen
also contains 2,806 “material only” decisions that are retained because they do
not pass the multiple-testing threshold.

This is not automatically wrong: the broader model is known to lose links and
fail to converge. It is, however, a central coverage-versus-invariance choice
and must be disclosed with a clear sensitivity result.

### P1. Several Year 3 tests have weak direct links to Year 1

Codex independently counted the direct retained Year 1 anchors in the primary
mapping. Several Year 3 mathematics forms have only one or two direct anchors;
Year 3 endline Grade 6 has zero and is linked through intermediate tests. Twelve
linked mathematics nodes rely on a weakest edge of four anchors under the
documented bridge rule.

For the primary-versus-sequential conservative comparison, the node-level
score correlation remains at least approximately `0.994`, but mean differences
reach `1.467` raw-theta units and primary/sequential node standard-deviation
ratios range from about `0.94` to `1.36` for the observed Year 3 mathematics
comparisons. This reinforces the earlier conclusion: rank ordering is stable,
but the vertical location and effect-size unit are less stable. The report
should publish an anchors-by-test table and a node-scale sensitivity summary.

### P1. The shipped outputs do not have clean lineage to a full run of current source

The latest regression master log used `reuse_estimates = 1`, so it rebuilt the
tables and PDF from existing estimates. The last recorded full IRT build ended
before later edits to `build_irt_outcome_bundle.R`, `run_irt_pipeline.R`,
`validate_irt_pipeline_adversarial.R`, and
`build_measurement_correlations.R`. The later correlation and QA artifacts were
produced by ad hoc runs that are absent from the latest full-run manifest.

The estimate and outcome files do not carry a run identifier or driving-code
hash, and development modules write into the same production estimate
directory. A clean full IRT build and a no-cache regression build of the
current source are required before release. Longer term, outputs should carry
run IDs and code hashes, validation should assert them, and development runs
should write to a separate directory.

## Other important findings

- Pooled subject-specific regressions do not give cohorts equal total weight as
  stated. The weight denominator is calculated across all subject rows in each
  cohort before the subject restriction. Claude's corrected weights moved the
  pooled French effect from `0.7362` to `0.7550` and Arabic from `0.3922` to
  `0.3884`.
- The correlation checks standardize scores within assessment node, and changes
  within subject and grade. They therefore remove the location and scale
  differences that matter for the size of a linked treatment effect. The raw
  node mean and standard-deviation diagnostics are generated but not used by a
  validation gate.
- Several QA checks are circular or algebraic identities. In addition to the
  stable-sample tie-out, the within-reference-group mean-zero and variance-one
  checks cannot detect a faulty external reference, and the Year 1 parameter
  check does not itself close the loop to the archived Year 1 parameter files.
- The concurrent calibration uses a common normal distribution while estimating
  new item parameters. A sensitivity that frees calibration-group means and
  variances was not completed.
- EAP shrinkage and its variation across tests are not examined with a WLE,
  maximum-likelihood, or plausible-value sensitivity.
- Different modules alternate between explicit time-effect dummies and
  `absorb()`. Claude found a one-student and approximately one-percent standard-
  error difference in one independently re-estimated headline cell.
- Some reported cells have fewer than 20 matched-pair clusters, with a minimum
  of 10. These should be visibly flagged.
- The test suite does not exercise the IRT fits, score transformation, Stata
  estimand, cohort weighting, or multiple-testing code.
- The occurrence manifest lacks a testlet or stimulus identifier, and the
  pipeline does not report dimensionality, item fit, or local-dependence
  diagnostics. These are open requirements under `AGENTS.md`.
- The “Number of Schools” in pooled results treats the same school observed in
  two cohorts as two cohort-specific schools; some grade-table school counts are
  taken from the all-grade regression rather than the grade-specific cell.

## Checks that remain open

1. GitHub repository visibility and whether the tracked data were ever publicly
   accessible.
2. The exact legacy-code reason for the stable-table two- and three-year
   discrepancy.
3. A refit that frees calibration-group means and variances while estimating
   the new item parameters.
4. Full content/version review of Arabic and French anchors.
5. Item fit, dimensionality, local dependence, and testlet structure.
6. Subject-composition balance within treatment arm, matched pair, and grade for
   the stacked Overall regression.
7. The lineage of 96 missing Year 1 baseline IRT scores.

## Release gate

### Must fix before circulation

- Establish repository visibility and purge data-bearing/item-map files from
  the current tree and history; correct ignore and pre-commit guards.
- Correct the Cohort 3 Arabic coverage explanation and add the missing endline
  Grade 1 limitation.
- Reconcile the stable-sample specification and replace its circular QA
  reference.
- Replace “finalized” with development language unless all recorded approval
  gates are genuinely closed.
- Add sample-retention evidence for measurement-method comparisons.
- State the outstanding Arabic/French item-version review accurately.
- Complete one clean end-to-end build of the current IRT and regression source.

### Must disclose

- The limited direct Year 1 anchoring and four-anchor bridges in mathematics,
  together with the node-scale sensitivity.
- The 528 robust pairwise DIF signals versus 144 applied frees, and the retained
  material-only warnings.
- Differences in estimable samples across measurement methods.
- The difference between the fixed Year 1 reference unit used for IRT and the
  grade/report-specific standardization used for the earlier sum score.
- Small-cluster cells and grade-pooled cells supported by only one or two
  cohorts.
- That high within-node correlations establish similar ranking, not stable
  vertical location or scale.

### Important engineering improvements

- Stamp every output with a run ID and code/configuration hashes.
- Separate development and production output directories.
- Add validation thresholds for node mean shifts and standard-deviation ratios.
- Add integration tests for the IRT estimator, score transformation, Stata
  estimand, cohort weights, and table tie-outs.
- Add an IRT-path duplicate audit and item-fit/local-dependence/testlet
  diagnostics.

## Codex verification status

Codex directly verified the P0 repository finding; the incorrect Arabic
coverage explanation; the circular stable-sample reference and selected legacy
discrepancies; the unapproved outcome, anchor, item-review, and source-lineage
flags; the 528-versus-144 DIF count; the direct-anchor counts; the node mean and
scale differences; the pooled-weight construction; and the stale full-run
lineage. No corrective edits were made as part of this review.
