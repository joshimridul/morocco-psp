# Year 3 IRT treatment-effect sensitivity

> Historical development analysis. The missing-node and treatment-effect
> statements below predate the subject-neutral required-link floor and are not
> current results. Use the compiled Ministry IRT report and
> `docs/IRT_PIPELINE_README.md` for the release-candidate results.

Status: **development only; not an approved paper result**.

## Question and headline result

This exercise asks whether the estimated Year 3 baseline-to-endline matched difference-in-differences effect is sensitive to the assessment outcome construction. It compares the binary raw-total score with the strict chained, subject-pooled, comparison-calibrated, grade-specific, direct-anchor, provisional-anchor, and school-development IRT outcomes.

On the identical 12,971-student strict-core panel, the pooled overall estimates are tightly grouped:

| Outcome | Effect | SE | 95% CI |
|---|---:|---:|---:|
| Binary raw total, do-file standardization | 0.352 | 0.043 | [0.267, 0.437] |
| Strict chained IRT | 0.364 | 0.044 | [0.276, 0.451] |
| Strict subject-pooled IRT, all calibration records | 0.345 | 0.038 | [0.269, 0.421] |
| Strict subject-pooled IRT, comparison-only calibration | 0.337 | 0.039 | [0.261, 0.413] |

The IRT-minus-plain differences are 0.012 SD for chained, -0.007 SD for pooled-all, and -0.015 SD for pooled-comparison. Clustered tests of these same-panel differences have p-values 0.494, 0.574, and 0.264, respectively. This is encouraging evidence that the main overall effect is not being manufactured by the IRT method.

The approximately 1.60 raw-theta location discrepancy remains a measurement blocker, but it does not translate into a comparably large treatment-effect discrepancy. Across the three strict core models, the pooled overall treatment-effect range is 0.027 SD. The largest pooled subject-specific range is 0.037 SD, in Maths. Some small method contrasts are precisely estimated, so the models are not numerically identical; the magnitude is far below 1.60 theta units.

## Post-purification update

The treatment grid now includes a comparison-only, Andy-style purification sensitivity. It first screens operational endline items for adjacent-grade DIF, then appends baseline evidence and frees baseline occurrences with wave drift. The archived Year 1 parameters and endline-control transformation remain unchanged.

All three subject calibrations converge, but the purified link graph supplies balanced Year 3 baseline/endline coverage only for Arabic Grades 3–6 and French Grades 1–6. Mathematics has no same-grade two-wave panel and is not estimated. The available effects are 0.274 SD (SE 0.076) for Arabic Grades 3–6 and 0.469 SD (SE 0.053) for French. On exactly the same students, these differ from original pooled strict IRT by +0.026 SD and -0.002 SD. The combined available Arabic-plus-French estimate changes by +0.002 SD.

For Cohort 3 French, the purified estimate is 0.407 SD (SE 0.050), compared with the Ministry's 0.466 SD (SE 0.083) and the original pooled strict estimate of 0.409 SD. The purification therefore leaves the French headline comparison essentially unchanged. There is no valid purified full three-subject overall estimate.

### Mathematics bridge update

A separate mathematics sensitivity now restores all six baseline/endline grade panels without changing the Arabic or French rules. It requires concordant adjusted logistic and Mantel–Haenszel DIF evidence, retains at least five provisional anchors in every directly screened mathematics link, and permits exact-summary four-anchor graph edges for mathematics only. The three newly connected Y3 nodes each have four such anchors. This profile is explicitly provisional and is not the frozen primary scale.

The all-cohort equal-weight mathematics effect is 0.463 SD (SE 0.075). On the identical students, the do-file-style standardized sum-score effect is 0.453 SD. On the subset supported by the original strict IRT graph, strict minus bridge is -0.009 SD (SE 0.003), so the restored scale does not materially change the effect where both methods are observed.

For the directly comparable Cohort 3 block, mathematics IRT is 0.499 SD (SE 0.043), versus 0.497 SD (SE 0.041) in the Ministry report. The grade-specific bridge estimates are 0.361, 0.594, 0.577, 0.434, 0.685, and 0.291 SD for Grades 1–6. Their differences from the Ministry estimates are 0.013, -0.009, 0.030, -0.046, -0.009, and 0.059 SD. Thus every mathematics grade is available and the largest absolute discrepancy is 0.059 SD.

With the new mathematics coverage, the Cohort 3 available-subject overall effect is 0.409 SD (SE 0.039), compared with the Ministry's 0.403 SD. Arabic Grades 1–2 remain absent from the purified scale, so this overall result still does not have full three-subject coverage in those two grades.

## Estimand and inherited specification

The Year 3 do-files implement a balanced two-wave student panel with:

- baseline treatment assignment;
- student fixed effects;
- post-by-matched-pair-by-grade fixed effects;
- standard errors clustered by matched pair;
- equal total cohort weight in pooled regressions; and
- PDS-LASSO-selected baseline covariates interacted with post.

For a balanced two-wave panel, the unadjusted core is algebraically equivalent to a first-difference regression of endline minus baseline score on treatment with matched-pair-by-grade fixed effects. The current script estimates that core and clusters by matched pair. It uses equal total cohort weight within the exact pooled regression subset.

The registered Year 3 wave-specific development inputs do not contain the full PDS-LASSO candidate covariate set. This run therefore omits the covariate adjustment and is a measurement-method sensitivity, not a final replication of the paper table.

The estimand is the change from the Year 3 baseline to the Year 3 endline. It is **not** the cumulative one-, two-, or three-year exposure effect defined from each cohort's original program baseline.

## Outcome construction

### IRT outcomes

All IRT estimates use `theta_y1_published_z`. This transformation uses the fixed Year 1 **endline matched-comparison** mean and SD. Year 1 baseline is not the reference. The delivered Year 1 parameters and scale constants are not re-estimated.

### Plain outcomes

The raw comparison includes only item-form occurrences marked binary in the verified Year 3 manifest. For the baseline and endline waves this is 1,277 item-form occurrences. A second response-value guard found zero manifest-listed occurrences with observed values outside `{0,1}`. Non-binary items do not enter score construction or estimation.

Two control-group standardizations are reported because the production code and written report differ:

1. `plain_code`: subject by cohort by wave, matching the do-file implementation.
2. `plain_report_grade`: subject by grade by cohort by wave, matching the report's written description.

On the full listed panel, their pooled overall effects are 0.355 SD and 0.365 SD. The 0.010 SD difference is small overall, although subject- and cohort-specific differences can be larger. The Cohort 3 grade-table reconciliation below strongly supports `plain_code` as the operational rule that generated the Ministry results; collaborator confirmation is still needed to correct the conflicting prose.

## Reconciliation with the Ministry reports

Only Cohort 3's one-year result is directly aligned in time. The new diagnostic uses the Year 3 baseline and endline for every cohort. In contrast, the Ministry report's Cohort 1 three-year and Cohort 2 two-year estimates begin at each cohort's original pre-program baseline. The Ministry's pooled one-year estimate combines first-year effects observed in three different academic years and is not comparable with the new pooled current-Year-3 estimate.

For the comparable Cohort 3 headline:

| Outcome | Ministry raw score | New plain, do-file rule | New plain, prose rule | Chained strict IRT | Pooled strict-all IRT | Pooled strict-control IRT |
|---|---:|---:|---:|---:|---:|---:|
| Overall | 0.403 | 0.385 | 0.425 | 0.417 | 0.378 | 0.374 |
| Arabic | 0.250 | 0.199 | 0.268 | 0.335 | 0.260 | 0.259 |
| French | 0.466 | 0.469 | 0.509 | 0.413 | 0.409 | 0.400 |
| Maths | 0.497 | 0.484 | 0.491 | 0.574 | 0.542 | 0.547 |

Thus every new overall estimate is within 0.03 SD of the Ministry's 0.403 SD headline. The IRT results shift some effect from French toward Arabic and Maths, but do not change the overall conclusion.

The separate grade report supplies 24 Cohort 3 grade-by-outcome cells. The do-file-style plain score reproduces those published coefficients with a mean absolute difference of 0.020 SD and a maximum difference of 0.058 SD. The prose-style within-grade standardization has a mean absolute difference of 0.063 SD and a maximum difference of 0.275 SD. This is strong empirical evidence that the reported tables used the across-grade subject-by-cohort-by-wave standardization found in the production do-file, not the within-grade standardization described in the narrative.

The IRT grade results are less uniform. Strict models estimate 21 of the 24 cells because three Maths nodes remain unlinked. Mean absolute differences from the Ministry raw-score cells range from 0.063 to 0.072 SD, with some differences above 0.20 SD. On identical student panels, the largest score-method contrasts include higher chained-IRT effects for Arabic Grades 2 and 3 and lower IRT effects for French Grade 1. These cells should prioritize link and item diagnostics, but treatment-effect differences must not be used mechanically to select or reject anchors.

## Subject results on the strict common panel

| Subject | Plain total | Chained IRT | Pooled-all IRT | Pooled-control IRT | N |
|---|---:|---:|---:|---:|---:|
| Arabic | 0.078 | 0.140 | 0.111 | 0.109 | 4,966 |
| French | 0.538 | 0.467 | 0.471 | 0.453 | 4,961 |
| Maths | 0.473 | 0.504 | 0.471 | 0.468 | 2,992 |
| Overall | 0.352 | 0.364 | 0.345 | 0.337 | 12,971 |

The agreement is strongest for Maths under the pooled models. French IRT effects are about 0.07-0.09 SD below the plain effect on the same panel; the clustered unadjusted contrasts are detectable at conventional levels in this development run. Arabic IRT effects are about 0.03-0.06 SD above the plain effect, with wider uncertainty. These subject differences merit follow-up even though they offset in the overall estimate.

## Coverage explains the apparently large spread across all models

The unrestricted principal comparison ranges from 0.111 to 0.450 SD, but the endpoints do not represent a common three-subject sample:

- direct strict and direct provisional have balanced baseline/endline coverage for Arabic and French only;
- the school-development model converged only for Arabic;
- grade-specific strict includes all subjects but has narrower Maths coverage; and
- chained strict, pooled strict-all, and pooled strict-comparison use identical student panels.

For example, direct strict gives 0.450 SD, while the plain score on that exact two-subject panel gives 0.509 SD. The direct IRT-minus-plain contrast is -0.060 SD, not +0.095 SD relative to the full-sample plain result. The full-sample comparison would confound measurement with coverage.

## Data and specification checks

- The registered Year 3 baseline and endline file hashes matched the source registry at run time. Both sources still carry `requires_collaborator_confirmation` canonicality status.
- Deterministic de-duplication removed 42 baseline and 29 endline duplicate student-subject-grade rows, using the same response-count, duration, and source-row precedence as the IRT scoring code.
- The raw balanced panel contains 15,061 records. The listed-panel restriction leaves 14,975; 14,821 remain in informative pair-by-grade cells with both treatment arms.
- Four balanced records have cross-wave treatment or cohort metadata disagreement. Baseline assignment remains authoritative. Dropping the four records leaves the main estimates unchanged to reported precision.
- Including the unresolved baseline `out_list` flags changes the core pooled overall estimates by at most about 0.002 SD.
- The main listed-panel regression sample has 264 schools in 132 informative matched pairs.
- All 30 automated aggregate validation checks pass. No identifiers or student-level analysis files are written by this exercise.

## Reproducible files

Tracked scripts:

- `src/22_treatment_effects/run_y3_irt_treatment_sensitivity.R`
- `src/22_treatment_effects/validate_y3_irt_treatment_sensitivity.R`
- `src/22_treatment_effects/plot_y3_irt_treatment_sensitivity.R`
- `src/22_treatment_effects/compare_y3_ministry_report.R`

Aggregate tables, run metadata, validation results, and figures are written below:

`work_root/outputs/y1_y3_irt/06_treatment_effect_sensitivity/`

The run writes no student-level output. Existing deidentified IRT outcomes remain under `work_root/derived/y1_y3_irt/` and remain unapproved.

## Next decision steps

1. Treat the production do-file standardization as the operational legacy rule and obtain collaborator confirmation to correct the conflicting report prose.
2. Recover and register the exact covariate inputs needed for the production PDS-LASSO adjustment, then repeat this comparison without using the forbidden combined file as the starting source.
3. Diagnose the long-path lower-grade location shifts item by item and link by link, while keeping treatment outcomes out of anchor-selection decisions.
4. After the measurement rules are frozen, run treatment-related DIF and the pre-specified anchor-set robustness suite.
