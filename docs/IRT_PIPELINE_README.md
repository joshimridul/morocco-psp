# One-click IRT outcome pipeline

This pipeline creates the measurement outcomes and measurement-robustness evidence only. It intentionally stops before treatment regressions.

## One command

From the repository root, run:

```bash
Rscript src/21_y1_y3_irt/run_irt_pipeline.R config/paths.local.yml
```

The full build reconstructs source registries and item eligibility, rebuilds the link graph and treatment-blind anchor purification, refits every declared model, creates the outcome datasets and correlation matrices, runs adversarial validation, and runs the unit tests. On the 2026-09-08 build it ran 35 steps in about 51 minutes.

For code development only, after a successful full estimation run, the downstream bundle and validation can be rebuilt with:

```bash
Rscript src/21_y1_y3_irt/run_irt_pipeline.R config/paths.local.yml --assemble-only
```

`--assemble-only` is not a substitute for the full reproducibility run.

## Primary outcome algorithm

1. Read the six registered Year 2 and Year 3 wave files from the three read-only Dropbox source systems. Hash the files before estimation and rehash them during final validation.
2. Read the archived Year 1 item parameters as immutable inputs. The build never re-estimates or overwrites the Year 1 paper's scores or item parameters.
3. Keep only item occurrences whose observed scoring is binary. Score observed `1` as correct, observed `0` and tagged `.a` (“don't know”) as incorrect, and leave ordinary/system missing responses missing. Continuous, count, oral-fluency, and rubric outcomes never enter a 2PL model.
4. Deduplicate a student within a form deterministically: retain the row with the most answered eligible items, then the longest duration, then the earliest source row. The audit reports every removed row.
5. Treat Arabic, French, and mathematics as separate constructs. There is no cross-subject latent factor.
6. Build item-version occurrences and the form/sample link graph. The project lead confirmed on 2026-09-08 that, in the operational Year 2 and Year 3 files, an unchanged item ID guarantees unchanged content, key, scoring, stimulus, format, and administration, and that an edited item receives a new ID. The pipeline records that decision explicitly.
7. Conduct treatment-blind grade-DIF, cohort-DIF, and wave/pilot drift screening. The comparison-group screen determines development frees. The all-student screen is diagnostic only. No estimated treatment effect selects an item.
8. Apply one subject-neutral targeted DIF rule. Free an implicated occurrence only when the joint-logistic and Mantel–Haenszel checks agree and the difference is material. Rank flagged anchors by adjusted evidence and materiality, retain at least five anchors on required screened links, and permit a verified four-anchor graph edge only when needed to connect an otherwise isolated assessment group. Every floor-retained decision remains flagged. This rule prevents statistical warning thresholds from mechanically deleting the link needed to score an administered test.
9. Fit one concurrent incomplete-booklet 2PL calibration per subject using all Year 2 and Year 3 records. Fix the pooled calibration mixture to `N(0,1)` for numerical stability. Fix all 255 archived Year 1 anchor parameters exactly: Arabic 104, French 85, and mathematics 66.
   Freely estimated discrimination parameters have a declared upper bound of 10 to prevent near-separated items from drifting toward infinity. The bound never applies to a fixed Year 1 parameter. The primary fit may use up to 4,000 EM cycles; robustness fits retain the 1,500-cycle budget.
10. Freeze the estimated subject item bank. For each year-wave-grade node, estimate only its latent mean and variance with item parameters fixed, and then calculate EAP ability and its standard error for every eligible student.
11. Retain raw ability on the fixed Year 1 metric as `theta_y1_metric`. Create the main analysis outcome `theta_y1_published_z` (also copied to `primary_outcome`) using the archived subject-specific Year 1 **endline comparison-group** mean and SD. Year 1 baseline is not the standardization population.
12. Save the primary dataset only if all three subject calibrations converge without warnings, all linked baseline/endline nodes are scored, all 255 fixed parameters match to numerical tolerance, student-node keys are unique, and no treatment field is exported.

The primary method ID is `concurrent_subject_all_final`.

## Prespecified robustness grid

The source of truth is [`config/irt_pipeline.yml`](../config/irt_pipeline.yml). The admissible concurrent grid is the full Cartesian product:

- anchor rule: strict-summary or the final purified rule with the required-link floor;
- calibration sample: all students or comparison students only;
- pooling scope: subject-pooled or grade-specific.

Additional isolated stress tests are:

- direct fixed-Year-1 node scoring;
- selected-path chained scoring;
- broad purification;
- the targeted DIF rule before adding the required-link floor;
- deterministic school-development calibration, evaluated through its validation-school scores;
- deliberately permissive ID-only links, retained as quarantined negative evidence;
- binary sum scores standardized either by subject × cohort × wave controls (the code-matched rule) or by subject × grade × cohort × wave controls (the reporting rule);
- each sum-score rule on the listed panel, all panel, and listed panel with consistent cross-wave metadata.

The method registry reports whether every method was declared, estimated, converged, partially covered, eligible for the correlation exercise, or quarantined. Partial models are never mistaken for the complete primary model, and pairwise sample sizes accompany every correlation.

## Correlation outputs

Two square matrices are produced:

- Year 3 score levels, after standardizing each method within year × wave × subject × grade. This removes arbitrary node location and asks whether methods rank students similarly.
- Year 3 baseline-to-endline changes, after standardizing changes within subject × grade. This is a stricter and noisier comparison.

Pearson and Spearman matrices and pairwise sample-size matrices are saved. Node-level diagnostics retain raw method means and SDs, which is where scale-location shifts should be investigated.

In the 2026-09-08 full run, the minimum correlation against the displayed IRT
variants was **0.9875 for levels** and **0.9665 for changes**; the binding case
was the WLE scoring stress test. The narrower set of sequential and direct IRT
links had a minimum level correlation above 0.998. Against standardized binary
sums, the minima were **0.9562 for levels** and **0.8832 for changes**. Thus
IRT modeling choices give very similar student ordering, while IRT versus
raw-sum scoring is strongly—but not perfectly—aligned.

## Output locations

All data-bearing outputs remain below the configured Dropbox `work_root`.

Primary analysis dataset:

```text
derived/y1_y3_irt/multiyear_irt_outcomes_primary.dta
derived/y1_y3_irt/multiyear_irt_outcomes_primary.csv
```

Long measurement-robustness dataset:

```text
derived/y1_y3_irt/multiyear_measurement_robustness_long.dta
derived/y1_y3_irt/multiyear_measurement_robustness_long.csv
```

Method registry, correlations, figures, and aggregate diagnostics:

```text
outputs/y1_y3_irt/06_outcome_construction/
```

Pipeline manifests and per-step logs:

```text
outputs/y1_y3_irt/00_pipeline/
```

Adversarial validation report:

```text
outputs/y1_y3_irt/08_adversarial_validation/ADVERSARIAL_VALIDATION_REPORT.md
```

## Current validation result

The 2026-09-08 full build completed all 35 steps with no failed step. The
primary file contains 56,183 student-node rows across the complete set of 66
Year 2 and Year 3 baseline/endline subject-by-grade nodes. The robustness file
contains 952,357 student-node-method rows from 22 scored methods; the registry
also records one joint item-ID stress test that is quarantined from comparisons.
All three primary subject calibrations converged without warnings; the fixed
Year 1 parameter counts are 104, 85, and 66; the plain-score standardization
identities hold to machine precision; and no treatment regression ran inside
the measurement build.

Sensitivity limitations are visible rather than suppressed:

- the all-student preferred grade-specific model scores 17 of 18
  subject-grade calibrations, while the comparison-school version scores 16;
- the subject-level strict rule converges but scores 63 rather than 66 nodes;
- the broad and older targeted purification rules converge but score only 53
  nodes because their anchor decisions disconnect parts of the network;
- the predetermined-school calibration converges and scores all 66 nodes;
- the deliberately permissive item-ID joint model now converges under the
  declared numerical bound, but remains quarantined because its matching rule
  is not accepted anchor evidence.

These limitations do not invalidate the complete, clean primary fit, but they constrain what each sensitivity can demonstrate.

The automated adversarial review completed 45 checks: 36 passed, nine raised
documented warnings, and none failed critically. Alternative IRT scores rank
students very similarly to the preferred score; the lowest Year 3 within-test
level correlation among the displayed sequential/direct IRT alternatives is
above 0.998. As expected, plain sum scores are less close: their level
correlations with the preferred IRT score are about 0.956--0.968 and their
change-score correlations are about 0.883--0.912. Other warnings disclose
local-dependence signals, three freely estimated discrimination parameters at
the numerical cap, large location/scale differences for some thin links, and
candidate-source statuses still awaiting collaborator confirmation. These are
visible decision gates, not critical coding failures. No outcome is marked
`final_outcome_approved = 1` yet.

## Software requirements

R packages: `digest`, `dplyr`, `haven`, `jsonlite`, `mirt`, `purrr`, `readr`, `stringr`, `tibble`, `tidyr`, and `yaml`.

Python packages: `openpyxl` and the Python standard library.

The final validation directory records `sessionInfo()` and every executed command. Seeds and warning thresholds are versioned in the configuration files.
