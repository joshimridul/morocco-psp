# Independent Replication Check

- Overall status: `PASS`
- Raw rows independently read: `3523`
- Deduplicated rows independently reconstructed: `3507`
- Binary item fields independently identified: `430`
- Non-binary item fields independently identified: `6`
- Non-binary fields: `a612y3_nv3, a613y3_nv3, a614y3_nv3, f2123, f2124, f2125`

## What Was Replicated Independently

- raw row count, binary item detection, and non-binary item exclusion
- duplicate resolution using the same student-subject-grade key and independent sorting logic
- form-level sample sizes, treated/control counts, item counts, response rates, and mean scores
- item-level scored difficulty, observed-only correctness, response rates, missing rates, and corrected item-total correlations
- item action classification under the revised dual-objective rules
- subject and subject-grade action counts
- adjacent-grade anchor-pair counts, usable-anchor counts, final-anchor counts, and chain-edge flags
- within-form IRT model fallback decisions by refitting 2PL and 1PL models
- canonical report hygiene after retiring `internal_research_report.md`

## Check Summary

| Check | Status | Problems |
| --- | --- | ---: |
| `raw_rows` | `pass` | 0 |
| `dedup_rows` | `pass` | 0 |
| `binary_item_count` | `pass` | 0 |
| `nonbinary_item_count` | `pass` | 0 |
| `form_summary` | `pass` | 0 |
| `item_summary` | `pass` | 0 |
| `action_classification` | `pass` | 0 |
| `action_subject_summary` | `pass` | 0 |
| `action_grade_summary` | `pass` | 0 |
| `anchor_pair_summary` | `pass` | 0 |
| `irt_refit` | `pass` | 0 |
| `canonical_internal_report` | `pass` | 0 |

## Errors Found And Fixes

- No analytic discrepancies were found in the replicated calculations or IRT fallback decisions.
- The only issue found during this pass was output hygiene: the old shorter `internal_research_report.md` was still being generated and present after we decided to keep only `team_full_report.md` as the internal report. I fixed this by removing the file, removing it from the reporting script output, and updating the pipeline README to list `team_full_report.md` as the canonical internal report.

## Notes

- This replication intentionally recalculates the core CTT and action logic from the raw Stata file instead of trusting the existing generated CSVs.
- The IRT check refits each form independently and compares the resulting `2PL` versus `1PL` fallback decision to the main output.
- IRT refit details are saved in [replication_irt_refit_summary.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/replication_irt_refit_summary.csv).
- Row-level replication details are saved in [replication_check_details.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/replication_check_details.csv).
