# Morocco Assessment Item and Anchor Audit — GitHub-Safe Codex Project

This private repository contains new code, documentation, configuration
templates, and project-lead-approved item maps. The Year 1, Year 2, and Year 3
data and legacy files remain in Dropbox.

The immediate objective is to use verified Year 3 data and item materials to evaluate item performance, identify defensible anchors, and improve the recommendations sent to the Moroccan Ministry of Education. A later phase will determine whether Year 1–Year 3 can support linked or multi-group IRT analyses across different papers, samples, cohorts, grades, and waves.

## Non-negotiable architecture

- The three legacy Dropbox roots are read-only.
- No new output may be written inside those roots.
- All generated data-bearing files go to a separate Dropbox working root.
- All new code, tests, and documentation go to GitHub.
- No student data, instruments, answer keys, secure item text, or data-bearing
  outputs go to GitHub. Project-lead-approved item maps may be tracked when
  they contain only the metadata needed for reproducibility.
- Legacy `.do` and `.R` files are opened or executed only after the project
  lead authorizes a separate audit phase. That authorization was given for the
  read-only Year 1 lineage and Year 3 Ministry-specification audits documented
  in this repository.

Read `docs/DROPBOX_Y1_Y2_Y3_DATA_AND_CODE_ARCHITECTURE.md` before doing any work.

## Local setup

1. Copy `config/paths.example.yml` to `config/paths.local.yml`.
2. Enter the local Dropbox roots and the project-lead-approved Dropbox
   `work_root`. It may be nested in a source tree only when that exact subtree
   has been explicitly approved for generated outputs.
3. Confirm that `config/paths.local.yml` remains untracked.
4. Do not copy or symlink Dropbox files into this repository.
5. Complete `docs/STUDY_DESIGN.md` and review `config/analysis.yml`.

## Recommended workflow

1. Verify path safety and implement guards against writes to the legacy roots.
2. Build a Year 3 source registry and hash the candidate source files.
3. Verify the Year 3 wave-specific baseline and endline sources.
4. Reconstruct scores independently and tie them out against prior outputs.
5. Run the Year 3 item-quality and anchor analysis.
6. Produce the Ministry decision workbook and memo.
7. Audit inherited code later in a read-only, sandboxed phase.
8. Build the Y1–Y3 form-and-sample link graph before considering pooled or linked IRT.

Use the revised first prompt in `PROMPTS.md`.

## Reproducible IRT and regression workflow

The production measurement build is documented in
[`docs/IRT_PIPELINE_README.md`](docs/IRT_PIPELINE_README.md). From the repository
root, run:

```bash
Rscript src/21_y1_y3_irt/run_irt_pipeline.R config/paths.local.yml
```

After that command completes successfully, the Ministry-format regression and
report build is documented in
[`docs/MINISTRY_IRT_REGRESSION_PIPELINE.md`](docs/MINISTRY_IRT_REGRESSION_PIPELINE.md).
Run:

```bash
/Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp -b do \
  src/30_ministry_irt_report/00_master.do \
  /Users/mriduljoshi/Github/morocco-psp 1 0
```

The first command creates and validates the outcomes. The second refreshes the
analysis panels, estimates every prespecified regression family, reproduces the
earlier standardized-sum-score results as a benchmark, writes the LaTeX tables,
runs regression QA, and compiles the PDF. Neither command writes to a legacy
Dropbox root.

## Repository data guard

Before committing, enable the repository's data-boundary hook once:

```bash
git config core.hooksPath .githooks
```

The hook rejects generated-output directories, analysis-data formats, and
unapproved structured data files. Project-lead-approved item maps are an
explicit exception. Run the same check over the current tracked tree with:

```bash
python3 scripts/check_repository_data_boundary.py --all-tracked
```
