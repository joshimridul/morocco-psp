# Morocco Assessment Project: Y1–Y3 Dropbox Data and GitHub Code Architecture

**Status:** Project instruction for Codex  
**Date:** 2026-08-04  
**Basis:** Directory-tree inventories of the Year 1, Year 2, and Year 3 Dropbox folders, together with the current Ministry assessment-audit plan. This note describes what is visible from file and folder names. It does **not** certify the contents, provenance, or correctness of any candidate dataset or script.

## 1. Purpose of this note

This project has two related but distinct goals:

1. **Immediate goal: Year 3 Ministry assessment analysis.**  
   Use the latest Year 3 assessment data and item materials to evaluate item quality, identify defensible anchor candidates, and improve the recommendations sent to the Moroccan Ministry of Education.

2. **Medium-run goal: a larger Y1–Y3 measurement project.**  
   Build a harmonized item-version, form, grade, wave, cohort, and sample system and then assess whether Year 1, Year 2, and Year 3 can support subject-specific linked or multi-group IRT models. Year 1 belongs to a different paper and must not be assumed to be directly comparable merely because it is part of the broader Pioneer Schools project.

The immediate Year 3 work must be designed so that it can later feed into the larger Y1–Y3 project, but the larger project must **not** delay the Ministry-facing Year 3 analysis.

## 2. Confirmed project decisions

The following are decisions supplied by the project lead and are not questions for Codex to resolve:

- The existing Year 1, Year 2, and Year 3 data and legacy analysis files remain in Dropbox.
- Raw data are immutable. They will never be edited, renamed, moved, deleted, or overwritten.
- The legacy Year 1, Year 2, and Year 3 folder trees are shared project records. Codex must not reorganize them.
- All **new analysis code, tests, documentation, and configuration templates** belong in a new GitHub repository.
- No student-level data, raw extracts, clean analytic data, master keys, item
  forms, answer keys, secure item text, or data-bearing outputs are to be
  committed to GitHub. Project-lead-approved item maps may be tracked when
  they are limited to reproducibility metadata and contain no student data or
  secure item content.
- All new derived datasets and data-bearing outputs must remain in Dropbox, but in a **separate dedicated working root**, not inside the legacy Y1, Y2, or Y3 trees.
- The immediate analysis is Year 3 only.
- The Year 1–Year 3 pooled or linked IRT work is a later phase.
- Legacy `.do` and `.R` files will be reviewed later. For the current stage, Codex may inventory their names from the directory trees, but must not edit or execute them.

## 3. Root aliases

Never hard-code usernames or absolute Dropbox paths in tracked code. Use an untracked local configuration file, such as `config/paths.local.yml`, with root aliases:

```yaml
dropbox:
  y1_root: "/absolute/local/path/to/DiD - Morocco Pioneer School"
  y2_root: "/absolute/local/path/to/DID - Morocco Pioneer Schools Year 2"
  y3_root: "/absolute/local/path/to/DID - Morocco Pioneer Schools Year 3"

  # A new, user-controlled Dropbox directory. It must not be nested inside
  # the legacy Y1, Y2, or Y3 roots unless the project lead explicitly approves it.
  work_root: "/absolute/local/path/to/Morocco Assessment Psychometrics - Working"
```

Tracked code should refer only to `y1_root`, `y2_root`, `y3_root`, and `work_root`. The local configuration file must be excluded by `.gitignore`.

If the project lead explicitly approves a `work_root` nested below one of the
legacy roots, path guards treat only that exact configured subtree as writable.
All parent, sibling, raw-data, and other legacy locations remain read-only.

## 4. Storage boundary

### 4.1 Dropbox is the data layer

The following remain in Dropbox only:

- raw and deidentified survey extracts;
- clean and intermediate `.dta`, `.csv`, `.xlsx`, `.rds`, `.parquet`, or similar datasets;
- PII volumes and master keys;
- actual assessment forms, passages, images, answer keys, rubrics, and examiner guides;
- item maps and secure item text;
- legacy code and logs;
- derived student-level or item-response-level datasets;
- data-bearing tables, figures, workbooks, logs, and rendered reports unless explicitly approved for GitHub.

Codex must treat all three legacy Dropbox roots as **read-only source systems**.

### 4.2 GitHub is the new code and documentation layer

The new repository may contain:

```text
AGENTS.md
README.md
config/
  paths.example.yml
  analysis.yml
docs/
  DROPBOX_Y1_Y2_Y3_DATA_AND_CODE_ARCHITECTURE.md
  STUDY_DESIGN.md
  ANALYSIS_SPEC.md
  MINISTRY_EXCHANGE_AND_DELIVERABLE_STATUS.md
  SOURCE_REGISTRY_TEMPLATE.csv
  SAMPLE_FORM_REGISTRY_TEMPLATE.csv
src/
  00_inventory/
  01_y3_readiness/
  02_y3_item_quality/
  03_y3_anchors/
  04_y3_recommendations/
  10_legacy_code_audit/
  20_y1_y3_harmonization/
  21_y1_y3_irt/
tests/
reports/
  source/
```

The repository must not contain a copy or symlink to the Dropbox data. A local symlink can accidentally be committed or expose machine-specific paths; use configuration files instead.

### 4.3 Dedicated Dropbox working root

All new data-bearing products should be written outside the three legacy roots:

```text
Morocco Assessment Psychometrics - Working/
  private_manifests/
  derived/
    y3_ministry/
    y1_y3_harmonization/
  outputs/
    y3_ministry/
    y1_y3_irt/
  logs/
  scratch/
```

No new script may write to a path under `y1_root`, `y2_root`, or `y3_root`. Code should fail immediately if an output resolves inside one of those roots.

## 5. Source-of-truth policy

The directory trees contain many `Archive`, `Draft`, `Temp`, `OLD`, `Recovered`, duplicate, and Dropbox conflicted-copy files. Therefore:

- A folder named `Clean` does not by itself establish that a file is canonical.
- A later date in a filename does not by itself establish that a file supersedes an earlier one.
- A copy in a replication package may represent a paper-specific analytic sample rather than the full operational dataset.
- A combined file such as `y1y2_tested_data.dta` or `y1y2y3_tested_data.dta` may embed prior decisions about exclusions, harmonization, anchor naming, scoring, or sample construction.
- Existing IRT files and tables are evidence about prior work, not authoritative inputs for the new calibration.
- Dropbox “conflicted copy” files must never be silently selected or merged.

Codex must build a **source registry** before analysis. For each candidate file, record:

```text
source_id
year
root_alias
relative_path
source_role
wave
subject
sample/cohort
candidate_status
reason_selected_or_rejected
file_size
modified_time
sha256
contains_pii_or_unknown
read_only
contents_inspected
provenance_verified
verified_by
verification_date
notes
```

Full local paths and private file manifests remain in Dropbox. A tracked registry may use root aliases and relative paths only, and must not contain direct identifiers.

## 6. Immediate scope: Year 3 Ministry item and anchor audit

### 6.1 What this phase is for

The Year 3 phase should answer:

- Which Year 3 items functioned well or poorly by subject, administered grade, form, and wave?
- Which apparent problems are scoring, missingness, administration, item-design, or data problems?
- Which items are substantively important but need revision?
- Which common items are eligible for within-year, adjacent-grade, or across-year anchor roles?
- Which candidate anchors are empirically stable enough to recommend to the Ministry?
- Which content or cognitive domains are too weakly measured to support credible heterogeneity analysis?

This phase should use Year 3 baseline, Year 3 endline, and—where useful—Year 3 pilot evidence. It should not begin by pooling Year 1–Year 3.

### 6.2 Provisional Year 3 source candidates

The following paths are visible in the Year 3 tree and should be entered into the source registry as **candidates requiring validation**, not automatically used as canonical files.

#### Student-level assessment data

```text
4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta
4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta
4 - Data processing/04_Endline/Clean/y1y2y3_tested_data.dta
4 - Data processing/04_Endline/Clean/Panel data variables description.docx
```

A duplicate baseline file also appears in the Year 3 replication package:

```text
8 - Replication package/Data/02 - Baseline/Clean/baseline_data_20251107_eo.dta
```

For the immediate Ministry audit, begin from the wave-specific Year 3 baseline and endline files after verifying their provenance. Do **not** begin from `y1y2y3_tested_data.dta`; that file is more appropriate as a later reconciliation target because it may already embody legacy merge and harmonization decisions.

#### Year 3 item maps

```text
3 - Data collection/01_Baseline/3 - Item map/Item_map_20251013_eo.xlsx
3 - Data collection/01_Baseline/3 - Item map/Y1-3 Item Map/Item_maps_compiled_16122025_eo.xlsx
3 - Data collection/01_Baseline/3 - Item map/Y1-3 Item Map/item-map-anchor.xlsx
3 - Data collection/03_Endline/3 - Item map/Item_map_20260618_eo.xlsx
```

The current Ministry exchange also includes the separately supplied baseline map, original endline map, returned endline map, and structural audit. Those files should be referenced from their Dropbox location rather than copied into GitHub.

#### Actual Year 3 instruments

The Year 3 tree contains grade-specific student booklets and examiner guides under:

```text
3 - Data collection/01_Baseline/4 - Instruments/
3 - Data collection/02_Endline_Pilot/4 - Instruments/
3 - Data collection/03_Endline/4 - Instruments/
```

These materials are necessary to verify item versions and anchors. Item IDs or English item-map descriptions are insufficient.

#### Existing Year 3 diagnostics and prior decisions

The tree contains cohort-specific item-correct, item-incorrect, item-missing, “do not know,” and provisional IRT outputs, as well as a prior item-update file. Examples include:

```text
5 - Data analysis/03_Baseline/Analysis/Tables/table-05-item-correct-cohort-*.xlsx
5 - Data analysis/03_Baseline/Analysis/Tables/table-05-item-incorrect-cohort-*.xlsx
5 - Data analysis/03_Baseline/Analysis/Tables/table-05-item-missing-cohort-*.xlsx
5 - Data analysis/03_Baseline/Analysis/Tables/table-05-item-dknow-cohort-*.xlsx
5 - Data analysis/03_Baseline/Analysis/Tables/table-06-students-irt-cohort-*.xlsx
5 - Data analysis/03_Baseline/Analysis/Tables/baseline_items_toupdate_20260223_eo.xlsx
```

Use these only as cross-checks after independently recomputing results from student-level data. They must not determine the new item classifications.

### 6.3 Year 3 analysis boundaries

For the first Year 3 pass:

- Use deidentified data only.
- Exclude all `PII_volumes`, master keys, named student lists, preload files, printable lists, and reidentification materials.
- Treat baseline, pilot, and endline as distinct administrations.
- Treat each cohort and sample role explicitly; do not silently pool them.
- Distinguish administered grade from the grade or level of item origin.
- Preserve subject, form, passage/testlet, oral task, rubric, and scoring structure.
- Keep treatment assignment hidden during initial item-quality and anchor screening. Treatment-related DIF comes later, after provisional rules are frozen.
- Reconstruct scores independently. Existing reported scores and tables are tie-out targets, not source variables to trust automatically.
- Create item-version fingerprints from actual forms, options, keys/rubrics, stimuli, administration, and scoring information.

## 7. Year-by-year orientation for the later IRT project

### 7.1 Year 1

Year 1 supports a different paper and should initially remain a separate measurement source. The folder contains several possible data layers:

```text
8 - Replication package/Data/02 - Baseline/Clean/Baseline_tested.dta
8 - Replication package/Data/03 - Endline/Clean/Endline_tested.dta
8 - Replication package/Do/replica_morocco1.do

4 - Data processing/Data repository/data/published/baseline/Baseline-tested-neam.dta
4 - Data processing/Data repository/data/published/endline/Endline-tested-neam.dta

4 - Data processing/Baseline/Clean/Baseline-tested-neam.dta
4 - Data processing/Endline/Clean/Endline-tested-neam.dta
```

The replication-package files may be the cleanest paper-replication entry point, but they may also be reduced, paper-specific, or missing item-level detail. Codex must verify whether they contain raw item responses and full sample identifiers needed for IRT before selecting them.

Year 1 also contains a substantial item-map and anchor archive, including:

```text
3 - Data collection/Item map/Resources/Table - Summary of anchors items.xlsx
3 - Data collection/Item map/Resources/crosswalk/crosswalk endline - all subjects.xlsx
3 - Data collection/Item map/Resources/digitalise questions' texts/
3 - Data collection/Item map/stata_codebooks/baseline/baseline_rename_anchors_manual_neam.xlsx
3 - Data collection/Item map/stata_codebooks/endline/endline_rename_anchors_manual_neam.xlsx
3 - Data collection/Item map/Math/Item map maths 2024-09-11 adb.xlsx
3 - Data collection/Item map/French/item map french 2024-09-11 adb.xlsx
3 - Data collection/Item map/Arabic/Item map arabic 2024-08-26 seo.xlsx
```

Existing model artifacts include subject-specific `.ster` files and a pilot `item_characteristics.xlsx`. These are historical evidence only; the medium-run project must reproduce the calibration from item-level responses and documented scoring.

### 7.2 Year 2

Year 2 contains separate baseline and endline data, a merged Y1–Y2 file, pilot IRT code, provisional IRT outputs, anchor-balance outputs, and extensive item-map and instrument histories.

Provisional data candidates include:

```text
4 - Data processing/04_Baseline/Clean/baseline_data_2024-10-14_ya.dta
4 - Data processing/09_Endline/Clean/endline_data_20250716_ks.dta
4 - Data processing/09_Endline/Clean/y1y2_tested_data.dta
4 - Data processing/09_Endline/Clean/irt_provisional.dta
5 - Data analysis/08_Endline/Analysis/irt_provisional.dta
```

Provisional item and code landmarks include:

```text
3 - Data collection/02_Endline/03_Item Maps/Item_maps_20250715_ks.xlsx
5 - Data analysis/03_Baseline/Analysis/Tables/baseline_items_toupdate_flag_20250818_eo.xlsx
5 - Data analysis/08_Endline/Analysis/Tables/endline_items_toupdate_20260226_eo.xlsx
5 - Data analysis/07_Pilot/Set up/04_Pilot_IRT_scoring.do
5 - Data analysis/08_Endline/Set up/04_Merging_y1y2_ 20250715_ks.do
```

Do not use `irt_provisional.dta` as the raw source for a new calibration. It is an output whose lineage and model assumptions must later be audited. Likewise, `y1y2_tested_data.dta` is a reconciliation target until its construction is verified.

The Year 2 instruments are grade-specific, but folder names and test levels suggest that baseline forms may assess prior-grade content. The harmonized registry must therefore maintain separate fields for:

- student’s administered grade;
- paper/form label;
- item grade of origin;
- intended target grade;
- wave;
- year;
- cohort/sample.

### 7.3 Year 3

Year 3 is both the immediate Ministry source and the latest node in the longer measurement network. It already contains:

- separate baseline, pilot, and endline data and instruments;
- cohort-specific samples;
- a Y1–Y3 school/sample structure;
- compiled Y1–Y3 item maps;
- a combined `y1y2y3_tested_data.dta`;
- existing anchor and merge scripts;
- prior item and IRT outputs.

These assets are useful, but none proves that the years are correctly harmonized. The new project must independently reconstruct the link graph and verify every item version.

## 8. Medium-run Y1–Y3 IRT architecture

The goal should not initially be described as “fit one big IRT.” The first goal is to determine whether a defensible linked measurement network exists.

### 8.1 Build a form-and-sample graph

For each subject, create one node for every combination of:

```text
year × wave × cohort × sample role × administered grade × form/version
```

Create an edge only when two nodes share one or more verified, operationally equivalent item versions. Report:

- number of common items;
- content and cognitive coverage;
- difficulty range;
- passage/testlet concentration;
- scoring equivalence;
- exposure history;
- empirical drift and DIF;
- whether the edge is strong enough for linking.

If Year 1 is disconnected from Year 2–3, do not force it onto the same scale. Possible outcomes include:

- separate Year 1 and Year 2–3 scales;
- a multi-group model with only defensible bridge constraints;
- subject- or grade-specific networks;
- no vertical scale for some links;
- a common-item trend analysis without claiming a fully vertical proficiency scale.

### 8.2 Build a sample registry

The folder trees indicate multiple evaluation, pilot, cohort, and panel files, including filenames referring to 300-school, 70-school, 150-school, and 270-school samples. These names are not verified analytic counts. Every calibration record must include:

```text
year
wave
cohort
sample_role
school_sample_id
student_sample_id
subject
administered_grade
paper_level
form_id
item_version
panel_linkable
prior_item_exposure
treatment_exposure
sampling_weight
school_id
class_id
```

Do not assume that observations from different years are repeated measures of the same students. Use crosswalks only when authorized and verified.

### 8.3 Model strategy

Later model selection should be driven by the verified response structure:

- fit subject-specific models;
- start with parsimonious Rasch/1PL or partial-credit models where appropriate;
- compare more flexible models only when the data support them;
- use multi-group constraints rather than silently concatenating samples;
- preserve testlets and rater-scored task structure;
- assess item drift and DIF by year, wave, grade, sample, and treatment exposure;
- validate anchors in held-out cohorts, waves, or schools;
- report linking uncertainty and sensitivity to alternate anchor sets;
- do not select anchors based on favorable treatment effects;
- keep causal estimands separate from measurement-model decisions.

A combined file is not a combined scale. The form graph, item-version equivalence, and empirical invariance must justify the scale.

## 9. Deferred legacy-code audit

### 9.1 Current rule

At the present stage, do not open, edit, or execute legacy `.do` or `.R` files. Their names may be placed in a candidate dependency map, but their logic should not be inferred from names alone.

Examples of later-relevant Year 3 scripts include:

```text
5 - Data analysis/05_Endline/Set up/Y3_EL_Cleaning_Master.do
5 - Data analysis/05_Endline/Set up/07_Anchors_25062026_mji.do
5 - Data analysis/05_Endline/Set up/11_Merging_y1y2y3_ 20260702_eo.do
```

Examples of later-relevant Year 2 and Year 1 scripts include:

```text
5 - Data analysis/08_Endline/Set up/04_Merging_y1y2_ 20250715_ks.do
5 - Data analysis/07_Pilot/Set up/04_Pilot_IRT_scoring.do
8 - Replication package/Do/replica_morocco1.do
```

### 9.2 Later static audit

When the project lead authorizes the legacy-code phase, first perform a static read-only audit. For each script, catalog:

- files read with `use`, `import`, `merge`, `append`, or equivalent;
- files written with `save`, `export`, `outsheet`, `putexcel`, or equivalent;
- `replace`, `erase`, `rm`, `copy`, `rename`, shell commands, and destructive operations;
- globals, absolute paths, working-directory assumptions, and package dependencies;
- inclusion chains and master scripts;
- variable renames, recodes, exclusions, scoring, anchor flags, and sample restrictions;
- random seeds and non-deterministic operations;
- expected outputs and logs.

### 9.3 Safe execution rule

Never run a legacy script directly against the live Dropbox roots. Legacy scripts may contain `save, replace`, `erase`, hard-coded paths, or output commands that could alter shared files.

If later execution is necessary:

1. make a byte-identical working copy outside the legacy roots;
2. mount or expose inputs as read-only where possible;
3. redirect every output to the dedicated Dropbox working root;
4. run in an isolated environment;
5. capture logs, software versions, package versions, return codes, and file hashes;
6. compare produced outputs with stored clean files;
7. never “fix” the original script in place.

Any adaptation belongs in new GitHub code, with a documented mapping back to the legacy script.

## 10. Collaboration-safe workflow

The shared folders contain work from many authors and numerous versions. The new workflow must be scientifically independent without being destructive or accusatory.

Codex must:

- leave every shared file untouched;
- never rename, archive, delete, or “clean up” another person’s folders;
- never choose a conflicted copy silently;
- describe discrepancies neutrally and by evidence, not by presumed author error;
- separate `verified`, `likely`, `uncertain`, and `requires collaborator confirmation`;
- preserve a decision log showing who made each final source-selection or scoring decision;
- make all new transformations reversible and reviewable;
- minimize broad requests to collaborators.

When collaborator input is genuinely necessary, produce a narrow question in this form:

```text
Decision needed:
Candidate files:
Observed difference:
Why the folder name/date is insufficient:
Consequence for the analysis:
Codex's provisional recommendation:
```

Do not ask “Which files should I use?” when the tree permits a more precise question.

## 11. Immediate Codex work plan

### Phase A — Repository and path safety

1. Read this note and the project instructions.
2. Verify that Git excludes all data, item materials, local paths, derived files, and rendered data-bearing outputs.
3. Create `config/paths.example.yml` and confirm that `config/paths.local.yml` is ignored.
4. Implement path guards that prohibit writes under `y1_root`, `y2_root`, and `y3_root`.
5. Create source- and sample-registry templates.

### Phase B — Year 3 source registry

1. Inventory only the targeted Year 3 data, item maps, instruments, and prior outputs needed for the Ministry audit.
2. Record hashes, metadata, schemas, and candidate roles.
3. Identify candidate canonical baseline and endline files, but do not declare them canonical until validated.
4. Do not inspect or run legacy code.
5. Produce a blocking-issues register.

### Phase C — Year 3 independent reconstruction

1. Read the selected deidentified wave-specific data.
2. Build a new normalized item-response representation in the dedicated Dropbox working root.
3. Reconstruct scores from item-level fields, item maps, forms, keys, and rubrics.
4. Tie out against existing scores and output tables.
5. Document every difference.

### Phase D — Year 3 psychometric and content audit

1. Run operational and classical item diagnostics.
2. Evaluate score structure, testlets, rubrics, and domain-score feasibility.
3. Identify exact common item versions.
4. Evaluate anchor eligibility and stability.
5. Produce the Ministry item-decision workbook and memo.

### Phase E — Legacy reconciliation

Only after the Year 3 independent analysis is reproducible, audit the relevant legacy scripts and reconcile differences.

### Phase F — Y1–Y3 harmonization and IRT

After the immediate Ministry deliverable is complete, build the full year/wave/cohort/sample/form/item-version network and determine which linked models are defensible.

## 12. Required safety checks in new code

Every entry-point script should:

- load paths from the untracked local configuration;
- resolve all paths before reading or writing;
- assert that each input exists;
- assert that every input is under an approved Dropbox source root;
- assert that every output is under the dedicated Dropbox working root;
- fail if an output equals an input path;
- fail if an output resolves under a legacy root;
- calculate and log input hashes;
- record row counts, variable names, key checks, and exclusions;
- refuse to export direct identifiers;
- set seeds and record package/software versions;
- never use destructive file operations on source roots.

## 13. GitHub exclusions

At minimum, `.gitignore` should exclude:

```gitignore
config/paths.local.yml
.env
.env.*

# No data or secure assessment content in Git
data/**
private/**
local/**
scratch/**
derived/**
outputs/**
logs/**

# Common data and model artifacts
*.dta
*.ster
*.sav
*.sas7bdat
*.rds
*.RData
*.parquet
*.feather
*.arrow

# Local state
.DS_Store
.Rhistory
.RDataTmp
.venv/
__pycache__/
.ipynb_checkpoints/
```

Do not use Git LFS as a workaround for the no-data rule.

## 14. What Codex must not do

Codex must not:

- modify any file in the Year 1, Year 2, or Year 3 Dropbox roots;
- execute inherited code against live shared folders;
- commit data, item maps, instruments, item text, keys, or student-level outputs to GitHub;
- start with the combined Y1–Y3 dataset for the immediate Year 3 audit;
- treat a replication-package sample as the full operational sample without checking;
- accept prior IRT scores, anchor flags, or item-update recommendations as ground truth;
- infer equivalence from item IDs, variable names, or English summaries alone;
- collapse pilot, main, cohort, grade, wave, or treatment groups without an explicit decision;
- force Year 1 onto a common scale if the link network is weak or disconnected;
- resolve conflicting files based only on timestamp or filename;
- silently invent missing scoring keys, sample definitions, or crosswalks.

## 15. Definition of success

The architecture is working when:

- the GitHub repository can be cloned without any project data;
- a user supplies only an untracked local paths file to connect it to Dropbox;
- all source files remain byte-for-byte unchanged;
- every input is registered and hashed;
- every generated data-bearing file is written to the dedicated Dropbox working root;
- the Year 3 Ministry audit is independently reproducible without modifying shared legacy code;
- legacy analyses can later be reconciled in a separate, safe phase;
- the medium-run Y1–Y3 IRT project begins from an explicit form-and-sample link graph rather than from an assumed pooled scale.

## 16. Initial instruction to Codex

Use the following as the first task prompt:

> Read `AGENTS.md`, `README.md`, and `docs/DROPBOX_Y1_Y2_Y3_DATA_AND_CODE_ARCHITECTURE.md`. The current priority is the Year 3 Ministry item and anchor audit. Year 1 and Year 2 are deferred except for documenting future source candidates. Do not open or execute any legacy `.do` or `.R` files in this phase. Do not write anywhere under the three legacy Dropbox roots. Verify the GitHub/data boundary, create the path guards and source-registry structure, and inventory only the targeted Year 3 wave-specific data, item maps, instruments, and prior output tables. Treat all apparent clean/latest files as candidates until provenance is verified. Produce a concise source-readiness report and a blocking-issues register before any psychometric modeling.
