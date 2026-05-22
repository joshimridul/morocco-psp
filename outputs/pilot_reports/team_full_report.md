# Morocco PSP Endline Pilot: Full Internal Team Report

- Date: `2026-05-22`
- Audience: internal research team
- Main data file: `/Users/mriduljoshi/Dropbox/DID - Morocco Pioneer Schools Year 3/4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta`
- Item map used for question text and anchor review: [Item_map_20250517_mji.xlsx](</Users/mriduljoshi/Dropbox/DID - Morocco Pioneer Schools Year 3/3 - Data collection/02_Endline_Pilot/3 - Item map/Item_map_20250517_mji.xlsx>)
- Missing responses are counted as incorrect throughout the item analysis and IRT work.
- All item references in this report use the original `item` IDs from the cleaned pilot file.

## Purpose

This report consolidates the full internal pilot review into one document for the research team. It brings together:

- the form-level psychometric scan
- the easy/hard item review with missing counted as incorrect
- the revised item-action rules that reflect both measurement and causal objectives
- the IRT and vertical-linking results
- the operational guidance for `fix administration`
- the maths anomaly review and substitute-item drafting logic
- the anchor-gap diagnosis and concrete anchor recommendations

The core framing throughout is that this is not only a measurement exercise. It is also a causal inference exercise in a treated versus control setting at endline. That means some easy items remain useful if they capture real treatment-driven mastery gains, even if they add limited upper-tail information. At the same time, we still need enough stretch items to avoid ceiling effects and estimate impacts near the top of the treated distribution.

## Executive Summary

- The cleaned pilot file contains `3,523` rows. We removed `16` duplicate student-form records, leaving `3,507` records for the psychometric sample.
- We reviewed `430` binary scored items across Arabic, French, and Maths. Six fluency-count variables were excluded from the binary CTT/IRT workflow and should be analyzed separately.
- Treated students outperform control students in all `18` subject-grade cells.
- The psychometric problems differ sharply by subject:
  - Arabic has a substantial early-grade ceiling problem, especially around letter and word reading, and a separate upper-grade administration problem in writing/open-response tasks.
  - French is less broken psychometrically than it first appears; the biggest issue is item completion and administration, especially in oral, reading-aloud, and some upper-grade open-response items.
  - Maths has the strongest upper-tail measurement layer, but also the largest cluster of anomalous or overshooting items, especially in upper grades.
- For within-form IRT, `2PL` fit cleanly for many forms, but we used `1PL` fallbacks where `2PL` was unstable or gave implausible discrimination estimates.
- For vertical linking, the French chain works from Grades `1-6`; Arabic links from Grades `2-6` with Grade `1` isolated; Maths links from Grades `2-5` with Grades `1` and `6` isolated under the strict anchor rule.
- Under the revised rules, the priority order is:
  1. `replace`
  2. `fix administration`
  3. `soften slightly`
  4. `review treated-only ceiling`
  5. preserve `keep as stretch` and `keep for causal signal`

## Data And Analytic Choices

### Working sample

- Starting file: `pilot_clean_20260518_mji.dta`
- Deduplicated sample for psychometric analysis: `3,507`
- Binary scored items reviewed: `430`
- Non-binary fluency-count items excluded from binary IRT/CTT: `6`

### Scoring rule

- Missing is treated as incorrect for all item-level difficulty calculations and the main IRT work.
- This is intentionally conservative and reflects how missingness affects effective item difficulty in the administered instrument.
- For interpretation, we still separately tracked response coverage so we could distinguish:
  - truly difficult items
  - items that only look difficult because they were not asked, not completed, or not recorded consistently

### Why the treated group matters

The ultimate objective is causal: estimating and understanding effects for pioneer schools relative to control schools. Because of that, we did not want the control group to mechanically drive all easy/hard decisions. If an item is easy in treated schools but much less easy in control schools, that can still be a useful causal signal even if the item contributes little to upper-tail measurement in the treated group.

This led to the revised dual-objective classification:

- `keep_as_stretch`: hard enough to measure stronger students and avoid ceiling effects
- `keep_for_causal_signal`: easy for treated students, but still shows meaningful treated-control separation
- `soften_slightly`: somewhat too hard, but still promising and discriminating
- `keep_but_fix_administration`: item may be fine, but poor completion is making it look worse than it is
- `replace`: item adds too little value because it is shared-ceiling, genuinely too hard, anomalous, or otherwise nonfunctioning
- `review_treated_only_ceiling`: item is near-ceiling in treated schools but not clearly shared-ceiling; review for overall form balance rather than auto-remove

### Ceiling rule used in the final outputs

We changed the ceiling logic after discussion because automatically replacing any item above `90%` in treated schools would throw away some useful causal items.

Final rule:

- `shared ceiling` means both treated and control are at ceiling or near-ceiling. These are high-priority `replace` items.
- `treated-only ceiling` means treated is at ceiling or near-ceiling but control is not. These are `review_treated_only_ceiling`, not automatic replace.
- Easy items with strong treated-control gaps can be retained as `keep_for_causal_signal`.

This matters especially in Maths and early Arabic, where some easy items capture real pioneer-school mastery gains even if they contribute less information at the top of the treated distribution.

## Form-Level Lay Of The Land

### Arabic

- Grade `1`: `N=179`, treated mean=`82.1%`, control mean=`67.0%`, alpha=`0.97`, response=`94.4%`, IRT=`1PL`
- Grade `2`: `N=200`, treated mean=`65.4%`, control mean=`57.4%`, alpha=`0.89`, response=`93.9%`, IRT=`1PL`
- Grade `3`: `N=200`, treated mean=`59.8%`, control mean=`51.9%`, alpha=`0.91`, response=`92.1%`, IRT=`2PL`
- Grade `4`: `N=200`, treated mean=`44.4%`, control mean=`35.5%`, alpha=`0.93`, response=`81.7%`, IRT=`2PL`
- Grade `5`: `N=195`, treated mean=`56.9%`, control mean=`45.2%`, alpha=`0.92`, response=`84.2%`, IRT=`2PL`
- Grade `6`: `N=195`, treated mean=`51.2%`, control mean=`46.6%`, alpha=`0.92`, response=`76.1%`, IRT=`2PL`

### French

- Grade `1`: `N=195`, treated mean=`55.6%`, control mean=`38.2%`, alpha=`0.95`, response=`72.4%`, IRT=`1PL`
- Grade `2`: `N=199`, treated mean=`43.5%`, control mean=`30.0%`, alpha=`0.95`, response=`74.6%`, IRT=`2PL`
- Grade `3`: `N=200`, treated mean=`52.6%`, control mean=`40.9%`, alpha=`0.95`, response=`82.2%`, IRT=`1PL`
- Grade `4`: `N=200`, treated mean=`43.2%`, control mean=`28.6%`, alpha=`0.89`, response=`64.1%`, IRT=`2PL`
- Grade `5`: `N=195`, treated mean=`46.2%`, control mean=`31.4%`, alpha=`0.93`, response=`65.2%`, IRT=`1PL`
- Grade `6`: `N=195`, treated mean=`55.4%`, control mean=`41.2%`, alpha=`0.92`, response=`72.7%`, IRT=`2PL`

### Maths

- Grade `1`: `N=180`, treated mean=`64.8%`, control mean=`52.2%`, alpha=`0.88`, response=`91.8%`, IRT=`2PL`
- Grade `2`: `N=200`, treated mean=`57.2%`, control mean=`47.9%`, alpha=`0.90`, response=`90.9%`, IRT=`2PL`
- Grade `3`: `N=199`, treated mean=`54.0%`, control mean=`51.6%`, alpha=`0.91`, response=`89.6%`, IRT=`2PL`
- Grade `4`: `N=200`, treated mean=`51.2%`, control mean=`40.4%`, alpha=`0.89`, response=`94.1%`, IRT=`2PL`
- Grade `5`: `N=190`, treated mean=`49.6%`, control mean=`31.6%`, alpha=`0.91`, response=`89.5%`, IRT=`2PL`
- Grade `6`: `N=185`, treated mean=`34.3%`, control mean=`24.0%`, alpha=`0.89`, response=`79.3%`, IRT=`1PL`

## Subject-Level Diagnosis

### Arabic

Main problem pattern:

- early-grade ceiling, especially around letter and word reading
- weak Grade `1-2` and `2-3` anchor transitions
- upper-grade completion problems in writing and open-response tasks

What the Arabic item review says:

- `replace`: `15` form-item occurrences
- `review_treated_only_ceiling`: `15`
- `keep_but_fix_administration`: `16`
- `keep_as_stretch`: `16`
- `keep_for_causal_signal`: `10`

Interpretation:

- Arabic does not suffer from a lack of difficult items overall.
- The main measurement problem is too many very easy items in the earliest grades.
- The main operational problem is that upper-grade writing and informational-text items often have low completion, which makes them look harder than they really are under the missing-equals-wrong rule.

High-priority Arabic `replace` items:

- Grade `1`: `a118y3_nv3`, `a115y3_nv3`, `a117y3_nv3`, `a122y3_nv3`
- Grade `2`: `a214_nv`, `a215`, `a218`, `a217`
- Grade `3`: `a219_nv`, `a214_nv`, `a217`, `a215`, `a218`
- Grade `5`: `a2164_nv`, `a2137`

What these represent:

- most of the early-grade replacements are true shared-ceiling items
- `a2164_nv` is the notable genuinely too-hard Arabic item
- `a2137` is extremely easy in both groups and adds little incremental value

### French

Main problem pattern:

- poor completion and administration dominate the French results
- the vertical scale is comparatively better than Arabic and Maths
- there are few items that clearly need replacement on psychometric grounds alone

What the French item review says:

- `replace`: `3` form-item occurrences
- `review_treated_only_ceiling`: `6`
- `keep_but_fix_administration`: `67`
- `keep_as_stretch`: `20`
- `keep_for_causal_signal`: `9`

Interpretation:

- French looks worse than it is if we look only at scored `% correct`.
- The biggest issue is not that the items are intrinsically too hard. The biggest issue is that too many oral and open-response items were not completed consistently.
- Once administration is improved, much of the French form is likely salvageable without major rewriting.

High-priority French `replace` items:

- Grade `3`: `f280`
- Grade `6`: `f2118`, `f2119`

What these represent:

- `f280` is the main treated-below-control anomaly in French
- `f2118` and `f2119` are shared-ceiling items in Grade `6`

### Maths

Main problem pattern:

- strongest upper-tail measurement layer of the three subjects
- enough difficult items remain even after revising the worst ceiling items
- main risk is not too few hard items, but too many hard items that overshoot or behave oddly, especially in Grades `5-6`

What the Maths item review says:

- `replace`: `14` form-item occurrences
- `review_treated_only_ceiling`: `4`
- `soften_slightly`: `2`
- `keep_as_stretch`: `25`
- `keep_for_causal_signal`: `3`

Interpretation:

- Maths already has enough stretch items. We do not need more difficulty for its own sake.
- What we need is better-functioning difficulty.
- After revising the clearly shared-ceiling items and the nonfunctioning hard items, the top end of Maths measurement remains adequately populated.

## Why We Did Not Auto-Remove Every Easy Item

This was a central conceptual issue in the review.

An item can be easy in treated schools and still be valuable because it captures real treatment-induced mastery relative to control. For example, a Grade `2` Maths item like `m23y3_nv3` (`8+3 =`) is easy for treated students, but it still shows a large treated-control gap and adequate discrimination. That makes it valuable for documenting foundational causal gains even if it does less for upper-tail measurement.

So the target form architecture should contain:

- some foundational items that show treatment-driven mastery gains
- some middle items that measure the body of the distribution
- some stretch items that keep the top end open

The goal is not to remove all easy items. The goal is to remove:

- items that are easy in both groups and add little value
- items that are too hard to function
- items whose observed difficulty is mainly an administration artifact
- items whose behaviour conflicts with the causal story and may reflect miscoding, content mismatch, or poor item design

## Meaning Of Each Decision Category

### `replace`

Use when the item is:

- shared-ceiling with little incremental value
- genuinely too hard to function
- anomalous, including treated-below-control patterns that do not fit the broader result
- otherwise psychometrically weak in a way that likely requires item redesign rather than field-process fixes

### `keep_but_fix_administration`

Use when the item may be fine in content terms, but too much missingness is driving the scored difficulty. These items should not be softened or replaced first. They should first be administered, captured, and scored properly.

### `soften_slightly`

Use when the item is a bit too hard, but still discriminates. These are lower-priority edits because the item is already doing some useful upper-tail work.

### `review_treated_only_ceiling`

Use when the item is at or near ceiling in treated schools but not in control schools. These items should be reviewed for overall form balance, not automatically removed.

### `keep_as_stretch`

Use when the item is hard enough to help distinguish stronger students and prevent ceiling effects, but not so hard that it stops functioning.

### `keep_for_causal_signal`

Use when the item is easy for treated students but still captures a meaningful treated-control mastery gap.

## Actual Guidance For `Fix Administration`

This guidance should be treated as operational field and scoring guidance, not psychometric guidance.

For all `keep_but_fix_administration` items:

- administer every item unless the protocol explicitly includes a stop rule
- if the student responds incorrectly, code `0`; do not leave the item blank
- if the student is silent, repeat the prompt once exactly as scripted, wait a fixed amount of time, then code `0` if still no response
- distinguish `not administered`, `no response`, and `incorrect` in the raw data capture, even if all are later scored incorrect in the analysis
- add an end-of-assessment completion check before the form is closed
- monitor item-level completion rates by enumerator and form daily

French-specific guidance:

- Grade `1-3` oral and oral-reading items must be asked one by one to every child
- assessors should not invent informal discontinue rules inside oral or reading blocks
- oral answers in the wrong language should count as attempted and be scored `0`, not left missing
- upper-grade French oral and writing prompts need enough wait time and writing time

Arabic-specific guidance:

- Grade `4-6` writing and informational-text open responses need protected time near the end of the session
- students should be explicitly told to attempt every prompt
- any written attempt should be captured and scored with the rubric
- informational-text sub-questions must all be asked and recorded separately

Bottom line:

- for these items, fix administration before softening or replacing content

## Maths: High-Priority Problem Items

The most concerning Maths anomaly items, where treated students did worse than control students, are:

- Grade `2` `m239_nv2`: `12 × 4`
- Grade `2` `m240_nv3`: `43 x 2`
- Grade `3` `m275`: garden-shape item
- Grade `3` `m278_nv3`: story-title item
- Grade `4` `m294_nv3`: `3/5 + 1/5 =`
- Grade `6` `m620y3_nv3`: angle `ACB`
- Grade `6` `m68y3_nv3`: `8/5 + 7/4 =`

These matter because the negative treated-control gaps are hard to reconcile with the broader pattern that treated students outperform control students in every subject-grade form on average.

Interpretation:

- the Grade `2` multiplication items and the Grade `4` fractions item are especially concerning because response coverage is good, so this does not look like a simple missingness artifact
- `m275`, `m620y3_nv3`, and `m68y3_nv3` may also reflect overshooting difficulty or content/scoring issues
- these items are higher priority than merely easy items, because they may distort both causal interpretation and test targeting

There is also a separate set of Maths items that are simply too hard:

- Grade `4` `m295_nv3`
- Grade `5` `m2119_nv3`
- Grade `5` `m2120_nv3`
- Grade `5` `m2121_nv`
- Grade `6` `m610y3_nv3`

And two Maths items that should be softened slightly rather than fully replaced:

- Grade `6` `m69y3_nv3`
- Grade `6` `m622y3_nv3`

## Maths Item Substitutes

We drafted substitute Maths items using the item map and the underlying skill/question-type logic. The purpose was not to change the construct, but to capture the same skill in a way that functions better psychometrically.

The draft table is here:

- [math_substitute_item_draft.md](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/math_substitute_item_draft.md)
- [math_substitute_item_draft.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/math_substitute_item_draft.csv)

The replacement logic used there is:

- preserve the same underlying skill
- preserve the question type where possible
- adjust the numerical values, prompt framing, or structure so the item is less anomalous, less overshot, or less ceiling-prone
- be careful with common items that are reused across grades, because changing them in one grade only can weaken the anchor structure

## Vertical Linking And Anchor Implications

### What linked cleanly

- French forms one linked chain across Grades `1-6`
- Arabic forms one linked chain across Grades `2-6`
- Maths forms one linked chain across Grades `2-5`

### What did not link cleanly

- Arabic Grade `1` remains isolated
- Maths Grade `1` remains isolated
- Maths Grade `6` remains isolated

### Why this matters

Linked theta values should only be compared within the same chain. On the current instrument:

- Arabic Grade `1` is not directly comparable to Arabic Grades `2-6`
- Maths Grade `1` is not directly comparable to Maths Grades `2-5`
- Maths Grade `6` is not directly comparable to Maths Grades `2-5`

The linked grade means are also not cleanly monotonic, especially in Arabic and French. That suggests that the vertical scales are still diagnostic rather than final.

### Anchor gaps identified

- Arabic `g1-g2`: broken
- Arabic `g2-g3`: weak
- Arabic `g5-g6`: fragile
- Maths `g1-g2`: broken
- Maths `g5-g6`: broken

French `g1-g2` is thinner than ideal, but the French vertical chain still holds, so we did not prioritize new French anchor recommendations in this round.

## Recommended Anchor Strategy

Detailed files:

- [anchor_recommendations.md](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/anchor_recommendations.md)
- [anchor_recommendations.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/anchor_recommendations.csv)

Priority order:

- `Critical`: Arabic `g1-g2`, Maths `g1-g2`, Maths `g5-g6`
- `Strengthen`: Arabic `g2-g3`, Arabic `g5-g6`

Recommended anchors:

### Arabic `g1-g2`

Add:

- `a245y3_nv3`
- `a247y3_nv3`
- `a249y3_nv3`
- `a251y3_nv3`

Rationale:

- these are harder and better-discriminating Grade `1` items than the current shared items
- they are much less likely to collapse into immediate ceiling in Grade `2`

### Arabic `g2-g3`

Keep:

- `a261_nv`
- `a324y3_nv3`

Add:

- `a251`
- `a263_nv3`
- `a322y3_nv3`

Rationale:

- the current edge works, but only thinly
- these additions broaden the anchor set beyond the two surviving writing anchors

### Arabic `g5-g6`

Keep:

- `a2145_nv`
- `a2161`

Add:

- `a2159`
- `a2152`
- `a2153`
- `a2155`

Rationale:

- the current edge technically survives, but only narrowly
- these additions should stabilize the link with more mid-difficulty comprehension anchors

### Maths `g1-g2`

Keep:

- `m210`

Add:

- `m216_nv3`
- `m218_nv`
- `m219_nv3`
- `m213_nv`

Rationale:

- the current common items are too easy to sustain this edge
- these Grade `1` items are harder and more discriminating, so they should hold better in Grade `2`

### Maths `g5-g6`

Keep:

- `m2139_nv`

Add:

- `m2125_nv3`
- `m2126_nv3`
- `m2133_nv3`
- `m2135`

Rationale:

- the current `g5-g6` edge effectively rests on one functioning anchor
- these additions improve range and reduce dependence on a single calculation item

## Subject-Specific Recommended Strategy

### Arabic

- replace the shared-ceiling early-grade letter and word items first
- keep foundational causal-signal items that still separate treated from control
- fix completion and scoring on Grades `4-6` writing and informational-text tasks before revising content
- redesign the broken `g1-g2` anchor edge and strengthen `g2-g3` and `g5-g6`

### French

- do not overreact to low `% correct` values without checking completion
- focus first on administration and scoring discipline
- replace only the very small set of clearly broken items
- preserve the current vertical chain while cleaning up completion problems

### Maths

- preserve the existing stretch layer
- replace anomalous treated-below-control items first
- replace clearly too-hard items that overshoot the target range
- review but do not automatically remove treated-only ceiling items
- strengthen the broken anchor edges at `g1-g2` and `g5-g6`

## Immediate Priorities If The Team Is Time-Constrained

1. Replace nonfunctioning items.
2. Fix administration and completion on French and upper-grade Arabic items.
3. Soften slightly only where items are borderline-too-hard but still otherwise useful.
4. Review treated-only ceiling items for balance, but do not treat them as automatic deletions.
5. Implement anchor repairs at Arabic `g1-g2`, Maths `g1-g2`, and Maths `g5-g6`.

## Supporting Files

Main item-level outputs:

- [pilot_item_action_sheet.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_item_actions/pilot_item_action_sheet.csv)
- [pilot_item_action_summary_by_subject.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_item_actions/pilot_item_action_summary_by_subject.csv)
- [pilot_item_summary.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_psychometrics/pilot_item_summary.csv)
- [pilot_irt_item_summary.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_psychometrics/pilot_irt_item_summary.csv)

Vertical linking outputs:

- [pilot_vertical_linking_summary.md](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_vertical_linking/pilot_vertical_linking_summary.md)
- [pilot_vertical_anchor_pair_summary.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_vertical_linking/pilot_vertical_anchor_pair_summary.csv)
- [pilot_vertical_anchor_items_used.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_vertical_linking/pilot_vertical_anchor_items_used.csv)
- [pilot_vertical_linked_grade_summary.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_vertical_linking/pilot_vertical_linked_grade_summary.csv)

Revision work products:

- [math_substitute_item_draft.md](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/math_substitute_item_draft.md)
- [math_substitute_item_draft.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/math_substitute_item_draft.csv)
- [anchor_recommendations.md](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/anchor_recommendations.md)
- [anchor_recommendations.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/anchor_recommendations.csv)

Replication and QA:

- [replication_check_report.md](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/replication_check_report.md)
- [replication_check_details.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/replication_check_details.csv)
- [replication_irt_refit_summary.csv](/Users/mriduljoshi/Github/morocco-psp/outputs/pilot_reports/replication_irt_refit_summary.csv)

## Bottom Line

The pilot does not point to one generic problem. It points to three different jobs:

- in Arabic, harden the easy early-grade forms and fix completion in upper grades
- in French, fix administration first
- in Maths, keep the stretch layer but replace the hard items that overshoot or behave anomalously

At the instrument level, the biggest technical design problem now is the anchor structure in Arabic and Maths. At the operational level, the biggest administration problem is French and upper-grade Arabic completion. At the causal-inference level, the key principle is to preserve a mix of foundational causal-signal items and upper-tail stretch items rather than optimizing only for one or the other.
