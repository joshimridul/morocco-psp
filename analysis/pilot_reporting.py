import os
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(os.getenv("PROJECT_ROOT", "/Users/mriduljoshi/Github/morocco-psp"))
PILOT_DATA_PATH = Path(
    os.getenv(
        "PILOT_DATA_PATH",
        "/Users/mriduljoshi/Dropbox/DID - Morocco Pioneer Schools Year 3/4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta",
    )
)

PSYCH_DIR = PROJECT_ROOT / "outputs" / "pilot_psychometrics"
VERT_DIR = PROJECT_ROOT / "outputs" / "pilot_vertical_linking"
ACTION_DIR = PROJECT_ROOT / "outputs" / "pilot_item_actions"
REPORT_DIR = PROJECT_ROOT / "outputs" / "pilot_reports"


def fmt_pct(x: float | int | None) -> str:
    if pd.isna(x):
        return "NA"
    return f"{100 * float(x):.1f}%"


def fmt_num(x: float | int | None, digits: int = 3) -> str:
    if pd.isna(x):
        return "NA"
    return f"{float(x):.{digits}f}"


def prepare_action_data() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    action_sheet = pd.read_csv(ACTION_DIR / "pilot_item_action_sheet.csv")
    action_summary = pd.read_csv(ACTION_DIR / "pilot_item_action_summary_by_subject.csv")
    reason_summary = pd.read_csv(ACTION_DIR / "pilot_item_action_reason_summary.csv")
    form_summary = pd.read_csv(PSYCH_DIR / "pilot_form_summary.csv")
    link_summary = pd.read_csv(VERT_DIR / "pilot_vertical_link_summary.csv")
    link_grade_summary = pd.read_csv(VERT_DIR / "pilot_vertical_linked_grade_summary.csv")

    reason_order = {
        "treated_below_control_anomaly": 1,
        "too_hard_replace": 2,
        "too_hard_or_weak_replace": 3,
        "shared_ceiling_limited_incremental_value": 4,
        "low_coverage_missing_drives_difficulty": 5,
        "treated_only_ceiling_review": 6,
        "borderline_too_hard_but_discriminating": 7,
        "useful_upper_tail_item": 8,
        "foundational_causal_signal_item": 9,
    }
    rec_priority = {
        "replace": 1,
        "keep_but_fix_administration": 2,
        "soften_slightly": 3,
        "review_treated_only_ceiling": 4,
        "keep_as_stretch": 5,
        "keep_for_causal_signal": 6,
    }

    action_sheet["reason_rank"] = action_sheet["recommendation_reason"].map(reason_order).fillna(99).astype(int)
    action_sheet["recommendation_priority"] = (
        action_sheet["recommendation"].map(rec_priority).fillna(99).astype(int)
    )
    action_sheet["treated_minus_control"] = action_sheet["p_treated"] - action_sheet["p_control"]
    action_sheet = action_sheet.sort_values(
        [
            "recommendation_priority",
            "reason_rank",
            "subject",
            "grade",
            "p_treated",
            "response_rate_all",
            "item",
        ]
    )

    return action_sheet, action_summary, reason_summary, form_summary, link_summary, link_grade_summary


def write_supporting_csvs(action_sheet: pd.DataFrame) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)

    ministry_queue = action_sheet[
        action_sheet["recommendation"].isin(
            ["replace", "keep_but_fix_administration", "soften_slightly"]
        )
    ].copy()
    ministry_queue["priority_order"] = ministry_queue["recommendation"].map(
        {"replace": 1, "keep_but_fix_administration": 2, "soften_slightly": 3}
    )
    ministry_queue = ministry_queue.sort_values(
        ["priority_order", "reason_rank", "subject", "grade", "p_treated", "item"]
    )
    ministry_queue.to_csv(REPORT_DIR / "ministry_priority_action_queue.csv", index=False)

    action_counts_by_grade = (
        action_sheet.groupby(["subject", "grade", "recommendation"])
        .size()
        .unstack(fill_value=0)
        .reset_index()
    )
    action_counts_by_grade.to_csv(REPORT_DIR / "action_counts_by_subject_grade.csv", index=False)


def internal_report(
    action_sheet: pd.DataFrame,
    action_summary: pd.DataFrame,
    reason_summary: pd.DataFrame,
    form_summary: pd.DataFrame,
    link_summary: pd.DataFrame,
    link_grade_summary: pd.DataFrame,
) -> str:
    lines: list[str] = []
    lines.append("# Internal pilot analysis report")
    lines.append("")
    lines.append(f"- Data file: `{PILOT_DATA_PATH}`")
    lines.append("- Audience: internal research team")
    lines.append("- Missing responses are counted as incorrect throughout the item analysis and IRT work.")
    lines.append("- Item strategy uses the revised dual objective: preserve both causal signal items and stretch items.")
    lines.append("- All item references use the original item IDs from the cleaned pilot file.")
    lines.append(
        "- Action counts in this report are form-item occurrences unless otherwise noted, so common items reused across grades can appear more than once."
    )
    lines.append("")

    lines.append("## Executive summary")
    lines.append("")
    lines.append(
        "- The cleaned pilot file contains 3,523 rows; 16 duplicate student-form records were removed, leaving 3,507 records in the psychometric sample."
    )
    lines.append(
        "- We reviewed 430 binary scored items. Six non-binary fluency-count variables were excluded from the binary CTT/IRT workflow."
    )
    lines.append(
        "- Treated students outperform control students in all 18 subject-grade cells, but the psychometric problems differ by subject: Arabic has many very easy early-grade items, French is dominated by administration and completion problems, and maths has the strongest stretch layer but also the highest number of anomalous or overshooting hard items."
    )
    lines.append(
        "- The strict vertical linking exercise keeps one full French chain (grades 1-6), one Arabic chain (grades 2-6, with grade 1 isolated), and one maths chain (grades 2-5, with grades 1 and 6 isolated)."
    )
    lines.append(
        "- If time is short, the recommended order is: `replace` nonfunctioning items first, `fix administration` second, and `soften slightly` third."
    )
    lines.append("")

    lines.append("## Form-level lay of the land")
    lines.append("")
    for _, row in form_summary.sort_values(["subject", "grade"]).iterrows():
        lines.append(
            f"- {row['subject']} grade {int(row['grade'])}: N={int(row['n_students'])}, "
            f"treated mean={fmt_pct(row['mean_pct_correct_treated'])}, "
            f"control mean={fmt_pct(row['mean_pct_correct_control'])}, "
            f"alpha={fmt_num(row['alpha'], 2)}, response={fmt_pct(row['avg_response_rate'])}, "
            f"IRT={row['irt_model_used']} ({row['irt_fit_reason']})."
        )
    lines.append("")

    lines.append("## Subject strategy summary")
    lines.append("")
    for _, row in action_summary.sort_values("subject").iterrows():
        lines.append(
            f"- {row['subject']}: {int(row['form_items_with_action'])} form-item occurrences need action out of "
            f"{int(row['total_form_items'])}; keep stretch {int(row.get('keep_as_stretch', 0))}, "
            f"keep causal signal {int(row.get('keep_for_causal_signal', 0))}, "
            f"soften slightly {int(row.get('soften_slightly', 0))}, "
            f"treated-only ceiling review {int(row.get('review_treated_only_ceiling', 0))}, "
            f"fix administration {int(row.get('keep_but_fix_administration', 0))}, "
            f"replace {int(row.get('replace', 0))}. "
            f"Unique item IDs with action: {int(row['unique_item_ids_with_action'])}."
        )
    lines.append("")

    lines.append("## What is going wrong by subject")
    lines.append("")
    for subject in ["Arabic", "French", "Maths"]:
        lines.append(f"### {subject}")
        subject_reasons = reason_summary[reason_summary["subject"] == subject]
        for _, row in subject_reasons.iterrows():
            lines.append(
                f"- {row['recommendation_reason']}: {int(row['n_form_items'])} form-item occurrences."
            )
        lines.append("")

    lines.append("## Vertical linking and anchor implications")
    lines.append("")
    for _, row in link_summary.sort_values(["subject", "chain_id"]).iterrows():
        lines.append(
            f"- {row['subject']} {row['chain_id']} (grades {row['grades']}): "
            f"{int(row['n_linked_items'])} linked items, {int(row['n_anchor_items_used'])} anchor items used, "
            f"{row['model_used']} fit ({row['fit_reason']})."
        )
    lines.append("")
    lines.append("Grade means on linked chains:")
    for _, row in link_grade_summary.sort_values(["subject", "chain_id", "grade"]).iterrows():
        lines.append(
            f"- {row['subject']} {row['chain_id']} grade {int(row['grade'])}: "
            f"theta treated={fmt_num(row['theta_mean_treated'])}, "
            f"control={fmt_num(row['theta_mean_control'])}, "
            f"gap={fmt_num(row['treated_minus_control'])}."
        )
    lines.append("")
    lines.append(
        "- Interpretation note: linked theta values should only be compared within the same chain. Arabic grade 1 and maths grades 1 and 6 remain outside the main linked chains."
    )
    lines.append("")

    lines.append("## Priority order if the team is time-constrained")
    lines.append("")
    lines.append("1. Replace nonfunctioning items.")
    lines.append("2. Fix administration and completion on otherwise useful items.")
    lines.append("3. Soften slightly only where items are borderline-too-hard but still discriminating.")
    lines.append("4. Review treated-only ceiling items for overall form balance, but do not automatically remove them.")
    lines.append("5. Preserve functioning stretch items and causal signal items when revising the rest of the form.")
    lines.append("")

    for subject in ["Arabic", "French", "Maths"]:
        lines.append(f"## Detailed actions: {subject}")
        lines.append("")
        sub = action_sheet[action_sheet["subject"] == subject].copy()
        for rec_name in [
            "replace",
            "keep_but_fix_administration",
            "soften_slightly",
            "review_treated_only_ceiling",
            "keep_as_stretch",
            "keep_for_causal_signal",
        ]:
            rec_df = sub[sub["recommendation"] == rec_name]
            if rec_df.empty:
                continue
            lines.append(f"### {rec_name}")
            for _, row in rec_df.sort_values(["grade", "p_treated", "item"]).iterrows():
                lines.append(
                    f"- grade {int(row['grade'])} `{row['item']}`: "
                    f"treated p={fmt_num(row['p_treated'])}, control p={fmt_num(row['p_control'])}, "
                    f"response={fmt_pct(row['response_rate_all'])}, CITC={fmt_num(row['corrected_item_total'])}. "
                    f"{row['item_label']} [{row['recommendation_reason']}]"
                )
            lines.append("")

    lines.append("## Tradeoff framing")
    lines.append("")
    lines.append(
        "- `replace` items are the most important because they either add little marginal information, overshoot the skill range, or behave anomalously against the causal story."
    )
    lines.append(
        "- `keep_but_fix_administration` items should not be misread as weak items; they often look hard only because they were not completed often enough."
    )
    lines.append(
        "- `soften_slightly` items are the lowest-priority edits because they are already close to usable upper-tail measurement."
    )
    lines.append(
        "- `review_treated_only_ceiling` items are easy for pioneer schools, but not necessarily for control schools, so they should be reviewed for balance rather than auto-removed."
    )
    lines.append(
        "- `keep_as_stretch` and `keep_for_causal_signal` together define the recommended target form architecture: a mix of foundational causal items, middle items, and upper-tail stretch items."
    )

    return "\n".join(lines)


def ministry_report(action_sheet: pd.DataFrame, action_summary: pd.DataFrame) -> str:
    lines: list[str] = []
    lines.append("# Ministry-facing pilot note")
    lines.append("")
    lines.append("- Audience: Ministry of Education")
    lines.append("- Purpose: identify the most important form changes from the pilot before finalizing endline instruments.")
    lines.append("- All item references use the original item IDs from the cleaned pilot file.")
    lines.append(
        "- Counts in this note refer to form-item occurrences, so a shared item used in multiple grades can appear more than once."
    )
    lines.append("")
    lines.append("## Main message")
    lines.append("")
    lines.append(
        "- The pilot suggests that the instruments are already capturing meaningful differences between pioneer and non-pioneer schools, but the forms still need targeted revisions."
    )
    lines.append(
        "- We do **not** recommend removing all difficult items. Some difficult items are useful and should stay, because they help measure stronger students and reduce ceiling effects."
    )
    lines.append(
        "- The most urgent work is to replace items that are not functioning well, then fix administration on items that appear stronger than their scored results suggest, and only then soften a small number of borderline-too-hard items."
    )
    lines.append(
        "- Easy items that are only near-ceiling in pioneer schools are no longer treated as automatic replacements; they should be reviewed only if the overall form becomes too easy."
    )
    lines.append("")

    lines.append("## Priority order if time is limited")
    lines.append("")
    lines.append("1. Replace items")
    lines.append("2. Fix administration")
    lines.append("3. Soften slightly")
    lines.append("")

    lines.append("## Higher-level problems by subject")
    lines.append("")
    lines.append(
        "- Arabic: the largest problem is too many very easy early-grade items. Only the items that are also near-ceiling in control schools are now treated as clear replacements; the rest should be reviewed more cautiously."
    )
    lines.append(
        "- French: the main problem is administration. Many oral and writing items, especially in grade 1 and upper grades, look harder than they really are because response coverage is low."
    )
    lines.append(
        "- Maths: the forms already contain many useful hard items. The main issue is not a lack of difficulty, but a subset of items that are too easy, too hard, or behave unexpectedly relative to the control group."
    )
    lines.append("")

    lines.append("## Priority 1: replace items")
    lines.append("")
    replace_df = action_sheet[action_sheet["recommendation"] == "replace"].copy()
    for subject in ["Arabic", "French", "Maths"]:
        sub = replace_df[replace_df["subject"] == subject]
        if sub.empty:
            continue
        lines.append(f"### {subject}")
        for _, row in sub.sort_values(["reason_rank", "grade", "p_treated", "item"]).iterrows():
            lines.append(
                f"- grade {int(row['grade'])} `{row['item']}`: {row['item_label']} "
                f"(treated {fmt_pct(row['p_treated'])}, control {fmt_pct(row['p_control'])}; {row['recommendation_reason']})."
            )
        lines.append("")

    lines.append("## Priority 2: fix administration")
    lines.append("")
    admin_df = action_sheet[action_sheet["recommendation"] == "keep_but_fix_administration"].copy()
    for subject in ["Arabic", "French", "Maths"]:
        sub = admin_df[admin_df["subject"] == subject]
        if sub.empty:
            continue
        lines.append(f"### {subject}")
        for _, row in sub.sort_values(["grade", "response_rate_all", "item"]).iterrows():
            lines.append(
                f"- grade {int(row['grade'])} `{row['item']}`: {row['item_label']} "
                f"(response {fmt_pct(row['response_rate_all'])}, treated scored {fmt_pct(row['p_treated'])})."
            )
        lines.append("")

    lines.append("## Priority 3: soften slightly")
    lines.append("")
    soften_df = action_sheet[action_sheet["recommendation"] == "soften_slightly"].copy()
    if soften_df.empty:
        lines.append("- No items fell into this category under the revised rules.")
    else:
        for _, row in soften_df.sort_values(["subject", "grade", "p_treated"]).iterrows():
            lines.append(
                f"- {row['subject']} grade {int(row['grade'])} `{row['item']}`: {row['item_label']} "
                f"(treated {fmt_pct(row['p_treated'])}, control {fmt_pct(row['p_control'])})."
            )
    lines.append("")

    lines.append("## What should stay")
    lines.append("")
    lines.append(
        "- Some easy items should stay because they capture real treatment-related mastery gains."
    )
    lines.append(
        "- Some hard items should stay because they are useful stretch items and help measure learning among stronger students."
    )
    lines.append(
        "- Some easy items should also stay if they are easy mainly in pioneer schools rather than in both groups."
    )
    lines.append("")
    lines.append("Counts under the revised strategy:")
    for _, row in action_summary.sort_values("subject").iterrows():
        lines.append(
            f"- {row['subject']}: replace {int(row.get('replace', 0))}, "
            f"fix administration {int(row.get('keep_but_fix_administration', 0))}, "
            f"soften slightly {int(row.get('soften_slightly', 0))}, "
            f"treated-only ceiling review {int(row.get('review_treated_only_ceiling', 0))}, "
            f"keep stretch {int(row.get('keep_as_stretch', 0))}, "
            f"keep causal signal {int(row.get('keep_for_causal_signal', 0))}, "
            f"across {int(row['form_items_with_action'])} form-item occurrences needing action."
        )

    return "\n".join(lines)


def main() -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)

    (
        action_sheet,
        action_summary,
        reason_summary,
        form_summary,
        link_summary,
        link_grade_summary,
    ) = prepare_action_data()

    write_supporting_csvs(action_sheet)

    ministry_text = ministry_report(action_sheet, action_summary)
    (REPORT_DIR / "ministry_brief.md").write_text(ministry_text, encoding="utf-8")

    print(f"Wrote outputs to: {REPORT_DIR}")


if __name__ == "__main__":
    main()
