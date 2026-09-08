# Year 1 legacy IRT static audit and Y1–Y3 calibration implications

**Status:** Preliminary, read-only static audit  
**Date:** 2026-08-05  
**Execution status:** No inherited script was executed  
**Scope:** Year 1 assessment cleaning, pilot diagnostics, final IRT scoring, and the replication master

## 1. Why this audit exists

The published Year 1 results must remain unchanged. Before estimating a Year 1–Year 3 measurement system, we therefore need to recover the exact Year 1 scale definition, preserve the reported Year 1 scores, and determine which Year 1 item parameters can be treated as fixed calibration constants for later administrations.

This is a lineage audit, not an endorsement of every inherited decision. It distinguishes:

- the published Year 1 estimand and score scale, which must be preserved;
- the historical estimation procedure, which must be reproduced closely enough to understand the scale;
- later Y2–Y3 calibration choices, which can be improved without rewriting the Year 1 paper; and
- sensitivity analyses, especially a calibration based only on control-group responses.

## 2. Legacy files read

Paths below use the `y1_root` alias from the untracked local path configuration.

1. `8 - Replication package/Do/replica_morocco1.do`
2. `5 - Data analysis/10_Endline/Analysis/Programs/01-Testscores-20251008-adb.do`
3. `5 - Data analysis/9_Endline_pilot/Analysis/Programs/1_endline_pilot_20240605_adb.do`
4. `5 - Data analysis/10_Endline/Setup/02_Endline_cleaning_2024-08-01_neam.do`
5. `5 - Data analysis/10_Endline/Setup/03_Endline_baseline_scores_2024-08-01_neam.do`
6. `5 - Data analysis/4_Baseline/Setup/4_baseline-cleaning-20240729-neam.do`
7. The locally installed help and program files for `uirt` 2.2.1 and `uirt_theta` 1.1.

The static audit deliberately did not enter PII/master-key directories and did not run any inherited code.

## 3. Year 1 scoring lineage

### 3.1 Replication entry point

The replication master sets Stata version 18 and seed 2816, then calls the final test-score script. It lists `uirt`, `diflogistic`, `dropmiss`, and `renvars` as required user-written commands. Its path setup is username-specific and is not portable without modification.

### 3.2 Pilot item diagnostics

The pilot script:

- defines explicit item lists by subject and paper;
- recodes the administered-item `.a` category to incorrect;
- fits `uirt` separately by paper/grade grouping;
- exports discrimination (`a`) and difficulty (`b`) estimates;
- computes proportion correct, the share coded `.a`, and classical item-rest correlations; and
- states that the exported workbook was used manually to construct the endline item map.

Because no model option is supplied, `uirt` fits a 2PL model to dichotomous items by default. The pilot item decisions were therefore partly manual and are not represented as a deterministic decision table in the script.

### 3.3 Construction of Year 1 item IDs

The baseline and endline cleaning scripts first apply Excel `iecodebook` mappings and then create common item variables from grade-specific source variables. Adjacent-grade items are combined into one named variable, while their original grade-specific variables are later dropped.

Consequences:

- a final Year 1 item ID is a constructed analytic identifier, not a raw-form identifier;
- the same final ID can represent several grade-specific source variables;
- the cleaning script is evidence of intended commonality, not proof that prompt, stimulus, options, key/rubric, layout, and administration were unchanged; and
- future cross-year matching must begin with a source-variable-to-item-version crosswalk, not a join on final item ID alone.

### 3.4 Analytic sample used for the final IRT

For each subject, the final test-score script:

1. removes schools belonging to unmatched pair strata using a pair-level singleton check;
2. retains endline students who can be matched to the baseline tested file;
3. retains baseline observations in the matched-pair schools, including baseline records for later attritors;
4. recodes administered-item `.a` values to zero for the IRT item families; and
5. removes specified non-binary oral/fluency variables before fitting the main subject model.

The script does not calibrate on control schools only. Treatment and control students contribute to the Year 1 item-parameter estimation. Control-group observations enter later when the EAP scores are standardized.

### 3.5 Endline vertical linking across grades

Within each subject, the script first examines common items across adjacent grades using logistic-DIF and Mantel–Haenszel commands with a nominal 0.05 threshold. It then manually creates grade-specific copies of selected items described in comments as needing to be “freed.” Items left under a common variable name share one parameter pair across the relevant grade administrations; grade-specific copies receive separate parameters.

This is a partially manual anchor-purification procedure. The script does not preserve a machine-readable table containing the statistical result, effect size, substantive decision, reviewer, or reason for each final constraint.

### 3.6 Baseline–endline linking and fixed parameters

The final model is estimated in two stages for each subject:

1. Fit `uirt` to endline item variables only.
2. Append baseline records, rename selected baseline items that were judged to drift, and refit with `fix(prev)`.

According to the installed `uirt` documentation, `fix(prev)` fixes item parameters at their values from the immediately preceding `uirt` estimation. Thus the endline item parameters define the Year 1 metric; additional baseline-only or freed baseline item parameters are estimated around that fixed endline scale.

The active production specification is therefore:

- unidimensional by subject;
- default 2PL for dichotomous items;
- marginal maximum likelihood estimation using the `uirt` EM algorithm;
- endline item calibration first;
- fixed-item calibration for the combined baseline/endline data; and
- manually freed parameters for selected grade or wave differences.

The commented multi-group `uirt` commands were diagnostic or abandoned specifications, not the final scoring commands.

### 3.7 Student scores and standardization

The script obtains EAP scores with `uirt_theta, eap`. It then attempts to standardize each subject score using the Year 1 endline control group:

\[
z_{is} = \frac{\widehat\theta_{is}-\bar{\widehat\theta}_{s,C,EL}}
{SD(\widehat\theta_{s,C,EL})}.
\]

The same stored subject model is also used to generate selected item-subset scores by temporarily masking other item responses and recomputing EAPs. These are conditional scores under the full subject calibration; they are not separately fitted domain IRT models.

## 4. Important issues requiring resolution

### 4.1 The final do-file does not save the estimation objects

The final script stores the three subject models in memory but contains no `estimates save` command. Three subject `.ster` files exist under the Year 1 endline temporary-output directory, but the static audit found no inherited do-file that creates them. Their contents may be exactly what is needed, but their production lineage is not yet verified.

A guarded Stata 19.5 probe subsequently opened all three stored models successfully. All report convergence and contain the expected active commands:

- Arabic: combined fixed-item model, 14,567 observations and 322 items;
- French: combined fixed-item model, 14,315 observations and 282 items; and
- Maths: combined fixed-item model, 14,639 observations and 415 items.

The stored group parameters are mean 0 and standard deviation 1. The combined-model parameter tables indicate 163 fixed Arabic items, 119 fixed French items, and 145 fixed Maths items through zero standard errors on their fixed parameters. Detailed hashes, Stata logs, summaries, and parameter tables are stored under `work_root/outputs/y1_y3_irt/00_y1_reference/ster_probe/`.

**Provisional status:** The objects are readable and structurally consistent with the final scoring commands. Their creation lineage and identity as the exact published production objects still require verification against delivered scores or a historical log.

A second guarded check loaded each stored model with its corresponding delivered Year 1 subject file, recomputed raw EAP scores, recovered the endline-control transformation, and compared the reconstructed standardized scores with the stored scores. All three subjects matched to machine precision across every available stored score. Detailed aggregate tie-out logs and scale constants are stored under `work_root/outputs/y1_y3_irt/00_y1_reference/score_tieout/`.

**Updated status:** Verified as the exact model objects underlying the delivered Year 1 subject scores. A separate historical execution log is no longer necessary for score identity, although the absent creation command remains a reproducibility gap in the inherited code.

### 4.2 Treatment-variable naming inconsistency

In each subject section, the script drops both `treat` and `treated`, merges back only `treat`, and then refers to `treated` when calculating the control-group standardization. As written, this appears internally inconsistent. The discrepancy must be reconciled against a successful historical log, the delivered score variables, or the actual code version used to produce the published results.

**Scientific consequence:** The intended standardization is clear, but the current file may not be the exact executable version that generated the published scores.

The delivered subject files contain the expected control indicator, and the stored-model score tie-out succeeds exactly. The inconsistency therefore concerns the available do-file's executable lineage, not the recoverability of the delivered Year 1 scale.

### 4.3 Software versions are incompletely pinned

The replication master specifies Stata 18 but does not pin versions or hashes for user-written packages. The currently installed `uirt` is 2.2.1, but that alone does not prove it was the version used for the published calibration.

### 4.4 Missingness codes combine distinct concepts

The cleaning labels describe `.a` as “question not administered or don't know,” while the IRT script recodes `.a` to zero for administered item families. Structural missingness generally appears to remain system missing because grade-specific recoding is conditional, but this must be verified empirically by form and grade before reproducing the response matrix.

### 4.5 Item equivalence is encoded, not demonstrated

The codebook and common-variable construction identify intended anchors, but actual form equivalence still requires prompt, stimulus, options, key/rubric, layout, administration, and exposure checks. This is especially important before extending a Year 1 constraint into Year 2 or Year 3.

### 4.6 Fixed Year 1 parameters omit their estimation uncertainty

Treating estimated Year 1 item parameters as known constants preserves the published scale but understates uncertainty in later linked estimates. The main Y2–Y3 model can hold them fixed, but reports should include sensitivity analyses or a linking-uncertainty calculation where feasible.

### 4.7 The Year 1 clean-data locations are not all distinct sources

The hash registry covers 27 priority Year 1 files. The `published` and processing `Clean` copies are byte-identical for baseline, and likewise byte-identical for endline. The replication-package baseline and endline files are different hashes and sizes from those pairs. This removes two false choices but does not by itself establish whether the replication files are reduced, augmented, or otherwise transformed. Canonical selection remains a documented decision rather than a filename assumption.

### 4.8 Legacy item IDs do not encode administered grade

The normalized codebook and scoring crosswalk maps all 1,019 stored-model item parameters. It also corrects an initially plausible but false interpretation: the first digit after the subject prefix is not the administered grade. In the inherited scoring logic, `a1*`, `f1*`, and `m1*` are primarily baseline-only families, while `a2*`, `f2*`, and `m2*` are endline/common-item families. Prefixes such as `bldf_` identify baseline copies used after parameters were separated, and suffixes such as `_3`, `_23`, or `_456` identify grade-specific or grade-group-specific endline parameters.

Administered grade must therefore come from the observed response pattern and scoring transformations, not from parsing the item ID.

### 4.9 The published Year 1 link structure is now machine-readable

Every stored-model variable is present in its corresponding verified scoring dataset. The aggregate audit found no non-binary response cells among the modeled items. The following counts describe observed administration and shared parameter constraints in the published Year 1 model:

| Subject | Cross-wave item families | Same parameter across waves | Freed/split across waves | G1–G2 | G2–G3 | G3–G4 | G4–G5 | G5–G6 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Arabic | 80 | 29 | 51 | 8 | 4 | 6 | 5 | 5 |
| French | 50 | 11 | 39 | 5 | 50 | 6 | 31 | 31 |
| Maths | 72 | 21 | 51 | 5 | 2 | 4 | 6 | 4 |

The adjacent-grade columns count endline item parameters observed in both grades. These are verified analytic constraints, not yet final anchor counts. Each still requires exact prompt, stimulus, options, key/rubric, layout, administration, and exposure verification against the source instruments and maps.

## 5. Implications for an R `mirt` implementation

`mirt` is a strong candidate for the new work because it supports multiple-group models, equality constraints, fixed item parameters, mixed dichotomous/polytomous item types, DIF tools, and reproducible parameter tables. It should not be adopted merely by translating command names.

The Year 1 `uirt` dichotomous response function is:

\[
P(X=1\mid\theta)=\operatorname{logit}^{-1}\{a(\theta-b)\}.
\]

For `mirt`'s slope/intercept parameterization,

\[
P(X=1\mid\theta)=\operatorname{logit}^{-1}(a_1\theta+d),
\]

the matching transformation is:

\[
a_1=a, \qquad d=-ab.
\]

Before any Y2–Y3 estimation, we must verify this conversion numerically by comparing item response curves, test characteristic curves, and EAP scores over a fixed theta grid and a controlled response-pattern sample.

To preserve the Year 1 paper:

1. keep the published Year 1 scores as the official Year 1 outcome variables;
2. extract and freeze the verified Year 1 item parameters on their pre-standardization latent scale;
3. record the published control-endline centering and scaling constants separately;
4. use verified unchanged Y1 items as fixed anchors for connected Y2–Y3 nodes only; and
5. never let a re-estimated R model silently replace the published Year 1 outcomes.

## 6. Proposed model sequence

### Stage 1 — Freeze the Year 1 reference

- Hash and register the candidate Year 1 clean data, codebooks, final scoring script, stored estimates, and delivered score file.
- Extract the item parameter tables and model metadata from each `.ster` file in an isolated read-only check.
- Identify the historical `uirt` package version if possible.
- Reconcile the treatment-variable naming inconsistency.
- Tie the reconstructed or stored Year 1 EAPs to the delivered published scores.
- Lock one versioned Year 1 parameter table and the three subject-specific transformation constants.

### Stage 2 — Build the harmonized registries

Create one record per:

`year × wave × cohort/sample × subject × administered grade × form × item version × scoring context`.

Maintain separate tables for:

- source response variables;
- analytic item IDs;
- exact item-version fingerprints;
- form membership and order;
- stimulus/testlet membership;
- keys, rubrics, maximum scores, and missingness rules;
- sample role and treatment exposure; and
- candidate link roles.

### Stage 3 — Build the form-and-sample link graph

Construct subject-specific graph nodes for every administration and edges only for verified common item versions. Report edge strength, difficulty coverage, content coverage, testlet concentration, exposure, and empirical drift. Disconnected components remain separate scales.

### Stage 4 — Replicate the Year 1 measurement model

Use Stata only as a controlled reference implementation. Do not run the inherited scripts against live legacy folders. Reproduce the fixed Year 1 parameters and score transformations using new guarded code and outputs under `work_root`.

### Stage 5 — Fit the new linked models in R

For each subject and connected graph component:

- begin with the simplest defensible model;
- use fixed verified Year 1 parameters where a genuine Y1 bridge exists;
- use multiple-group constraints for year, wave, grade, cohort, and sample differences;
- free drifted parameters rather than forcing bad links;
- preserve testlets and polytomous rubric structure;
- compare 1PL/Rasch and 2PL where appropriate; and
- report convergence, fit, local dependence, DIF/drift, linking stability, and score uncertainty.

### Stage 6 — Full-sample and control-only specifications

Estimate at least two planned specifications:

1. **Primary high-information calibration:** all eligible observations, with treatment hidden from anchor selection and treatment-related DIF assessed only after the measurement specification is frozen.
2. **Economist's control-only calibration:** estimate new Y2–Y3 item and group parameters using control observations only, while holding the verified Year 1 reference parameters fixed; then score treatment observations against that frozen measurement system.

Compare item parameters, linking constants, score ranks, score distributions, and treatment-effect estimates. The control-only model is especially valuable when treatment may change how students approach particular items, but it will have lower calibration precision.

## 7. Immediate next actions

1. Safely inspect the three Year 1 `.ster` files and export only non-sensitive model metadata and item-parameter tables to `work_root`.
2. Locate any historical Stata log that proves which code and package version generated the published scores.
3. Hash and compare the duplicate Year 1 baseline/endline candidate datasets before declaring a canonical source.
4. Read and normalize the Year 1 baseline and endline codebook workbooks into a source-variable-to-item-ID crosswalk under `work_root`.
5. Tie the fixed parameter objects to the delivered Year 1 score variables before opening any Year 2 or Year 3 estimation code.
