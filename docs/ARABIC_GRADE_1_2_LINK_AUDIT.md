# Year 3 Arabic Grade 1–2 link audit

## Finding

The Year 3 Arabic Grade 1 and Grade 2 tests are present and contain eligible
binary questions. Their earlier absence from the IRT outcome was caused by an
overly conservative anchor-screening rule, not by missing data, non-binary
items, or changed item identifiers.

The operational link graph contains:

- 44 common binary questions between the Grade 1 and Grade 2 baseline tests;
- 41 common binary questions between the Grade 1 baseline and endline tests;
- 11 common binary questions between the Grade 2 baseline and endline tests;
- 11 common binary questions between the Grade 1 and Grade 2 endline tests.

Under the earlier rule, separate DIF warnings across several comparisons broke
the parameter-equality components needed to connect the lower-grade tests. The
critical baseline Grade 1–Grade 2, Grade 1 baseline–endline, and Grade 2
baseline–endline links were left with only 8, 4, and 2 usable anchors in the
resulting network. Three assessment groups consequently had no path to the
fixed Year 1 scale.

## Resolution

The preferred rule is now the same for Arabic, French, and mathematics. An
item occurrence is freed only when the joint-logistic and Mantel–Haenszel DIF
checks agree and the difference is material. The procedure aims to retain at
least five verified anchors on every required screened link. After exact
item-version mapping, a four-anchor graph edge is allowed only when needed to
connect an otherwise isolated assessment group. Every item retained because of
this floor is explicitly flagged; no treatment estimate is used in the
decision.

With this rule, all 36 Year 3 baseline/endline subject-by-grade groups are
connected. All 12 Arabic groups are linked, and the weakest selected path for
Arabic Grades 1–2 contains five anchors. The only remaining unlinked node is a
Grade 6 mathematics pilot form, which is not used in any requested
baseline/endline treatment comparison.

The preferred score file now contains the following Cohort 3 Arabic records:

| Administered grade | Baseline | Endline |
|---:|---:|---:|
| 1 | 642 | 614 |
| 2 | 678 | 658 |

These are scored student-test records, not imputed observations. The release
check independently requires all four cells to remain present.

## Reproducible evidence

The full pipeline writes the relevant evidence below the configured Dropbox
`work_root`:

```text
outputs/y1_y3_irt/05_anchor_purification/comparison_only_math_bridge5/
  arabic_grade_1_2_link_audit.csv

outputs/y1_y3_irt/05_anchor_purification/comparison_only/
  multiyear_andy_core_math_bridge5_purified_selected_paths.csv
  multiyear_anchor_link_decisions_with_targets_andy_core_math_bridge5.csv

derived/y1_y3_irt/
  multiyear_purified_andy_core_math_bridge5_occurrence_mapping.csv
```

The internal profile and file names are retained for backward compatibility;
the reader-facing description is “the preferred consensus-and-connectivity
DIF rule.”
