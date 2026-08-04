import math
import os
import re
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd


PROJECT_ROOT = Path(os.getenv("PROJECT_ROOT", "/Users/mriduljoshi/Github/morocco-psp"))
DATA_PATH = Path(
    os.getenv(
        "PILOT_DATA_PATH",
        "/Users/mriduljoshi/Dropbox/DID - Morocco Pioneer Schools Year 3/4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta",
    )
)

PSYCH_DIR = PROJECT_ROOT / "outputs" / "pilot_psychometrics"
ACTION_DIR = PROJECT_ROOT / "outputs" / "pilot_item_actions"
LINK_DIR = PROJECT_ROOT / "outputs" / "pilot_vertical_linking"
REPORT_DIR = PROJECT_ROOT / "outputs" / "pilot_reports"

TOL = 1e-7


def to_numeric_frame(df: pd.DataFrame, cols: list[str]) -> pd.DataFrame:
    return df[cols].apply(pd.to_numeric, errors="coerce").astype("float64")


def is_binary_series(series: pd.Series) -> bool:
    vals = pd.to_numeric(series, errors="coerce").dropna().unique()
    return len(vals) > 0 and set(vals).issubset({0, 1})


def safe_corr(x: np.ndarray, y: np.ndarray) -> float:
    if len(x) <= 1 or len(y) <= 1:
        return np.nan
    if np.nanstd(x, ddof=1) == 0 or np.nanstd(y, ddof=1) == 0:
        return np.nan
    return float(np.corrcoef(x, y)[0, 1])


def classify_action(row: pd.Series) -> tuple[str | None, str | None]:
    p = row["p_treated"]
    p_control = row["p_control"]
    rr = row["response_rate_all"]
    citc = row["corrected_item_total"]
    gap_tc = row["p_treated"] - row["p_control"]
    obs_gap = row["observed_correct_treated"] - row["p_treated"]

    if rr < 0.75 and obs_gap >= 0.20:
        return "keep_but_fix_administration", "low_coverage_missing_drives_difficulty"
    if gap_tc <= -0.10 and rr >= 0.75:
        return "replace", "treated_below_control_anomaly"
    if p < 0.10 and rr >= 0.75:
        return "replace", "too_hard_replace"
    if 0.10 <= p < 0.15 and rr >= 0.75:
        if citc >= 0.20 and gap_tc > -0.10:
            return "soften_slightly", "borderline_too_hard_but_discriminating"
        return "replace", "too_hard_or_weak_replace"
    if 0.15 <= p < 0.40 and rr >= 0.75 and citc >= 0.20 and gap_tc > -0.10:
        return "keep_as_stretch", "useful_upper_tail_item"
    if p >= 0.85 and gap_tc >= 0.15 and rr >= 0.75 and citc >= 0.20:
        return "keep_for_causal_signal", "foundational_causal_signal_item"
    if p >= 0.90 and rr >= 0.90:
        if p_control >= 0.90:
            return "replace", "shared_ceiling_limited_incremental_value"
        return "review_treated_only_ceiling", "treated_only_ceiling_review"
    return None, None


def compare_numeric(
    name: str,
    actual: pd.DataFrame,
    expected: pd.DataFrame,
    keys: list[str],
    numeric_cols: list[str],
    details: list[dict],
    tolerance: float = TOL,
) -> int:
    merged = actual.merge(expected, on=keys, how="outer", suffixes=("_actual", "_expected"), indicator=True)
    problems = 0

    for _, row in merged[merged["_merge"] != "both"].iterrows():
        problems += 1
        details.append(
            {
                "check": name,
                "status": "mismatch",
                "key": "|".join(str(row.get(k, "")) for k in keys),
                "field": "_merge",
                "actual": row["_merge"],
                "expected": "both",
                "difference": "",
            }
        )

    both = merged[merged["_merge"] == "both"].copy()
    for col in numeric_cols:
        a = pd.to_numeric(both[f"{col}_actual"], errors="coerce")
        e = pd.to_numeric(both[f"{col}_expected"], errors="coerce")
        diff = (a - e).abs()
        mismatch = diff > tolerance
        mismatch = mismatch.fillna(False)
        mismatch = mismatch | (a.isna() != e.isna())
        for idx in both.index[mismatch]:
            problems += 1
            details.append(
                {
                    "check": name,
                    "status": "mismatch",
                    "key": "|".join(str(both.loc[idx, k]) for k in keys),
                    "field": col,
                    "actual": both.loc[idx, f"{col}_actual"],
                    "expected": both.loc[idx, f"{col}_expected"],
                    "difference": diff.loc[idx] if not math.isnan(diff.loc[idx]) else "",
                }
            )
    return problems


def compare_exact(
    name: str,
    actual: pd.DataFrame,
    expected: pd.DataFrame,
    keys: list[str],
    cols: list[str],
    details: list[dict],
) -> int:
    merged = actual.merge(expected, on=keys, how="outer", suffixes=("_actual", "_expected"), indicator=True)
    problems = 0

    for _, row in merged[merged["_merge"] != "both"].iterrows():
        problems += 1
        details.append(
            {
                "check": name,
                "status": "mismatch",
                "key": "|".join(str(row.get(k, "")) for k in keys),
                "field": "_merge",
                "actual": row["_merge"],
                "expected": "both",
                "difference": "",
            }
        )

    both = merged[merged["_merge"] == "both"].copy()
    for col in cols:
        a = both[f"{col}_actual"].fillna("")
        e = both[f"{col}_expected"].fillna("")
        mismatch = a.astype(str) != e.astype(str)
        for idx in both.index[mismatch]:
            problems += 1
            details.append(
                {
                    "check": name,
                    "status": "mismatch",
                    "key": "|".join(str(both.loc[idx, k]) for k in keys),
                    "field": col,
                    "actual": both.loc[idx, f"{col}_actual"],
                    "expected": both.loc[idx, f"{col}_expected"],
                    "difference": "",
                }
            )
    return problems


def build_independent_outputs() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, dict]:
    raw_num = pd.read_stata(DATA_PATH, convert_categoricals=False)
    raw_lab = pd.read_stata(DATA_PATH, convert_categoricals=True)

    item_like = [c for c in raw_num.columns if re.match(r"^[maf][0-9]", c)]
    binary_items = [c for c in item_like if is_binary_series(raw_num[c])]
    nonbinary_items = sorted(set(item_like) - set(binary_items))

    item_obs = to_numeric_frame(raw_num, binary_items)
    context = pd.DataFrame(
        {
            "row_id": np.arange(1, len(raw_num) + 1),
            "id_student_panel": raw_num["id_student_panel"].astype(str),
            "subject": raw_lab["subject"].astype(str),
            "grade": pd.to_numeric(raw_num["grade"], errors="coerce").astype("Int64"),
            "treated": pd.to_numeric(raw_num["treated"], errors="coerce"),
            "duration_num": pd.to_numeric(raw_num["duration"].astype(str), errors="coerce").fillna(-np.inf),
        }
    )
    context["n_binary_nonmissing"] = item_obs.notna().sum(axis=1)
    context["binary_score_observed"] = item_obs.fillna(0).sum(axis=1)

    analysis = pd.concat([context, item_obs], axis=1)
    analysis = analysis.sort_values(
        [
            "id_student_panel",
            "subject",
            "grade",
            "n_binary_nonmissing",
            "binary_score_observed",
            "duration_num",
            "row_id",
        ],
        ascending=[True, True, True, False, False, False, True],
    )
    dedup = analysis.drop_duplicates(["id_student_panel", "subject", "grade"], keep="first").copy()

    form_rows = []
    item_rows = []
    for subject in sorted(dedup["subject"].dropna().unique()):
        for grade in sorted(dedup["grade"].dropna().unique()):
            form = dedup[(dedup["subject"] == subject) & (dedup["grade"] == grade)]
            if form.empty:
                continue
            eligible = [c for c in binary_items if form[c].notna().any()]
            if not eligible:
                continue
            x_obs = form[eligible].apply(pd.to_numeric, errors="coerce")
            x = x_obs.fillna(0)
            treated_mask = form["treated"] == 1
            control_mask = form["treated"] == 0

            total_scores = x.sum(axis=1)
            response_rate_all = x_obs.notna().mean(axis=0)
            p_all = x.mean(axis=0)
            p_treated = x.loc[treated_mask, :].mean(axis=0)
            p_control = x.loc[control_mask, :].mean(axis=0)
            observed_all = x_obs.mean(axis=0, skipna=True)
            observed_treated = x_obs.loc[treated_mask, :].mean(axis=0, skipna=True)
            observed_control = x_obs.loc[control_mask, :].mean(axis=0, skipna=True)
            response_treated = x_obs.loc[treated_mask, :].notna().mean(axis=0)
            response_control = x_obs.loc[control_mask, :].notna().mean(axis=0)

            form_rows.append(
                {
                    "subject": subject,
                    "grade": int(grade),
                    "n_students": len(form),
                    "n_treated": int(treated_mask.sum()),
                    "n_control": int(control_mask.sum()),
                    "n_binary_items": len(eligible),
                    "avg_response_rate": float(response_rate_all.mean()),
                    "mean_pct_correct_all": float((total_scores / len(eligible)).mean()),
                    "mean_pct_correct_treated": float((total_scores[treated_mask] / len(eligible)).mean()),
                    "mean_pct_correct_control": float((total_scores[control_mask] / len(eligible)).mean()),
                    "ctt_very_easy_treated": int((p_treated >= 0.90).sum()),
                    "ctt_very_hard_treated": int((p_treated <= 0.10).sum()),
                    "ctt_very_easy_all": int((p_all >= 0.90).sum()),
                    "ctt_very_hard_all": int((p_all <= 0.10).sum()),
                }
            )

            for item in eligible:
                item_vector = x[item].to_numpy(dtype=float)
                rest = total_scores.to_numpy(dtype=float) - item_vector
                item_rows.append(
                    {
                        "subject": subject,
                        "grade": int(grade),
                        "item": item,
                        "p_all": float(p_all[item]),
                        "p_treated": float(p_treated[item]),
                        "p_control": float(p_control[item]),
                        "observed_correct_all": float(observed_all[item]) if pd.notna(observed_all[item]) else np.nan,
                        "observed_correct_treated": float(observed_treated[item]) if pd.notna(observed_treated[item]) else np.nan,
                        "observed_correct_control": float(observed_control[item]) if pd.notna(observed_control[item]) else np.nan,
                        "response_rate_all": float(response_rate_all[item]),
                        "response_rate_treated": float(response_treated[item]),
                        "response_rate_control": float(response_control[item]),
                        "missing_rate_all": float(1 - response_rate_all[item]),
                        "corrected_item_total": safe_corr(item_vector, rest),
                        "ctt_flag_treated": "very_easy"
                        if p_treated[item] >= 0.90
                        else "very_hard"
                        if p_treated[item] <= 0.10
                        else "in_range",
                        "ctt_flag_all": "very_easy"
                        if p_all[item] >= 0.90
                        else "very_hard"
                        if p_all[item] <= 0.10
                        else "in_range",
                    }
                )

    form_summary = pd.DataFrame(form_rows)
    item_summary = pd.DataFrame(item_rows)

    recs = item_summary.apply(classify_action, axis=1, result_type="expand")
    recs.columns = ["recommendation", "recommendation_reason"]
    action = pd.concat([item_summary, recs], axis=1)
    action = action[action["recommendation"].notna()].copy()
    action = action.sort_values(["subject", "recommendation", "grade", "p_treated", "response_rate_all", "item"])

    anchor_rows = []
    for subject in sorted(item_summary["subject"].unique()):
        subj_items = item_summary[item_summary["subject"] == subject]
        for g1, g2 in zip(range(1, 6), range(2, 7)):
            left = subj_items[subj_items["grade"] == g1]
            right = subj_items[subj_items["grade"] == g2]
            shared = left[["item", "p_treated", "response_rate_all", "corrected_item_total"]].merge(
                right[["item", "p_treated", "response_rate_all", "corrected_item_total"]],
                on="item",
                suffixes=("_g1", "_g2"),
            )
            usable = (
                (shared["response_rate_all_g1"] >= 0.75)
                & (shared["response_rate_all_g2"] >= 0.75)
                & (shared["p_treated_g1"].between(0.20, 0.80, inclusive="both"))
                & (shared["p_treated_g2"].between(0.20, 0.80, inclusive="both"))
                & (shared["corrected_item_total_g1"] >= 0.15)
                & (shared["corrected_item_total_g2"] >= 0.15)
            )
            swing = shared["p_treated_g2"] - shared["p_treated_g1"]
            final = usable & (swing > -0.10)
            anchor_rows.append(
                {
                    "subject": subject,
                    "grade_pair": f"g{g1}-g{g2}",
                    "shared_items": int(len(shared)),
                    "usable_anchor_candidates": int(usable.sum()),
                    "final_anchors": int(final.sum()),
                    "chain_edge": bool(final.sum() >= 2),
                }
            )

    anchor_pair = pd.DataFrame(anchor_rows)

    metadata = {
        "raw_rows": len(raw_num),
        "dedup_rows": len(dedup),
        "item_like_count": len(item_like),
        "binary_item_count": len(binary_items),
        "nonbinary_item_count": len(nonbinary_items),
        "nonbinary_items": ", ".join(nonbinary_items),
    }
    return form_summary, item_summary, action, anchor_pair, metadata


def main() -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    details: list[dict] = []
    summary_rows: list[dict] = []

    irt_refit_path = REPORT_DIR / "replication_irt_refit_summary.csv"
    irt_script = PROJECT_ROOT / "analysis" / "pilot_irt_replication_check.R"
    irt_run = subprocess.run(
        ["Rscript", str(irt_script)],
        cwd=PROJECT_ROOT,
        env={**os.environ, "PROJECT_ROOT": str(PROJECT_ROOT), "PILOT_DATA_PATH": str(DATA_PATH)},
        text=True,
        capture_output=True,
    )
    if irt_run.returncode != 0:
        details.append(
            {
                "check": "irt_refit",
                "status": "mismatch",
                "key": "Rscript",
                "field": "returncode",
                "actual": irt_run.returncode,
                "expected": 0,
                "difference": irt_run.stderr[-500:],
            }
        )
        summary_rows.append({"check": "irt_refit", "status": "fail", "problems": 1})

    form_ind, item_ind, action_ind, anchor_ind, metadata = build_independent_outputs()

    form_out = pd.read_csv(PSYCH_DIR / "pilot_form_summary.csv")
    item_out = pd.read_csv(PSYCH_DIR / "pilot_item_summary.csv")
    action_out = pd.read_csv(ACTION_DIR / "pilot_item_action_sheet.csv")
    action_subject_out = pd.read_csv(ACTION_DIR / "pilot_item_action_summary_by_subject.csv")
    action_grade_out = pd.read_csv(REPORT_DIR / "action_counts_by_subject_grade.csv")
    anchor_out = pd.read_csv(LINK_DIR / "pilot_vertical_anchor_pair_summary.csv")

    metadata_expected = {
        "raw_rows": 3523,
        "dedup_rows": int(form_out["n_students"].sum()),
        "binary_item_count": int(item_out["item"].nunique()),
        "nonbinary_item_count": len(pd.read_csv(PSYCH_DIR / "pilot_nonbinary_items_excluded.csv")),
    }
    for key, expected in metadata_expected.items():
        actual = metadata[key]
        status = "pass" if actual == expected else "fail"
        summary_rows.append({"check": key, "status": status, "problems": 0 if status == "pass" else 1})
        if status != "pass":
            details.append(
                {
                    "check": key,
                    "status": "mismatch",
                    "key": key,
                    "field": key,
                    "actual": actual,
                    "expected": expected,
                    "difference": actual - expected,
                }
            )

    form_cols = [
        "n_students",
        "n_treated",
        "n_control",
        "n_binary_items",
        "avg_response_rate",
        "mean_pct_correct_all",
        "mean_pct_correct_treated",
        "mean_pct_correct_control",
        "ctt_very_easy_treated",
        "ctt_very_hard_treated",
        "ctt_very_easy_all",
        "ctt_very_hard_all",
    ]
    problems = compare_numeric("form_summary", form_ind, form_out, ["subject", "grade"], form_cols, details)
    summary_rows.append({"check": "form_summary", "status": "pass" if problems == 0 else "fail", "problems": problems})

    item_cols = [
        "p_all",
        "p_treated",
        "p_control",
        "observed_correct_all",
        "observed_correct_treated",
        "observed_correct_control",
        "response_rate_all",
        "response_rate_treated",
        "response_rate_control",
        "missing_rate_all",
        "corrected_item_total",
    ]
    problems = compare_numeric("item_summary_numeric", item_ind, item_out, ["subject", "grade", "item"], item_cols, details)
    problems += compare_exact(
        "item_summary_flags",
        item_ind,
        item_out,
        ["subject", "grade", "item"],
        ["ctt_flag_treated", "ctt_flag_all"],
        details,
    )
    summary_rows.append(
        {"check": "item_summary", "status": "pass" if problems == 0 else "fail", "problems": problems}
    )

    action_compare_actual = action_ind[["subject", "grade", "item", "recommendation", "recommendation_reason"]]
    action_compare_expected = action_out[["subject", "grade", "item", "recommendation", "recommendation_reason"]]
    problems = compare_exact(
        "action_classification",
        action_compare_actual,
        action_compare_expected,
        ["subject", "grade", "item"],
        ["recommendation", "recommendation_reason"],
        details,
    )
    summary_rows.append(
        {"check": "action_classification", "status": "pass" if problems == 0 else "fail", "problems": problems}
    )

    action_subject_ind = (
        action_ind.groupby(["subject", "recommendation"]).size().unstack(fill_value=0).reset_index()
    )
    subject_totals = item_ind.groupby("subject").size().rename("total_form_items").reset_index()
    subject_unique = item_ind.groupby("subject")["item"].nunique().rename("total_unique_item_ids").reset_index()
    action_totals = action_ind.groupby("subject").size().rename("form_items_with_action").reset_index()
    action_unique = action_ind.groupby("subject")["item"].nunique().rename("unique_item_ids_with_action").reset_index()
    action_subject_ind = (
        subject_totals.merge(action_subject_ind, on="subject", how="left")
        .merge(subject_unique, on="subject", how="left")
        .merge(action_totals, on="subject", how="left")
        .merge(action_unique, on="subject", how="left")
        .fillna(0)
    )
    action_subject_ind["action_share"] = (
        action_subject_ind["form_items_with_action"] / action_subject_ind["total_form_items"]
    )
    subject_cols = [
        "total_form_items",
        "keep_as_stretch",
        "keep_but_fix_administration",
        "keep_for_causal_signal",
        "replace",
        "review_treated_only_ceiling",
        "soften_slightly",
        "total_unique_item_ids",
        "form_items_with_action",
        "unique_item_ids_with_action",
        "action_share",
    ]
    problems = compare_numeric(
        "action_subject_summary",
        action_subject_ind,
        action_subject_out,
        ["subject"],
        subject_cols,
        details,
    )
    summary_rows.append(
        {"check": "action_subject_summary", "status": "pass" if problems == 0 else "fail", "problems": problems}
    )

    action_grade_ind = (
        action_ind.groupby(["subject", "grade", "recommendation"]).size().unstack(fill_value=0).reset_index()
    )
    all_forms = item_ind[["subject", "grade"]].drop_duplicates()
    action_grade_ind = all_forms.merge(action_grade_ind, on=["subject", "grade"], how="left").fillna(0)
    grade_cols = [
        "keep_as_stretch",
        "keep_but_fix_administration",
        "keep_for_causal_signal",
        "replace",
        "review_treated_only_ceiling",
        "soften_slightly",
    ]
    for col in grade_cols:
        if col not in action_grade_ind:
            action_grade_ind[col] = 0
    problems = compare_numeric(
        "action_grade_summary",
        action_grade_ind,
        action_grade_out,
        ["subject", "grade"],
        grade_cols,
        details,
    )
    summary_rows.append(
        {"check": "action_grade_summary", "status": "pass" if problems == 0 else "fail", "problems": problems}
    )

    anchor_cols = ["shared_items", "usable_anchor_candidates", "final_anchors"]
    problems = compare_numeric(
        "anchor_pair_summary",
        anchor_ind,
        anchor_out,
        ["subject", "grade_pair"],
        anchor_cols,
        details,
    )
    problems += compare_exact(
        "anchor_pair_chain_edge",
        anchor_ind,
        anchor_out,
        ["subject", "grade_pair"],
        ["chain_edge"],
        details,
    )
    summary_rows.append(
        {"check": "anchor_pair_summary", "status": "pass" if problems == 0 else "fail", "problems": problems}
    )

    if irt_refit_path.exists() and not any(row["check"] == "irt_refit" for row in summary_rows):
        irt_refit = pd.read_csv(irt_refit_path)
        irt_expected = form_out[
            [
                "subject",
                "grade",
                "irt_model_used",
                "irt_items_fit",
                "irt_constant_items_excluded",
                "irt_converged",
                "irt_fit_reason",
            ]
        ].rename(
            columns={
                "irt_model_used": "irt_model_used_refit",
                "irt_items_fit": "irt_items_fit_refit",
                "irt_constant_items_excluded": "irt_constant_items_excluded_refit",
                "irt_converged": "irt_converged_refit",
                "irt_fit_reason": "irt_fit_reason_refit",
            }
        )
        problems = compare_exact(
            "irt_refit_exact",
            irt_refit,
            irt_expected,
            ["subject", "grade"],
            [
                "irt_model_used_refit",
                "irt_items_fit_refit",
                "irt_constant_items_excluded_refit",
                "irt_converged_refit",
                "irt_fit_reason_refit",
            ],
            details,
        )
        summary_rows.append({"check": "irt_refit", "status": "pass" if problems == 0 else "fail", "problems": problems})

    team_report = REPORT_DIR / "team_full_report.md"
    obsolete_paths = [
        PROJECT_ROOT / ".DS_Store",
        REPORT_DIR / "internal_research_report.md",
        REPORT_DIR / "ministry_brief.md",
        REPORT_DIR / "ministry_priority_action_queue.csv",
        ACTION_DIR / "requested_item_strategies.csv",
    ]
    readme = PROJECT_ROOT / "analysis" / "README_pilot_pipeline.md"
    reporting = PROJECT_ROOT / "analysis" / "pilot_reporting.py"
    doc_problems = 0
    if not team_report.exists():
        doc_problems += 1
        details.append({"check": "canonical_report", "status": "mismatch", "key": "team_full_report.md", "field": "exists", "actual": False, "expected": True, "difference": ""})
    for obsolete_path in obsolete_paths:
        if obsolete_path.exists():
            doc_problems += 1
            details.append({"check": "canonical_report", "status": "mismatch", "key": str(obsolete_path), "field": "obsolete_file_exists", "actual": True, "expected": False, "difference": ""})
    for path in [readme, reporting]:
        text = path.read_text(encoding="utf-8")
        if "internal_research_report.md" in text:
            doc_problems += 1
            details.append({"check": "canonical_report", "status": "mismatch", "key": str(path), "field": "stale_reference", "actual": "internal_research_report.md", "expected": "", "difference": ""})
        if "ministry_brief.md" in text or "ministry_priority_action_queue.csv" in text:
            doc_problems += 1
            details.append({"check": "canonical_report", "status": "mismatch", "key": str(path), "field": "stale_ministry_reference", "actual": "ministry output reference", "expected": "", "difference": ""})
    summary_rows.append(
        {"check": "canonical_report_hygiene", "status": "pass" if doc_problems == 0 else "fail", "problems": doc_problems}
    )

    details_df = pd.DataFrame(details)
    if details_df.empty:
        details_df = pd.DataFrame(columns=["check", "status", "key", "field", "actual", "expected", "difference"])
    details_path = REPORT_DIR / "replication_check_details.csv"
    details_df.to_csv(details_path, index=False, encoding="utf-8")

    summary_df = pd.DataFrame(summary_rows)
    status = "PASS" if (summary_df["status"] == "fail").sum() == 0 else "FAIL"
    report_path = REPORT_DIR / "replication_check_report.md"

    lines = [
        "# Independent Replication Check",
        "",
        f"- Overall status: `{status}`",
        f"- Raw rows independently read: `{metadata['raw_rows']}`",
        f"- Deduplicated rows independently reconstructed: `{metadata['dedup_rows']}`",
        f"- Binary item fields independently identified: `{metadata['binary_item_count']}`",
        f"- Non-binary item fields independently identified: `{metadata['nonbinary_item_count']}`",
        f"- Non-binary fields: `{metadata['nonbinary_items']}`",
        "",
        "## What Was Replicated Independently",
        "",
        "- raw row count, binary item detection, and non-binary item exclusion",
        "- duplicate resolution using the same student-subject-grade key and independent sorting logic",
        "- form-level sample sizes, treated/control counts, item counts, response rates, and mean scores",
        "- item-level scored difficulty, observed-only correctness, response rates, missing rates, and corrected item-total correlations",
        "- item action classification under the revised dual-objective rules",
        "- subject and subject-grade action counts",
        "- adjacent-grade anchor-pair counts, usable-anchor counts, final-anchor counts, and chain-edge flags",
        "- within-form IRT model fallback decisions by refitting 2PL and 1PL models",
        "- canonical report hygiene after retiring obsolete internal/ministry artifacts",
        "",
        "## Check Summary",
        "",
        "| Check | Status | Problems |",
        "| --- | --- | ---: |",
    ]
    for _, row in summary_df.iterrows():
        lines.append(f"| `{row['check']}` | `{row['status']}` | {int(row['problems'])} |")

    lines.extend(["", "## Errors Found And Fixes", ""])
    if status == "PASS":
        lines.extend(
            [
            "- No analytic discrepancies were found in the replicated calculations or IRT fallback decisions.",
                "- Cleanup issues addressed: the old shorter `internal_research_report.md`, the ministry brief/queue files, the one-off requested-item lookup, and `.DS_Store` were obsolete. I removed those files, stopped the pipeline from regenerating the ministry outputs, and updated the pipeline README to list only the current internal report outputs.",
            ]
        )
    else:
        lines.extend(
            [
                "- Replication found mismatches. See `replication_check_details.csv` for row-level details.",
                "- I did not auto-fix analytic mismatches because those should be reviewed against the source data before changing the pipeline.",
            ]
        )

    lines.extend(
        [
            "",
            "## Notes",
            "",
            "- This replication intentionally recalculates the core CTT and action logic from the raw Stata file instead of trusting the existing generated CSVs.",
            "- The IRT check refits each form independently and compares the resulting `2PL` versus `1PL` fallback decision to the main output.",
            f"- IRT refit details are saved in [replication_irt_refit_summary.csv]({REPORT_DIR / 'replication_irt_refit_summary.csv'}).",
            f"- Row-level replication details are saved in [replication_check_details.csv]({details_path}).",
        ]
    )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Replication status: {status}")
    print(f"Wrote {report_path}")
    print(f"Wrote {details_path}")


if __name__ == "__main__":
    main()
