# Morocco Assessment Item and Anchor Audit — GitHub-Safe Codex Project

This repository contains **new code and documentation only**. The Year 1, Year 2, and Year 3 data and legacy files remain in Dropbox.

The immediate objective is to use verified Year 3 data and item materials to evaluate item performance, identify defensible anchors, and improve the recommendations sent to the Moroccan Ministry of Education. A later phase will determine whether Year 1–Year 3 can support linked or multi-group IRT analyses across different papers, samples, cohorts, grades, and waves.

## Non-negotiable architecture

- The three legacy Dropbox roots are read-only.
- No new output may be written inside those roots.
- All generated data-bearing files go to a separate Dropbox working root.
- All new code, tests, and documentation go to GitHub.
- No student data, item maps, instruments, answer keys, secure item text, or data-bearing outputs go to GitHub.
- Legacy `.do` and `.R` files are not opened or executed until the project lead authorizes a separate audit phase.

Read `docs/DROPBOX_Y1_Y2_Y3_DATA_AND_CODE_ARCHITECTURE.md` before doing any work.

## Local setup

1. Copy `config/paths.example.yml` to `config/paths.local.yml`.
2. Enter the local Dropbox roots and a separate Dropbox `work_root`.
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
