# Year 1 reference to Year 3 IRT development runbook

> **Superseded for execution:** use the one-click [`IRT_PIPELINE_README.md`](IRT_PIPELINE_README.md) and `Rscript src/21_y1_y3_irt/run_irt_pipeline.R config/paths.local.yml`. The command list below is retained only as historical detail; it mixes earlier development and treatment-effect stages and is not the production measurement build.

This runbook executes the development-only IRT pipeline. It never modifies a Year 1, Year 2, or Year 3 Dropbox source. Aggregate diagnostics and student-level derived outcomes are written only below the configured `work_root`. Every current outcome remains unapproved.

## Model roles

- `direct`: separate Year 3 wave-subject-grade 2PL models with Year 1 parameters fixed. Unsupported nodes are skipped.
- `chained`: separate node models that use either fixed Year 1 anchors or fixed item parameters inherited from the selected parent path.
- `subject_pooled_mixture`: one incomplete-booklet 2PL item calibration per subject using all linked Year 2 and Year 3 records. The calibration mixture is fixed to a standard normal distribution for stability. After item parameters freeze, each Year 3 node receives a separately estimated latent mean and variance before all students are scored.
- `grade_specific_mixture`: the same pooled approach within administered subject-grade. This is a sensitivity model.
- `subject_pooled` and `grade_specific`: unrestricted multi-group implementations with free group means and variances during item calibration. The first high-dimensional runs exceeded the bounded execution window and are not completed results.

Arabic, French, and mathematics are always separate constructs. The pipeline does not fit a cross-subject latent factor.

Only verified binary response columns enter a 2PL model. An observed `1` is correct, an observed `0` and tagged `.a` (don't know) are incorrect, and untagged system missing remains missing. A Year 2 node-item occurrence is excluded from IRT when any observed response lies outside `{0,1}`; continuous oral-fluency and rubric measures remain separate outcomes.

## Reproducible execution order

Run from the GitHub repository root.

```bash
python3 src/00_inventory/build_y2_source_registry.py --config config/paths.local.yml
Rscript src/21_y1_y3_irt/build_y2_operational_registry.R config/paths.local.yml
python3 src/21_y1_y3_irt/build_multiyear_link_graph.py --config config/paths.local.yml

Rscript src/21_y1_y3_irt/run_multiyear_chained_scoring.R config/paths.local.yml strict_summary
Rscript src/21_y1_y3_irt/run_multiyear_chained_scoring.R config/paths.local.yml provisional_id

Rscript src/21_y1_y3_irt/run_joint_multigroup_scoring.R config/paths.local.yml strict_summary all subject_pooled_mixture
Rscript src/21_y1_y3_irt/run_joint_multigroup_scoring.R config/paths.local.yml strict_summary comparison_only subject_pooled_mixture
Rscript src/21_y1_y3_irt/run_joint_multigroup_scoring.R config/paths.local.yml strict_summary development_schools subject_pooled_mixture
Rscript src/21_y1_y3_irt/run_joint_multigroup_scoring.R config/paths.local.yml strict_summary all grade_specific_mixture

# Treatment-blind DIF/drift purification. The comparison-only pass determines
# development frees; the all-student pass is diagnostic only.
Rscript src/21_y1_y3_irt/run_multiyear_anchor_purification.R config/paths.local.yml comparison_only
Rscript src/21_y1_y3_irt/run_multiyear_anchor_purification.R config/paths.local.yml all_students_blinded
Rscript src/21_y1_y3_irt/run_multiyear_anchor_purification.R config/paths.local.yml comparison_only math_bridge5
Rscript src/21_y1_y3_irt/build_targeted_purified_constraints.R config/paths.local.yml broad
Rscript src/21_y1_y3_irt/build_targeted_purified_constraints.R config/paths.local.yml andy_core
Rscript src/21_y1_y3_irt/build_targeted_purified_constraints.R config/paths.local.yml andy_core_math_bridge5
Rscript src/21_y1_y3_irt/run_joint_multigroup_scoring.R config/paths.local.yml purified_strict all subject_pooled_mixture
Rscript src/21_y1_y3_irt/run_joint_multigroup_scoring.R config/paths.local.yml purified_andy_core all subject_pooled_mixture
Rscript src/21_y1_y3_irt/run_joint_multigroup_scoring.R config/paths.local.yml purified_andy_core_math_bridge5 all subject_pooled_mixture
Rscript src/21_y1_y3_irt/validate_multiyear_anchor_purification.R config/paths.local.yml

Rscript src/21_y1_y3_irt/validate_irt_sensitivity.R config/paths.local.yml

Rscript src/22_treatment_effects/run_y3_irt_treatment_sensitivity.R config/paths.local.yml
Rscript src/22_treatment_effects/compare_y3_ministry_report.R config/paths.local.yml
Rscript src/22_treatment_effects/validate_y3_irt_treatment_sensitivity.R config/paths.local.yml
Rscript src/22_treatment_effects/plot_y3_irt_treatment_sensitivity.R config/paths.local.yml

# Exact Ministry design panels: all cohorts, exposure lengths, grades,
# heterogeneity groups, and stable-sample headline estimates.
Rscript src/22_treatment_effects/prepare_ministry_multiyear_irt_panels.R config/paths.local.yml
/Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp -b do /absolute/repo/path/src/22_treatment_effects/run_ministry_multiyear_irt_results.do '"/absolute/work_root/path"'
/Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp -b do /absolute/repo/path/src/22_treatment_effects/run_ministry_stable_irt_results.do '"/absolute/work_root/path"'
Rscript src/22_treatment_effects/compare_ministry_multiyear_irt_results.R config/paths.local.yml
Rscript src/22_treatment_effects/validate_ministry_multiyear_irt_results.R config/paths.local.yml
Rscript src/22_treatment_effects/build_ministry_multiyear_irt_report.R config/paths.local.yml
python3 -m unittest discover -s tests -v
```

The conflict-screened provisional-ID pooled subject model can be invoked by replacing `strict_summary` with `provisional_id`. The current run hit the iteration cap for all three subjects and is quarantined. Do not use it to create outcomes merely because it adds three form nodes.

## Main output locations under `work_root`

- `outputs/y1_y3_irt/00_y2_sources/`: Year 2 source hashes, operational summaries, and source blockers.
- `outputs/y1_y3_irt/01_multiyear_link_graph/`: item occurrences, item-pair links, node edges, selected paths, and version-review queues.
- `outputs/y1_y3_irt/03_chained_scoring/`: chained model and item-parameter diagnostics.
- `outputs/y1_y3_irt/04_joint_multigroup/`: pooled and multi-group sensitivity diagnostics.
- `outputs/y1_y3_irt/05_anchor_purification/`: treatment-blind DIF/drift evidence, iterative decisions, targeted constraint profiles, sample-sensitivity comparisons, and aggregate validation.
- `outputs/y1_y3_irt/05_validation/`: model-run registry, structural QA, fixed-parameter fidelity, node score sensitivity, and consolidated blockers.
- `outputs/y1_y3_irt/06_treatment_effect_sensitivity/`: aggregate Year 3 within-year matched-DiD estimates, exact-panel outcome contrasts, sample and item audits, validation results, and figures.
- `outputs/y1_y3_irt/07_ministry_multiyear_results/`: aggregate estimates and Ministry comparisons for every reported headline, grade, heterogeneity, and stable-sample cell; private analysis inputs remain in its `analysis_inputs/` subdirectory below `work_root`.
- `derived/y1_y3_irt/`: student-level development outcomes. These files contain deidentified panel keys and must remain outside GitHub.

The all-Ministry-panel preparation begins from the six wave-specific analysis
files. The legacy combined file is consulted read-only only to reproduce the
replacement-baseline exclusion in the previously reported stable-sample table;
it is not an item-response or score source. The associated hash and role are
recorded in `stable_sample_lineage_registry.csv`.

## Current decision gates

The outcome freeze remains blocked until all of the following are resolved:

1. Confirm the exact canonical Year 2 and Year 3 response files and item maps against the recorded hashes.
2. Complete `selected_path_version_review_queue.csv`, including prompt, stimulus, options, key/rubric, administration, scoring, layout, and exposure.
3. Review the provisional mathematics bridge sensitivity before promotion: 17 floor-retained item-link decisions, 22 flagged occurrences, and the three four-anchor paths for Y3 baseline Grade 4 and endline Grades 3 and 6.
4. Resolve the large location differences between chained and pooled results on long-path lower-grade nodes.
5. Resolve the nonconverged school-held-out French and mathematics calibrations. The converged Arabic fit is stable relative to the full pooled calibration, but it does not validate the other subjects.
6. Run treatment-related DIF only after measurement decisions are frozen.

No numerical warning threshold makes an automatic anchor or model decision.
