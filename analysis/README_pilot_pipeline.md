# Pilot analysis pipeline

This folder contains the reproducible pipeline for the Morocco pilot item review.

## Entry point

Run the full pipeline with:

```bash
python3 analysis/run_pilot_pipeline.py
```

The runner sets `PROJECT_ROOT` and `PILOT_DATA_PATH` for all downstream scripts.

## Script order

1. `pilot_psychometrics_review.R`
   - Deduplicates student-form records.
   - Builds form summaries, item summaries, CTT flags, anchor audits, and within-form IRT outputs.
2. `pilot_vertical_linking.R`
   - Audits adjacent-grade anchor sets.
   - Builds conservative subject-specific linked chains.
3. `pilot_item_action_sheet.py`
   - Assigns revised item strategies:
     - `keep_as_stretch`
     - `keep_for_causal_signal`
     - `soften_slightly`
     - `review_treated_only_ceiling`
     - `keep_but_fix_administration`
     - `replace`
4. `pilot_reporting.py`
   - Writes the external ministry brief.
   - Writes supporting priority queues for follow-up.

## Counting convention

- Planning summaries use `form-item occurrences` rather than unique item IDs.
- This means a shared or anchor item reused across grades can appear more than once in workload counts.
- The subject summary file also includes unique item ID totals for audit purposes.
- A ceiling item is now an automatic `replace` only when both treated and control groups are near ceiling; treated-only ceiling items are separated into a review category.

## Output folders

- `outputs/pilot_psychometrics`
- `outputs/pilot_vertical_linking`
- `outputs/pilot_item_actions`
- `outputs/pilot_reports`

## Reporting outputs

- `outputs/pilot_reports/team_full_report.md`
- `outputs/pilot_reports/ministry_brief.md`
- `outputs/pilot_reports/ministry_priority_action_queue.csv`
- `outputs/pilot_reports/action_counts_by_subject_grade.csv`

## Independent replication check

Run the independent QA pass with:

```bash
python3 analysis/pilot_replication_check.py
```

This writes:

- `outputs/pilot_reports/replication_check_report.md`
- `outputs/pilot_reports/replication_check_details.csv`
- `outputs/pilot_reports/replication_irt_refit_summary.csv`
