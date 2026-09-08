import os
from pathlib import Path

import pandas as pd


BASE_DIR = Path(os.getenv("PROJECT_ROOT", "/Users/mriduljoshi/Github/morocco-psp"))
OUTPUT_ROOT = Path(os.environ["PILOT_OUTPUT_ROOT"])
INPUT_PATH = OUTPUT_ROOT / "pilot_psychometrics" / "pilot_item_summary.csv"
OUTPUT_DIR = OUTPUT_ROOT / "pilot_item_actions"


def classify(row: pd.Series) -> tuple[str | None, str | None]:
    p = row["p_treated"]
    p_control = row["p_control"]
    rr = row["response_rate_all"]
    citc = row["corrected_item_total"]
    gap_tc = row["treated_minus_control"]
    obs_gap = row["observed_minus_scored_treated"]

    # Low completion can make solid open-response items look much harder than they are.
    if rr < 0.75 and obs_gap >= 0.20:
        return "keep_but_fix_administration", "low_coverage_missing_drives_difficulty"

    # Reverse-signed treatment gaps are a strong warning sign when coverage is acceptable.
    if gap_tc <= -0.10 and rr >= 0.75:
        return "replace", "treated_below_control_anomaly"

    # These items are probably overshooting the top end rather than stretching it.
    if p < 0.10 and rr >= 0.75:
        return "replace", "too_hard_replace"

    # Borderline items can be useful with a small softening if they still discriminate.
    if 0.10 <= p < 0.15 and rr >= 0.75:
        if citc >= 0.20 and gap_tc > -0.10:
            return "soften_slightly", "borderline_too_hard_but_discriminating"
        return "replace", "too_hard_or_weak_replace"

    # These are the items most likely to help recover effects in the upper tail.
    if 0.15 <= p < 0.40 and rr >= 0.75 and citc >= 0.20 and gap_tc > -0.10:
        return "keep_as_stretch", "useful_upper_tail_item"

    # Easy items can still be useful if they capture foundational mastery gains versus control.
    if p >= 0.85 and gap_tc >= 0.15 and rr >= 0.75 and citc >= 0.20:
        return "keep_for_causal_signal", "foundational_causal_signal_item"

    # Only call an item a true ceiling-replace when both treated and control are near the top.
    if p >= 0.90 and rr >= 0.90:
        if p_control >= 0.90:
            return "replace", "shared_ceiling_limited_incremental_value"
        return "review_treated_only_ceiling", "treated_only_ceiling_review"

    return None, None


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    items = pd.read_csv(INPUT_PATH)
    items["treated_minus_control"] = items["p_treated"] - items["p_control"]
    items["observed_minus_scored_treated"] = (
        items["observed_correct_treated"] - items["p_treated"]
    )

    recs = items.apply(classify, axis=1, result_type="expand")
    recs.columns = ["recommendation", "recommendation_reason"]
    items = pd.concat([items, recs], axis=1)

    action_sheet = items[items["recommendation"].notna()].copy()
    action_sheet = action_sheet.sort_values(
        ["subject", "recommendation", "grade", "p_treated", "response_rate_all", "item"]
    )

    action_sheet.to_csv(
        OUTPUT_DIR / "pilot_item_action_sheet.csv", index=False, encoding="utf-8"
    )

    summary = (
        action_sheet.groupby(["subject", "recommendation"])
        .size()
        .unstack(fill_value=0)
        .reset_index()
    )
    subject_totals = (
        items.groupby("subject").size().rename("total_form_items").reset_index()
    )
    subject_unique_totals = (
        items.groupby("subject")["item"].nunique().rename("total_unique_item_ids").reset_index()
    )
    action_totals = (
        action_sheet.groupby("subject")
        .size()
        .rename("form_items_with_action")
        .reset_index()
    )
    action_unique_totals = (
        action_sheet.groupby("subject")["item"]
        .nunique()
        .rename("unique_item_ids_with_action")
        .reset_index()
    )
    summary = (
        subject_totals.merge(summary, on="subject", how="left")
        .merge(subject_unique_totals, on="subject", how="left")
        .merge(action_totals, on="subject", how="left")
        .merge(action_unique_totals, on="subject", how="left")
    )
    summary = summary.fillna(0)
    summary["action_share"] = summary["form_items_with_action"] / summary["total_form_items"]
    summary.to_csv(
        OUTPUT_DIR / "pilot_item_action_summary_by_subject.csv",
        index=False,
        encoding="utf-8",
    )

    reason_summary = (
        action_sheet.groupby(["subject", "recommendation_reason"])
        .size()
        .reset_index(name="n_form_items")
        .sort_values(
            ["subject", "n_form_items", "recommendation_reason"],
            ascending=[True, False, True],
        )
    )
    reason_summary.to_csv(
        OUTPUT_DIR / "pilot_item_action_reason_summary.csv",
        index=False,
        encoding="utf-8",
    )

    md_lines: list[str] = []
    md_lines.append("# Pilot item action sheet")
    md_lines.append("")
    md_lines.append(
        "- `keep_as_stretch`: difficult but functioning items that help measure the upper tail."
    )
    md_lines.append(
        "- `keep_for_causal_signal`: easy items that still document meaningful treatment-induced mastery relative to control."
    )
    md_lines.append(
        "- `soften_slightly`: borderline-too-hard items that still discriminate and may be worth easing a little."
    )
    md_lines.append(
        "- `replace`: items that are too easy, too hard, or behaviorally anomalous and should not be kept unchanged."
    )
    md_lines.append(
        "- `review_treated_only_ceiling`: easy items that are near-ceiling in treated schools but not in control schools; review them for overall form balance rather than auto-replacing them."
    )
    md_lines.append(
        "- `keep_but_fix_administration`: items whose scored difficulty is being driven by low completion rather than weak observed performance."
    )
    md_lines.append("")
    md_lines.append("## Subject summary")
    md_lines.append("")

    for _, row in summary.sort_values("subject").iterrows():
        md_lines.append(
            f"- {row['subject']}: {int(row['form_items_with_action'])} form-item occurrences with action out of "
            f"{int(row['total_form_items'])}; keep stretch {int(row.get('keep_as_stretch', 0))}, "
            f"keep causal signal {int(row.get('keep_for_causal_signal', 0))}, "
            f"soften {int(row.get('soften_slightly', 0))}, replace {int(row.get('replace', 0))}, "
            f"treated-only ceiling review {int(row.get('review_treated_only_ceiling', 0))}, "
            f"fix administration {int(row.get('keep_but_fix_administration', 0))}. "
            f"Unique item IDs with action: {int(row['unique_item_ids_with_action'])}."
        )

    for subject in sorted(action_sheet["subject"].unique()):
        md_lines.append("")
        md_lines.append(f"## {subject}")
        md_lines.append("")
        subject_df = action_sheet[action_sheet["subject"] == subject]
        for rec_name in [
            "keep_as_stretch",
            "keep_for_causal_signal",
            "soften_slightly",
            "replace",
            "review_treated_only_ceiling",
            "keep_but_fix_administration",
        ]:
            rec_df = subject_df[subject_df["recommendation"] == rec_name]
            if rec_df.empty:
                continue
            md_lines.append(f"### {rec_name}")
            for _, item_row in rec_df.head(8).iterrows():
                md_lines.append(
                    f"- grade {int(item_row['grade'])} `{item_row['item']}`: "
                    f"treated p={item_row['p_treated']:.3f}, control p={item_row['p_control']:.3f}, "
                    f"response={item_row['response_rate_all']:.1%}, CITC={item_row['corrected_item_total']:.3f}. "
                    f"{item_row['item_label']}"
                )
            md_lines.append("")

    (OUTPUT_DIR / "pilot_item_action_summary.md").write_text(
        "\n".join(md_lines), encoding="utf-8"
    )

    print(f"Wrote outputs to: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
