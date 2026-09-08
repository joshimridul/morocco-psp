import os
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(os.getenv("PROJECT_ROOT", "/Users/mriduljoshi/Github/morocco-psp"))
OUTPUT_ROOT = Path(os.environ["PILOT_OUTPUT_ROOT"])
PSYCH_DIR = OUTPUT_ROOT / "pilot_psychometrics"
ACTION_DIR = OUTPUT_ROOT / "pilot_item_actions"
REPORT_DIR = OUTPUT_ROOT / "pilot_reports"

ACTION_COLUMNS = [
    "keep_as_stretch",
    "keep_but_fix_administration",
    "keep_for_causal_signal",
    "replace",
    "review_treated_only_ceiling",
    "soften_slightly",
]


def main() -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)

    item_summary = pd.read_csv(PSYCH_DIR / "pilot_item_summary.csv")
    action_sheet = pd.read_csv(ACTION_DIR / "pilot_item_action_sheet.csv")

    forms = item_summary[["subject", "grade"]].drop_duplicates()
    action_counts = (
        action_sheet.groupby(["subject", "grade", "recommendation"])
        .size()
        .unstack(fill_value=0)
        .reset_index()
    )
    action_counts = forms.merge(action_counts, on=["subject", "grade"], how="left").fillna(0)

    for col in ACTION_COLUMNS:
        if col not in action_counts.columns:
            action_counts[col] = 0

    action_counts = action_counts[["subject", "grade", *ACTION_COLUMNS]].sort_values(
        ["subject", "grade"]
    )
    action_counts.to_csv(REPORT_DIR / "action_counts_by_subject_grade.csv", index=False)

    print(f"Wrote supporting outputs to: {REPORT_DIR}")


if __name__ == "__main__":
    main()
