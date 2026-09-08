# Final independent Claude adversarial review

**Review date:** 2026-09-09  
**Reviewer:** Claude Opus, invoked through the local CLI in read-only mode with
permission to execute diagnostic commands.  
**Scope:** measurement construction, fixed Year 1 parameters, anchor and DIF
rules, robustness outcomes, Stata regressions, Ministry tie-outs, code/data
boundaries, lineage, and the compiled report.

## Verdict returned by Claude

Claude found **no numerical error** in the IRT estimator, fixed Year 1 metric,
anchor rule, Stata estimand, or reported treatment effects. It independently
verified binary-only scoring, exact preservation of all 255 Year 1 parameter
pairs, separate subject models, the three-slope numerical cap, treatment-blind
anchor selection, all 66 operational nodes, the restored Cohort 3 Arabic Grade
1--2 cells, the robustness grid, the historical Ministry branch, and all four
families of Ministry tie-outs.

It classified the analysis as a conditional scientific pass and raised two
release-engineering blockers plus several documentation/provenance cautions.

## Release blockers and resolution

1. **Tracked generated output and a false pass in the repository guard.** The
   Git index still contained 33 generated Y4 output files, including a
   student-level score file. The guard skipped a tracked file when its working
   copy was absent. **Resolved:** all generated Y4 outputs and five tracked
   `.DS_Store` files are staged for removal from the index without rewriting
   history; the guard now evaluates index paths even when the working file is
   absent; the pre-commit hook runs both staged-file and all-tracked checks.
2. **Cached final report rebuild did not itself run the measurement gate, and
   the full-run log was not archived beside the outputs.** **Resolved:** the
   release gate now runs before both full and cached branches; each Stata run
   keeps a timestamped log; the genuine 2026-09-09 no-cache run log is archived
   under the report output directory; and the final short rebuild passed the
   gate, QA, and PDF compilation.
3. **Stale correlation floors in the governing README.** **Resolved:** the
   README now reports the output-backed minima: 0.9875/0.9665 for the displayed
   IRT level/change variants and 0.9562/0.8832 against standardized sums, while
   separately noting that sequential/direct IRT level correlations exceed
   0.998.

## Other findings and resolution

- Unsupported claims about unfinished unbounded/free-distribution runs were
  removed or explicitly described as unreported, unfinished methods.
- The report now explains that pooled school counts are school-by-cohort
  estimation units.
- The appendix now reports 266 freed item-by-link rows, 39 link-floor
  retentions, and 2,868 material-only review rows; these are explicitly not
  counts of globally defective items.
- The appendix now states the high French item-fit warning rate (120/186) and
  explains why robustness of treatment effects does not establish construct
  validity.
- The open source, occurrence-review, testlet, and scientific approval gates
  are enumerated. `final_outcome_approved` remains zero.
- Regression and report source hashes are now recorded separately on every
  report build, covering `src/22_treatment_effects`,
  `src/30_ministry_irt_report`, and the governing configuration.
- The stale undeclared development-model directory was moved to a recoverable
  archive outside the production grid.
- The two appendix prose/typography defects were corrected.

## Scientific cautions retained

These are not coding failures and are not suppressed: French item fit; strong
local-dependence signals with incomplete testlet metadata; large location and
scale differences on thin mathematics links; 44 regression cells with fewer
than 20 matched-pair clusters; small subject-share imbalance; unmatched Year 1
baseline joins; and sources or item occurrences still awaiting scientific
sign-off. The report remains an internal analytical draft until those approval
gates are closed.

## Final post-review checks

- 30 unit tests pass.
- All 29 R files parse.
- The repository all-tracked data-boundary check passes.
- Git whitespace validation passes.
- The final Stata report build passes the measurement release gate and the
  42-check regression audit (38 pass, 4 disclosed warnings, 0 critical).
- The PDF has 16 pages and compiles without LaTeX layout or reference warnings.

