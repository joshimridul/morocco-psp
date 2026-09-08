# IRT outcome scaling design for the matched difference in differences studies

> This document records design development. Where an intermediate result below
> conflicts with `docs/IRT_PIPELINE_README.md`, the production README governs.

**Status:** Working specification for implementation and review  
**Immediate scope:** Preserve the published Year 1 scale and create provisional Year 3 IRT outcomes  
**Longer-run scope:** Subject-specific linked scales across years, rounds, cohorts, grades, forms, and samples

## 1. Decision summary

The published Year 1 outcomes and item parameters remain fixed. New Year 3 models must be placed on that metric only through verified unchanged items. A matching item ID or English summary is useful screening evidence, but it is not enough for a final link.

The primary outcome family is subject-specific. Arabic, French, and mathematics must never be combined into one IRT model. Within a subject, the basic analysis node is:

`year x wave x cohort/sample x administered grade x form/version x scoring context`.

The first scoring pass will calibrate Year 3 baseline and endline form nodes with Year 1 fixed item parameters wherever the direct link is adequate. Nodes without enough direct Year 1 anchors will be reached through explicitly documented Year 3 bridge edges. Scores produced before full item-version review are development outcomes, not final causal-analysis outcomes.

## 2. What Andy did in Year 1

The Year 1 production script and the paper implement the same core design:

1. Fit one unidimensional two-parameter logistic model per subject to binary endline items.
2. Link grade forms through overlapping items, freeing selected grade-specific parameters after logistic and Mantel-Haenszel DIF checks.
3. Append baseline responses and hold the previously estimated endline parameters fixed.
4. Free selected baseline item parameters judged to drift across rounds.
5. estimate expected-a-posteriori student ability scores.
6. Standardize each subject score to the mean and standard deviation of the Year 1 endline matched-comparison group.

The verified Year 1 model objects reproduce every delivered subject score to machine precision. The fixed-model transformation constants are:

| Subject | Year 1 endline comparison mean on raw theta | Year 1 endline comparison SD on raw theta |
|---|---:|---:|
| Arabic | -0.2400314007 | 0.9127664341 |
| French | -0.5166984276 | 0.7985084594 |
| Mathematics | -0.3713869650 | 0.8408824093 |

The published scale is therefore recoverable even though the available production do-file has reproducibility defects, including a treatment-variable naming inconsistency and no command that saves the model objects.

## 3. What must be preserved and what can improve

### Preserve exactly

- The delivered Year 1 scores used in the Year 1 paper.
- The verified Year 1 subject-specific 2PL item parameters.
- The Year 1 raw-theta metric and its published endline-comparison transformation.
- The distinction between binary IRT items and timed oral-reading counts.

### Improve for Years 2 and 3

- Use a machine-readable item-version and anchor decision table.
- Keep administered grade separate from item grade of origin.
- Represent form, wave, cohort, sample role, testlet, rubric, scoring, and exposure explicitly.
- Estimate node-specific latent distributions rather than assuming all grades and cohorts share one normal ability distribution.
- Report anchor effect sizes and uncertainty rather than relying on a p-value alone.
- Preserve treatment blindness during item screening and anchor purification.
- Carry model and linking uncertainty into sensitivity analyses.

## 4. Scale definitions

Each scored record will carry both of the following outcomes:

1. `theta_y1_metric`: the EAP estimate on the raw latent metric defined by the verified Year 1 item parameters.
2. `theta_y1_published_z`: the same estimate transformed with the fixed Year 1 endline-comparison mean and SD.

The second score is comparable to the published Year 1 score. It must use the Year 1 constants for every later year. Re-standardizing each later endline to its own comparison group would create a useful year-specific effect-size outcome but would destroy the common longitudinal origin and unit. Any year-specific standardization must therefore be stored under a different name and treated as a derived presentation scale.

## 5. Planned model sequence

### Model A  Published Year 1 reference

- Official Year 1 outcome: delivered score.
- Reference parameters: verified subject-specific Year 1 2PL item parameters.
- Reference transformation: fixed Year 1 endline-comparison mean and SD.

### Model B  Direct fixed-anchor Year 3 calibration

For each Year 3 subject-wave-grade-form node:

- exclude treatment fields from the calibration input;
- fix verified Year 1 anchor slopes and difficulties;
- estimate parameters for new Year 3 binary items;
- estimate the node ability mean and variance on the fixed Year 1 metric;
- obtain EAP scores and posterior standard errors; and
- retain cohort and sample metadata in the private outcome file.

This model is estimable only where the node has an adequate direct Year 1 anchor set with acceptable content and difficulty coverage.

### Model C  Chained Year 3 bridge calibration

For a node without an adequate direct Year 1 link:

1. select a previously calibrated source node connected by verified unchanged items;
2. fix the bridge-item parameters at the source-node values;
3. retain any direct verified Year 1 anchors as additional fixed constraints;
4. estimate the target-node distribution and new item parameters; and
5. record the complete path back to Year 1.

The number of links, weakest edge, testlet concentration, and accumulated uncertainty must be reported. A node remains unscored on the common metric when no defensible path exists.

### Model D  Joint multi-group sensitivity

After the node and edge registry is frozen, fit a subject-specific multi-group model with groups defined at least by wave, cohort/sample, administered grade, and form. Constrain only approved item versions. Compare scores and group moments with the staged fixed-anchor results.

### Model E  Control-only calibration sensitivity

Estimate new Year 2 and Year 3 parameters using comparison observations only, with the Year 1 parameters fixed, then score treatment observations against the frozen system. This is a sensitivity analysis, not an item-selection exercise.

### Model F  Rasch sensitivity

Fit a parsimonious Rasch or 1PL sensitivity model where the response structure supports it. Because the published Year 1 reference is a 2PL scale, the Rasch results require an explicit link back to the Year 1 metric and cannot replace the fixed-2PL primary outcome silently.

## 6. Outcome variants

The confirmatory candidate is the full subject score. Additional scores are secondary unless the analysis plan says otherwise:

- at-grade item subset;
- below-grade item subset;
- content-domain subset;
- cognitive-domain subset; and
- timed oral-reading fluency in natural units.

Subset EAP scores should mirror the Year 1 approach: use the full subject calibration, mask non-subset responses, and rescore. They are conditional subset scores under the full model, not separately calibrated constructs. A domain score is reported only when task count, testlet structure, dimensionality, and conditional precision support it.

## 7. Matched difference in differences use

The measurement model creates outcomes; it does not estimate the treatment effect. The causal analysis must merge the frozen outcome file with the approved design file only after anchor and scoring decisions are locked.

The principal Year 3 matched difference in differences analysis should retain:

- student panel structure where the same student is observed at baseline and endline;
- matched-pair-by-grade time controls or the pre-specified equivalent;
- clustering at the matched-pair level;
- explicit cohort/sample indicators and interactions required by the design;
- attrition and out-of-list sensitivity definitions; and
- the pre-specified multiple-testing hierarchy.

Treatment assignment must not determine which items or anchors are retained. Treatment-related DIF is a later sensitivity check on a frozen measurement system.

## 8. Required validation gates

A score is not final until all applicable gates pass:

1. canonical wave-specific sources are collaborator-confirmed;
2. item response scoring ties to the maps, forms, keys, and rubrics;
3. direct and bridge items pass full version review;
4. the form-and-sample graph is connected through defensible edges;
5. models converge without boundary or sign problems;
6. fit, local dependence, testlet structure, and dimensionality are acceptable or transparently qualified;
7. alternate anchor sets and link paths give substantively stable scores;
8. school- or cohort-held-out validation is satisfactory;
9. the fixed-parameter conversion reproduces Year 1 item response curves and scoring behavior; and
10. a separate causal-analysis script merges the frozen scores without changing the measurement rules.

## 9. Implemented development models as of 2026-09-07

The guarded pipeline now includes:

- hash registries for the Year 1 reference and provisional Year 2 inputs;
- aggregate Year 2 and Year 3 form-item administration registries;
- a version-aware Year 1-Year 2-Year 3 node and item-link graph;
- direct fixed-Year-1 node calibrations;
- selected-path chained calibrations that inherit fixed item parameters from an already linked parent;
- a pooled incomplete-booklet model for each subject using all linked Year 2 and Year 3 data;
- a comparison-group-only version of that pooled model; and
- a deterministic school-development/validation split that calibrates on development schools and scores validation schools out of sample; and
- aggregate structural, fixed-parameter, convergence, and score-sensitivity checks.

The Year 2 operational registry now enforces the binary/nonbinary boundary before the link graph is built. Of 1,688 administered Year 2 node-item occurrences, 1,613 have only observed zero/one responses and are eligible for binary IRT; 75 contain nonbinary observed values and are excluded. Tagged `.a` values are retained as administered don't-know responses and scored zero, while untagged system missing remains missing. This keeps continuous fluency and rubric measures out of the 2PL models.

The unrestricted multi-group specification is implemented but was not accepted as a completed result: the initial high-dimensional fits exceeded the bounded run window. The efficient pooled subject model fixes its calibration mixture to a standard normal distribution, freezes the resulting item bank, and then estimates a separate mean and variance for each Year 3 scoring node. This is a sensitivity model, not a substitute for the selected-path model or the still-pending full multi-group fit.

The binary-only strict school-held-out subject model converged for Arabic and scored 12 Year 3 nodes. Across 6,100 held-out student-node comparisons, its scores closely reproduce the full pooled calibration: the minimum node correlation is 0.999, the largest absolute node mean difference is 0.044 raw-theta units, and the largest RMSE is 0.056. The French and mathematics calibrations hit the iteration cap and were not scored. The held-out evidence therefore supports the stability of the pooled Arabic item bank, but it does not resolve the larger metric-location differences between pooled and chained links or validate French and mathematics.

Treatment-blind Year 2–Year 3 purification now evaluates 225 grade, wave, year, pilot, and cohort links using clustered logistic and Mantel–Haenszel evidence with iterative purification and Holm correction. The comparison-only pass produces 560 robust item-link frees after iteration. A broad profile applying every category is over-parameterized and does not converge for Arabic. The closer Andy-core profile applies 157 operational-endline grade and baseline-drift frees; all three subject calibrations converge. On overlapping nodes, its correlations with the original pooled model are at least 0.989 and its largest absolute mean shift is 0.243 raw-theta units. It lacks a balanced Year 3 mathematics grade. A separate mathematics bridge sensitivity requires both DIF detectors, retains five provisional anchors per screened link, and permits four-anchor exact-summary graph edges for mathematics only. That profile links all 12 Y3 mathematics grade-wave nodes and all three subject models converge. Detailed rules and results are in `docs/MULTIYEAR_ANCHOR_PURIFICATION.md`.

No development score is approved for causal use. The strict graph still leaves three Year 3 mathematics nodes without a five-item automated path; the complete mathematics result relies on explicitly provisional four-anchor links and floor-retained items. The project lead confirmed on 2026-09-08 that unchanged mathematics IDs across Years 2 and 3 guarantee identical item content, key, scoring, stimulus, format, and administration, resolving the mathematics version-equivalence gate. Analytical sparse-link sensitivity, nonconverged school-held-out French and mathematics models, and Year 2/Year 3 source canonicality remain unresolved.
