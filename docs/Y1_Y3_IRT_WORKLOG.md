# Y1–Y3 IRT worklog

> This is a chronological development record. Intermediate coverage statements
> below are deliberately preserved to show what failed and why; they are not
> the current specification. The production algorithm and current validation
> result are in `docs/IRT_PIPELINE_README.md`, and the resolved Year 3 Arabic
> Grade 1–2 issue is in `docs/ARABIC_GRADE_1_2_LINK_AUDIT.md`.

Short checkpoint log only. Detailed methods and code changes are recorded elsewhere in GitHub; data-bearing run logs remain under `work_root`.

## 2026-08-05

- Read the main Year 1 cleaning, pilot, scoring, and replication do-files; documented the inherited 2PL/fixed-endline approach.
- Verified all three stored models and reproduced the delivered Year 1 scores to machine precision.
- Built the Year 1 hash registry and confirmed two exact duplicate clean-data pairs.
- Mapped all 1,019 stored-model items and recovered their observed wave/grade administration. Legacy item IDs do not encode grade.
- Next: verify item versions against the forms/maps, then extend the link graph to Years 2 and 3.

## 2026-08-16

- Built a provisional half-length baseline design: five selected anchors for each of 33 required links, with form-level domain and tail checks. One French Grade 4 easy-tail item remains to resolve before assembly and timing.
- School-held-out IRT validation found full/short score correlations of 0.945 Arabic, 0.973 French, and 0.935 Maths; individual uncertainty rises, and 45 proposed item-grade slots cannot be observed until piloted.

## 2026-08-18

- Rebuilt the half-length baseline on the agreed grade shift: baseline G1 from prior baseline G1; baseline G2-G6 from prior endline G1-G5.
- Corrected unsafe same-base-ID anchor matches. The draft now has 332 rows and five exact-source anchors for each of 18 required baseline links.
- Independent adversarial review passed the corrected draft selection map. Final booklet keys and shared passage/image/rubric bundles remain separate assembly work.

## 2026-08-22

- El Mehdi's booklet review exposed unresolved historical-ID drift and partial French/Arabic composite tasks. The current short-form map is paused for a block-aware correction pass; the Maths division item should use ID `m2154`, while the Grade 4 historical row and all incomplete composites require replacement or full-task assembly.

## 2026-08-24

- Source-booklet review confirms the selected French and Arabic component scores remain meaningful when the complete parent prompt, passage, images, and rubric are restored.
- Test length must be counted by administered task, not scored rows. Historical Arabic `a250` has an ID collision and `a2146` has scoring-version drift; both require correction before the baseline map is final.

## 2026-09-07

- Re-read the Year 1 paper, Andy de Barros's production score do-file, the verified stored-model tie-outs, the Year 3 wave documentation, and the existing item and anchor audit outputs.
- Formalized the outcome architecture in `docs/IRT_OUTCOME_SCALING_DESIGN.md`: preserve delivered Year 1 scores and parameters, retain the raw Year 1 metric, and apply the fixed Year 1 endline-comparison transformation to later linked scores.
- Built a direct Year 1-to-Year 3 anchor manifest covering 1,906 Year 3 binary item-form rows. It identifies 983 direct fixed-parameter ID matches, 577 strict English-summary development matches, and 775 non-conflicted provisional ID matches. Full item-version review remains required.
- Ran treatment-blind direct fixed-anchor 2PL scoring for Year 3 baseline and endline. The strict-summary run converged for 20 of 36 nodes and produced 19,498 development scores; the broader non-conflicted ID run converged for 24 nodes and produced 23,147 scores. Unlinked nodes were left unscored.
- Verified zero duplicate outcome keys, zero missing theta values, no treatment fields in the output, and exact preservation of all 368 strict fixed-anchor parameter rows to numerical precision.
- Strict-versus-provisional score correlations exceed 0.997 in every common node, but the location shifts by about 0.62 raw-theta units for baseline Mathematics Grade 3 and endline Mathematics Grade 2. Those links require anchor reconciliation before causal use.

## 2026-09-07 — multi-year bridge and sensitivity implementation

- Registered 13 Year 2 response, item-map, and codebook candidates with hashes. The three wave-specific development inputs are explicitly provisional; no Year 2 file is marked canonical.
- Built an aggregate Year 2 operational registry with 48 wave-subject-grade nodes and 1,688 administered node-item rows from 21,876 source records. It excludes 75 rows with nonbinary observed responses from 2PL eligibility and retains 1,613 binary rows; tagged `.a` don't-know responses score zero and untagged system missing remains missing. Five duplicate pilot rows were removed deterministically; no partially administered form columns were found; treatment was not used.
- Built a 102-node Year 2-Year 3 graph with 3,519 binary item occurrences, 12,060 item-pair link records, 1,100 node edges, and an explicit full-version review queue. Every selected development edge requires at least five anchors.
- Strict summary evidence links 33 of 36 Year 3 baseline/endline nodes. Mathematics baseline Grade 4 and endline Grades 3 and 6 remain unlinked. The non-conflicted provisional-ID graph links all 36 nodes but is not valid final version evidence.
- The strict selected-path 2PL calibration fitted 37 required source/target nodes without warnings or convergence failures and produced 33,534 Year 3 scores. The provisional path fitted 38 nodes and produced 36,356 scores, but Year 3 baseline Mathematics Grade 1 generated an EM stability warning.
- The efficient pooled incomplete-booklet model fitted one common item bank per subject using all linked Year 2 and Year 3 data. All three strict models converged without warnings and scored the same 33 strict Year 3 nodes. The strict comparison-group-only models also converged without warnings and scored all students against control-calibrated item banks and node priors.
- The pooled provisional-ID models all hit the iteration cap and are quarantined. Their output is not eligible for score comparison or causal use.
- The binary-only strict grade-specific pooled sensitivity converged for 17 of 18 subject-grade models and scored 31 Year 3 nodes. Mathematics Grade 1 still has only two direct Year 1 anchors in the grade-restricted design and was not estimated; every fitted subject-grade model converged.
- Across strict chained, strict pooled-all, and strict pooled-comparison scores, node-level rank correlations are at least 0.9947. Pooled-all versus pooled-comparison correlations exceed 0.999 and their largest node mean difference is 0.136 raw-theta units. Chained-versus-pooled locations differ materially for long-path lower-grade Arabic and Mathematics nodes, reaching about 1.60 raw-theta units; these nodes cannot be frozen without link-path resolution.
- The binary-only deterministic school-development sensitivity converged for Arabic and scored 12 Year 3 nodes; French and Mathematics hit the iteration cap and were not scored. On 6,100 held-out student-node comparisons, school-development versus pooled-all Arabic scores have node correlations of at least 0.999, a maximum absolute node mean difference of 0.044, and a maximum RMSE of 0.056 raw-theta units. This supports out-of-sample item-bank stability for Arabic only.
- All fixed Year 1 and inherited bridge parameters reproduce their source values within 6.7e-15. Every outcome remains marked unapproved.

## 2026-09-07 — Year 3 treatment-effect sensitivity

- Statically reviewed the Year 3 production estimation and raw-score construction do-files after explicit authorization. The inherited design uses balanced student panels, baseline assignment, student fixed effects, post-by-pair-by-grade controls, matched-pair clustered inference, PDS-LASSO-selected covariates, and equal total cohort weight in pooled estimates.
- Implemented a guarded R comparison of eight nonempty IRT outcome variants and two binary raw-total standardizations. The approved wave files lack the full PDS-LASSO covariate set, so the current results estimate the unadjusted matched-DiD core and remain development-only.
- Used only 1,277 verified binary baseline/endline item-form occurrences. A response-value guard found zero observed non-binary occurrences among them. No non-binary item enters the score or regression.
- On the identical 12,971-student strict-core panel, the pooled overall effects are 0.352 SD for the do-file-style plain score, 0.364 for chained strict IRT, 0.345 for pooled strict-all, and 0.337 for pooled strict-comparison. Same-panel IRT-minus-plain differences are small and not statistically distinguishable in the overall comparison.
- The three strict IRT effects span 0.027 SD overall and at most 0.037 SD within a pooled subject estimate. Thus the previously observed 1.60 raw-theta location shift does not produce a comparably large ITT difference, though it remains a scale-validity blocker.
- Documented that the direct-anchor and school-development `Overall` estimates do not share three-subject coverage and must not be compared naively with the full-sample plain result.
- Extended the estimator to grade-specific treatment effects and reconciled the comparable Cohort 3 one-year block against both Ministry PDFs. The do-file-style plain score reproduces all 24 published grade-by-outcome coefficients with mean absolute difference 0.020 SD and maximum difference 0.058 SD; the narrative's within-grade standardization fits materially worse.
- Every new Cohort 3 overall estimate is within 0.03 SD of the Ministry's 0.403 SD headline. Grade-level IRT differences are less uniform, reaching more than 0.20 SD in several lower-grade Arabic and French cells; three strict Maths cells remain unavailable because their nodes are unlinked.
- Verified source hashes, standardization identities, exact-panel sample equality, Ministry reconciliation accuracy, aggregate-only output, and unapproved status through 30 automated checks. All checks pass.

## 2026-09-07 — all Ministry result groups on fixed-Year-1 IRT scales

- Extended strict chained, strict subject-pooled all-sample, strict subject-pooled comparison-only, strict grade-specific, and provisional chained scoring to every required Year 2 and Year 3 baseline/endline node. Year 1 scores are the unchanged delivered estimates in every IRT method; non-binary items remain excluded.
- Recreated the six exact Ministry cohort-by-exposure design panels and ran the inherited student-fixed-effect matched difference-in-differences specification with post-by-pair-by-grade controls, PDS-LASSO-selected covariates, matched-pair clustered standard errors, and cohort reweighting for pooled results.
- Produced 192 headline rows, 1,032 grade rows, 768 gender/baseline-performance heterogeneity rows, and 120 stable-sample rows across the Ministry sum score and five IRT methods. Omitted or non-estimable coefficients are retained as missing; no zero-standard-error coefficient is reported as a zero treatment effect.
- The reconstructed standardized-sum-score estimates match the saved Ministry headline, grade, and heterogeneity aggregate objects to numerical precision, including coefficients, standard errors, student counts, and school counts. The stable-sample student and school counts also match exactly.
- The published stable-sample coefficient rows do not reproduce from the same current standardized-sum-score panels even when the sample counts match. The comparison package therefore benchmarks stable IRT results against a fresh same-sample sum-score regression and retains the published row as a flagged lineage discrepancy.
- For the joint subject-pooled strict-all candidate, headline effects have mean absolute difference 0.059 SD from the same-sample sum score, maximum difference 0.168 SD, correlation 0.947, and identical signs in all 32 cells. Across the eight overall headline cells, the largest difference is 0.066 SD and the five IRT methods span at most 0.050 SD.
- The only headline significance-band change for the joint candidate is Cohort 2 after two years in Arabic: the sum-score estimate is significant at 5 percent and the IRT estimate at 10 percent. All other headline conclusions retain their significance band.
- Grade results are more sensitive: among 158 comparable joint-candidate cells, mean absolute difference is 0.095 SD and the maximum is 0.594 SD. The two sign changes are both uninformative thin cells (one estimate near zero and one with a standard error above one). Lower-grade French and one lower-grade mathematics link remain priority diagnostics; effects were not used to choose or remove anchors.
- All 25 automated validation checks pass. Outputs remain development-only pending anchor-version review and canonical source approval.

## 2026-09-07 — treatment-blind multiyear anchor purification

- Screened 225 prespecified Year 2–Year 3 grade, wave, year, pilot, and cohort links covering 5,907 item-link decisions. Only registered binary items entered; ordinary missing stayed missing and no late nonbinary item reached estimation.
- Used comparison observations for every source with treatment assignment. Treatment was never a DIF predictor. A separate all-student blinded pass was diagnostic only and could not determine anchor constraints.
- Combined school-clustered uniform/nonuniform logistic DIF, a joint Wald test, Mantel–Haenszel evidence, material-effect thresholds, Holm correction, and up to three purification iterations. The final comparison-only pass produced 560 robust item-link frees, 2,454 development retains, 2,806 material-only review flags, 80 unreliable/insufficient reviews, and 7 statistical-only reviews.
- The all-student first pass flagged 683 item-links versus 452 in the comparison-only first pass. Overall classifications agree for 91.4 percent of rows, but the flagged-set Jaccard is only 0.382. Treatment-exposed responses therefore remain excluded from anchor selection.
- Built targeted Andy-style frees rather than globally discarding flagged items. The broad grade/wave/year/pilot/cohort profile applies 444 node-item and 48 cohort-item frees; French and Maths converge, Arabic does not. Valid broad scores cover 34 baseline/endline nodes.
- Built an Andy-core profile using only operational-endline adjacent-grade DIF and baseline–endline drift. It applies 157 node-item frees. Arabic, French, and Maths all converge without warnings and score 42,119 records across 53 baseline/endline nodes.
- Andy-core versus original pooled score correlations are at least 0.989. The largest absolute node mean shift is 0.243 raw-theta units and the largest raw-theta RMSE is 0.327. The earlier 1.60 raw-theta path discrepancy is not reproduced on viable overlapping nodes, but remains unresolved for disconnected weak-link nodes.
- Balanced Year 3 pre/post coverage under Andy-core exists for Arabic Grades 3–6 and all French grades. No mathematics grade has both waves linked after purification, so a purified mathematics matched-DiD is unavailable.
- The Andy-core Year 3 matched-DiD is 0.274 SD (SE 0.076) for the available Arabic Grades 3–6 and 0.469 SD (SE 0.053) for all French grades. On identical panels these differ from original pooled strict IRT by +0.026 and -0.002 SD, respectively. The combined Arabic-plus-French available-cell effect changes by only +0.002 SD. No full three-subject overall effect is available.
- For directly comparable Cohort 3 French, Andy-core IRT is 0.407 SD (SE 0.050), versus 0.466 SD (SE 0.083) in the Ministry report and 0.409 SD in the original pooled strict model. The Arabic purified headline covers Grades 3–6 only and is not directly comparable with the Ministry all-grade headline.
- Twenty-five aggregate purification validation checks and the refreshed 30 treatment-effect validation checks pass. All 255 fixed Year 1 item parameters match the archived values to better than `1e-12`; every anchor and outcome remains marked unapproved.

## 2026-09-07 — mathematics bridge sensitivity

- Added a treatment-blind mathematics-specific rule because the five-to-eight-item mathematics links were too brittle under the standard OR-of-detectors free rule. Automatic mathematics frees now require concordant Holm-adjusted joint-logistic and Mantel–Haenszel evidence plus a material-effect flag and reliable clustered inference.
- Retained at least five items per directly screened mathematics link and labeled all floor-retained evidence explicitly. Seventeen item-link decisions and 22 mapped node-item occurrences are provisional identification anchors, not approved clean anchors.
- Permitted exact-summary four-anchor graph links for mathematics only; Arabic and French retain the five-anchor minimum. This connects Y3 Mathematics baseline Grade 4 and endline Grades 3 and 6 and yields balanced baseline/endline coverage for all six mathematics grades.
- The separate subject-pooled mixture model converged for Arabic, French, and Mathematics without warnings, scored 52,483 records over 63 baseline/endline nodes, and retained all 255 fixed Year 1 item parameters within `5.8e-15`.
- The all-cohort mathematics matched-DiD is 0.463 SD (SE 0.075), versus 0.453 SD for the do-file-style plain score on the identical panel. Cohort 3 mathematics IRT is 0.499 SD (SE 0.043), versus 0.497 SD (SE 0.041) in the Ministry report.
- Cohort 3 mathematics grade effects are 0.361, 0.594, 0.577, 0.434, 0.685, and 0.291 SD for Grades 1–6. The maximum absolute difference from the Ministry's corresponding sum-score estimates is 0.059 SD.
- All 25 expanded anchor-purification checks and all 30 refreshed treatment-effect checks pass. At that stage, the mathematics bridge remained a development sensitivity pending confirmation of the item-ID convention and analytical sparse-link checks.

## 2026-09-08 — mathematics item-ID confirmation

- The project lead confirmed that mathematics item IDs are immutable across Years 2 and 3: the same ID guarantees identical administered content, answer key, scoring rule, stimulus, and format, and edited items receive new IDs.
- Closed the proposed item-by-item mathematics content review. The bridge specification's remaining uncertainty is psychometric—empirical DIF and reliance on sparse four- or five-anchor links—not operational item-version ambiguity.
- No Kenza review of the 19 previously listed administration-specific mathematics versions is required. The next mathematics validation is analytical leave-anchor/link-out sensitivity.
