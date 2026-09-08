# Year 2–Year 3 anchor purification audit

> Historical development analysis. Profile names and numerical results below
> document earlier iterations; they are not the reader-facing specification.
> The production rule is described in `docs/IRT_PIPELINE_README.md`, and the
> resolved Arabic Grade 1–2 link audit is in
> `docs/ARABIC_GRADE_1_2_LINK_AUDIT.md`.

**Run date:** 2026-09-07  
**Status:** Development evidence only; no anchor or outcome is approved

## Purpose

This exercise reproduces the core logic of the Year 1 workflow without changing any delivered Year 1 score or item parameter. It evaluates whether exact-summary common binary items can reasonably share parameters across administered grades, waves, years, pilots, and cohorts. Treatment effects are not used to select items.

The primary screen uses comparison observations whenever a treatment-assignment field exists. A source without treatment assignment, notably the Year 2 pilot, uses all observations. A second all-student pass omits treatment from every model and is diagnostic only; its flags cannot determine the anchor set.

## Response and missing-data rules

- Only item occurrences already verified to have observed values in `{0,1}` enter the 2PL/DIF universe.
- Tagged `.a` responses are treated as administered “don't know” responses and scored zero.
- Ordinary system missing remains missing.
- The upstream Year 2 registry excludes 75 nonbinary node-item occurrences. The purification screen found zero additional nonbinary occurrences among the 3,519 link-graph rows.
- Duplicate student-form records are resolved deterministically using answered-item count, duration, and source-row order. Identifiers are used only in memory and are never written to audit outputs.

## Links tested

The comparison-only screen evaluates 225 links and 5,907 item-link decisions:

| Link type | Links |
|---|---:|
| Within-node cohort DIF | 84 |
| Pilot-to-main drift | 44 |
| Within-year adjacent-grade DIF | 41 |
| Across-year same-grade drift | 31 |
| Within-year baseline–endline drift | 13 |
| Across-year upward grade transition | 12 |

Cross-year grade-transition links only compare an earlier-year grade with the next higher grade in the later year. Reverse grade transitions are not treated as cohort progression links.

## Statistical method

For each item and link, a logistic model conditions on the proportion correct on the remaining common-item set and estimates uniform and nonuniform group effects. Standard errors are clustered by school. A robust two-degree-of-freedom Wald test evaluates the group main effect and group-by-rest-score interaction jointly. A stratified Mantel–Haenszel comparison provides a second DIF measure.

P-values are Holm-adjusted within link and iteration. A parameter is automatically freed in the comparison-only development sensitivity only when:

1. clustered inference is reliable with at least 10 clusters and a converged nonseparated model;
2. the adjusted joint logistic or Mantel–Haenszel p-value is below 0.05; and
3. at least one material-effect warning holds: uniform odds ratio outside `[0.67,1.50]`, absolute nonuniform logit coefficient above 0.50, incremental pseudo-R-squared relative to the reduced item model above 0.02, or absolute Mantel–Haenszel delta above 1.00.

Flagged items are removed from the conditioning score and the link is re-estimated for up to three iterations. Thresholds are development rules, not final substantive judgments.

## Screening results

The final comparison-only decisions are:

| Decision | Item-link rows |
|---|---:|
| Retain constraint, development only | 2,454 |
| Review: material effect only | 2,806 |
| Free in development sensitivity | 560 |
| Review: unreliable or insufficient inference | 80 |
| Review: statistical signal only | 7 |

The 560 freed item-link rows translate to 444 distinct node-item parameter frees in the broad targeted specification and 48 additional cohort-specific item frees. The largest concentrations occur in Year 3 lower-grade links: Arabic baseline Grades 1–2, Arabic Grade 1 baseline–endline, French Grade 1 baseline–endline, and French baseline Grades 1–2. Those concentrations require form, scoring, and administration review; they should not be interpreted as hundreds of globally “bad items.”

The all-student diagnostic produces 683 first-pass flags, versus 452 in the comparison-only first pass. The classifications agree for 91.4% of all 5,907 item-link rows, but the Jaccard overlap among flagged sets is only 38.2%. The all-student pass therefore contains materially different selection information, especially for wave and cohort comparisons, and is not used to freeze constraints.

## Constraint profiles

Two refit profiles are retained.

### Broad diagnostic profile

The broad profile applies robust flags from grade, wave, year, pilot, and cohort comparisons. It frees the implicated administration instead of dropping the item globally:

- baseline for baseline–endline drift, preserving the Year 1-style endline reference;
- upper grade for adjacent-grade DIF;
- later year for cross-year drift;
- pilot for pilot-to-main drift; and
- focal cohort B for cohort DIF.

This profile leaves 81 of 102 nodes connected to Year 1 by paths with at least five retained anchors. French and mathematics converge, but Arabic reaches the 1,500-cycle cap. The valid output contains 27,125 scores over 34 baseline/endline nodes. This profile is too parameter-rich to be the preferred pooled scale.

### Andy-core profile

The closer Year 1 replication uses only:

1. adjacent-grade DIF in operational endline forms; and
2. baseline–endline drift, freeing the baseline occurrence.

Across-year, pilot, and cohort results remain review/sensitivity evidence and do not determine this core scale. The core applies 157 node-item frees. All three subject models converge without warnings and score 42,119 records over 53 baseline/endline nodes.

All 255 fixed Year 1 item-parameter rows in the Andy-core model reproduce the archived discrimination and difficulty parameters within `5.8e-15`. The delivered Year 1 outcomes and their reference transformation are untouched.

On the 42,119 records also scored by the original pooled strict model, node correlations range from 0.989 to 1.000. The largest absolute node mean shift is 0.289 published-score SD or 0.243 raw-theta units; the largest raw-theta RMSE is 0.327. This is far smaller than the earlier 1.60 raw-theta chained-versus-pooled location discrepancy, but it does not resolve that discrepancy because the weakest disconnected nodes remain outside the core result.

Balanced Year 3 baseline/endline coverage under the Andy-core profile exists for Arabic Grades 3–6 and all six French grades. Mathematics has no grade with both waves linked after purification, so a Year 3 mathematics matched-DiD effect cannot be reported from this profile.

### Mathematics bridge sensitivity

The Andy-core rule is too brittle for mathematics because several operational links contain only five to eight common items. A separate treatment-blind sensitivity therefore changes mathematics only:

1. a mathematics occurrence is eligible for an automatic DIF/drift free only when both the Holm-adjusted joint logistic test and the Holm-adjusted Mantel–Haenszel test are below 0.05, clustered inference is reliable, and a material-effect warning holds;
2. at least five common items are retained in each directly screened link, with eligible frees ranked by the weaker adjusted p-value and then material severity; and
3. exact-summary graph links may contain four anchors for mathematics, while the minimum remains five for Arabic and French.

Items retained because of the five-anchor floor are labeled `retain_provisional_math_bridge_floor`; their affected mapping occurrences are labeled `retained_provisional_math_bridge_floor`. They are identification anchors for a sensitivity model, not approved clean anchors. Seventeen item-link decisions and 22 node-item occurrences carry this explicit provisional flag.

On 2026-09-08, the project lead confirmed that mathematics item IDs are immutable across Years 2 and 3: an unchanged ID denotes the same administered item, answer key, scoring rule, stimulus, and format, and edited items receive a new ID. This resolves the mathematics item-version/content review question by collaborator confirmation. The provisional status of the floor-retained items now reflects empirical DIF and sparse-link uncertainty only, not uncertainty about whether matching IDs denote different content.

The four-anchor graph threshold is sufficient for the three otherwise missing nodes: Year 3 Mathematics baseline Grade 4, endline Grade 3, and endline Grade 6 each has a four-item exact-summary link to an already connected node. The resulting graph links all 12 Year 3 mathematics baseline/endline grade-wave nodes. All three subject models converge without warnings and score 52,483 records across 63 baseline/endline nodes.

All 255 fixed Year 1 item parameters remain unchanged to better than `6e-15`. On mathematics records also scored by the original pooled strict model, score correlations are at least 0.999; the largest absolute node mean shift is 0.109 raw-theta units and the largest raw-theta RMSE is 0.122. The sensitivity therefore restores coverage without recreating the earlier 1.60 raw-theta discrepancy on overlapping nodes.

## Matched-DiD sensitivity

The established Year 3 matched-DiD grid was rerun without changing its panel, matched-pair-by-grade fixed effects, clustering, or weighting rules. Only the outcome method changed.

For the preferred Andy-core profile:

| Available subject panel | Andy-core IRT | SE | Original pooled strict on its full panel | Exact-panel strict minus Andy-core |
|---|---:|---:|---:|---:|
| Arabic, Grades 3–6 only | 0.274 | 0.076 | not directly comparable | -0.026 (SE 0.005) |
| French, Grades 1–6 | 0.469 | 0.053 | 0.471 | 0.002 (SE 0.006) |
| Arabic + French available cells | 0.451 | 0.053 | not directly comparable | -0.002 (SE 0.006) |
| Mathematics, Grades 1–6 | 0.463 | 0.075 | 0.471 | -0.009 (SE 0.003) |

The exact-panel contrast is the appropriate comparison. It implies that Andy-core purification raises the Arabic Grades 3–6 effect by 0.026 SD, lowers the French effect by 0.002 SD, and raises the combined available-cell effect by 0.002 SD. These are small changes relative to the treatment effects themselves.

For mathematics, the exact-panel contrast compares the original strict and bridge scores only where both exist; strict minus bridge is -0.009 SD (SE 0.003). On the bridge model's complete six-grade panel, the same-student do-file-style plain score effect is 0.453 SD, only 0.010 SD below the IRT estimate.

On the same student panels, the do-file-style standardized binary sums are 0.162 for Arabic Grades 3–6, 0.538 for French, and 0.496 for the combined available cells. The differences between IRT and sum scores are therefore larger than the differences between purified and unpurified IRT. They reflect outcome weighting and scale construction and were not used to choose items.

For the directly aligned Cohort 3 French headline, Andy-core IRT is 0.407 (SE 0.050), compared with 0.466 (SE 0.083) in the Ministry report, a difference of -0.059 SD. The corresponding original pooled strict estimate is 0.409, so purification barely changes this comparison. The Andy-core Arabic headline covers Grades 3–6 only and is not directly comparable with the Ministry's all-grade Arabic headline.

The mathematics bridge sensitivity is directly aligned to all six Cohort 3 grades. Its headline is 0.499 SD (SE 0.043), compared with 0.497 SD (SE 0.041) in the Ministry report. The overall available-subject headline is 0.409 SD (SE 0.039), compared with the Ministry's 0.403 SD.

| Mathematics grade | Ministry sum score | Math-bridge IRT | Difference |
|---:|---:|---:|---:|
| 1 | 0.348 | 0.361 | 0.013 |
| 2 | 0.603 | 0.594 | -0.009 |
| 3 | 0.547 | 0.577 | 0.030 |
| 4 | 0.480 | 0.434 | -0.046 |
| 5 | 0.694 | 0.685 | -0.009 |
| 6 | 0.232 | 0.291 | 0.059 |

For directly aligned Cohort 3 grade cells:

| Subject | Grade | Ministry sum score | Andy-core IRT | Difference |
|---|---:|---:|---:|---:|
| Arabic | 3 | 0.247 | 0.408 | 0.161 |
| Arabic | 4 | 0.133 | 0.116 | -0.017 |
| Arabic | 5 | 0.208 | 0.281 | 0.073 |
| Arabic | 6 | 0.214 | 0.295 | 0.081 |
| French | 1 | 0.836 | 0.637 | -0.199 |
| French | 2 | 0.473 | 0.343 | -0.130 |
| French | 3 | 0.566 | 0.436 | -0.130 |
| French | 4 | 0.442 | 0.532 | 0.090 |
| French | 5 | 0.259 | 0.292 | 0.033 |
| French | 6 | 0.222 | 0.230 | 0.008 |

These grade differences are similar to the earlier strict-IRT versus Ministry pattern. They warrant measurement review, especially lower-grade French and Arabic Grade 3, but cannot be used as anchor-selection criteria.

## Interpretation

The exercise supports four conclusions:

1. Grade and wave invariance cannot be assumed merely from item IDs or summary hashes. There is concentrated, material instability in specific lower-grade links.
2. The essential Andy-style purification is computationally viable: all three subject calibrations converge and student rankings remain very stable.
3. A model that frees every year, pilot, cohort, grade, and wave flag simultaneously is over-parameterized for these data and fails for Arabic.
4. Mathematics can be made complete only through an explicitly less conservative sensitivity: consensus DIF evidence, a five-anchor screened-link floor, and three four-anchor graph links. This is strong enough for a robustness result, not yet for an approved primary scale.

## Remaining blockers

- Exact prompt, stimulus, options, key/rubric, administration, scoring, layout, and exposure equivalence is not yet verified.
- Direct Y1 anchors remain fixed at their archived parameters but were not empirically retested against Y1 response data in this pass.
- Year 2 and Year 3 source canonicality still requires collaborator confirmation.
- Testlet/stimulus metadata remain incomplete.
- Large lower-grade flag clusters require item-level content and scoring review.
- The scale is not ready to freeze for Arabic Grades 1–2. Complete mathematics coverage is available in the bridge specification; its remaining gate is analytical sensitivity to the four-anchor paths and floor-retained items, not manual item-version review.

## Reproducible outputs

Tracked code:

- `src/21_y1_y3_irt/run_multiyear_anchor_purification.R`
- `src/21_y1_y3_irt/build_targeted_purified_constraints.R`
- `src/21_y1_y3_irt/run_joint_multigroup_scoring.R`
- `src/21_y1_y3_irt/validate_multiyear_anchor_purification.R`
- `src/22_treatment_effects/run_y3_irt_treatment_sensitivity.R`
- `src/22_treatment_effects/validate_y3_irt_treatment_sensitivity.R`

Aggregate evidence and validation are written below `work_root/outputs/y1_y3_irt/05_anchor_purification/`. Deidentified score files and constraint mappings are written below `work_root/derived/y1_y3_irt/`. No data-bearing output is written to GitHub, and no legacy Dropbox source is modified.
