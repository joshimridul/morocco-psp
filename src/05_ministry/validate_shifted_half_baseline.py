#!/usr/bin/env python3
"""Validate the corrected shifted half-length baseline selection map."""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import zipfile
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "00_inventory"))
from build_y3_registry import read_simple_paths  # noqa: E402
from path_guard import assert_output_path  # noqa: E402


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    paths = read_simple_paths(args.config.resolve())
    work = paths["work_root"]
    roots = [paths["y1_root"], paths["y2_root"], paths["y3_root"]]
    out = work / "outputs/y3_ministry/05_short_form/shifted_baseline"

    shift = read_rows(work / "outputs/y3_ministry/03_forms/y3_one_grade_shift_map.csv")
    candidates = read_rows(work / "derived/y3_ministry/y3_anchor_candidate_evidence.csv")
    historical = read_rows(work / "private_manifests/historical_bank_candidate_evidence.csv")
    plan = read_rows(out / "shifted_half_baseline_item_plan.csv")
    log = read_rows(out / "shifted_half_baseline_selection_log.csv")
    anchors = read_rows(out / "shifted_half_baseline_anchor_audit.csv")
    workbook = out / "Morocco_Baseline_Half_Length_Draft_Selection_Map.xlsx"
    failures: list[str] = []

    def check(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    pool_counts = Counter((row["subject"], int(row["target_baseline_grade"])) for row in shift)
    selected_counts = Counter((row["subject"], int(row["baseline_grade"])) for row in plan)
    expected = {key: math.ceil(value * 0.5) for key, value in pool_counts.items()}
    check(len(shift) == 652, f"Expected 652 shifted pool rows, found {len(shift)}")
    check(len(plan) == 332, f"Expected 332 selected rows, found {len(plan)}")
    check(dict(selected_counts) == expected, f"Selected counts do not equal per-form ceilings of half: {dict(selected_counts)}")

    plan_keys = [(row["subject"], int(row["baseline_grade"]), row["item_id"]) for row in plan]
    check(len(plan_keys) == len(set(plan_keys)), "Duplicate subject-baseline-grade-item rows")
    for field in ("item_or_summary", "content_domain", "cognitive_domain", "source", "selection_reason"):
        check(all(row[field].strip() for row in plan), f"Blank selected field: {field}")

    current_pool = {
        (row["subject"], int(row["target_baseline_grade"]), row["source_wave"], int(row["source_administered_grade"]), row["item_id"])
        for row in shift
    }
    misplaced = []
    missing_current = []
    for row in plan:
        grade = int(row["baseline_grade"])
        if row["source_wave"] == "historical":
            continue
        expected_wave = "baseline" if grade == 1 else "endline"
        expected_source_grade = 1 if grade == 1 else grade - 1
        if row["source_wave"] != expected_wave or int(row["source_grade"]) != expected_source_grade:
            misplaced.append((row["subject"], grade, row["item_id"], row["source_wave"], row["source_grade"]))
        key = (row["subject"], grade, row["source_wave"], int(row["source_grade"]), row["item_id"])
        if key not in current_pool:
            missing_current.append(key)
    check(not misplaced, f"Rows violate grade-shift rule: {misplaced[:10]}")
    check(not missing_current, f"Current rows absent from official shifted pool: {missing_current[:10]}")

    anchor_plan = [row for row in plan if row["selected_anchor"] == "1"]
    anchor_counts = Counter(row["anchor_link"] for row in anchor_plan)
    check(len(anchor_plan) == 90, f"Expected 90 anchor placements, found {len(anchor_plan)}")
    check(len(anchor_counts) == 18, f"Expected 18 required baseline links, found {len(anchor_counts)}")
    check(all(value == 5 for value in anchor_counts.values()), "Every required baseline link must have exactly five anchors")
    check(len(anchors) == 90, f"Expected 90 anchor audit rows, found {len(anchors)}")

    evidence_exact = {
        (row["link_id"], row["item_id"])
        for row in candidates
        if row["prompt_hash_consistent"] == "1"
        and row["anchor_candidate_tier"] in {"Tier A core candidate", "Tier B expanded candidate"}
    }
    bad_current_anchors = [
        (row["anchor_link"], row["item_id"])
        for row in anchor_plan
        if row["source_wave"] != "historical"
        and (row["anchor_link"], row["item_id"]) not in evidence_exact
    ]
    check(not bad_current_anchors, f"Current anchors lack exact prompt-hash-consistent evidence: {bad_current_anchors[:10]}")
    historical_status_failures = [
        (row["anchor_link"], row["item_id"])
        for row in anchor_plan
        if row["source_wave"] == "historical"
        and "historical source version" not in row["anchor_version_status"].casefold()
    ]
    check(not historical_status_failures, f"Historical anchors lack explicit source-version status: {historical_status_failures[:10]}")

    selected_log = [row for row in log if row["selected"] == "YES"]
    selected_historical_placements = [row for row in plan if row["source_wave"] == "historical"]
    selected_historical_ids = {(row["subject"], row["item_id"]) for row in selected_historical_placements}
    expected_log_n = len(shift) + len(historical) + len(selected_historical_placements) - len(selected_historical_ids)
    check(len(log) == expected_log_n, f"Expected {expected_log_n} decision-log rows, found {len(log)}")
    check(len(selected_log) == 332, f"Expected 332 selected log rows, found {len(selected_log)}")
    log_keys = {
        (row["subject"], int(row["baseline_grade"]), row["item_id"], row["source_wave"])
        for row in selected_log
    }
    plan_log_keys = {
        (row["subject"], int(row["baseline_grade"]), row["item_id"], row["source_wave"])
        for row in plan
    }
    check(log_keys == plan_log_keys, "Selected log rows do not exactly match the selection map")
    check(all(row["decision_reason"].strip() for row in log), "Blank decision reason in log")
    check(all(row["source_reference"].strip() for row in log), "Blank source reference in log")

    available_tails: Counter[tuple[str, int, str]] = Counter()
    for row in shift:
        pct = float(row["source_pct_correct"]) if row["source_pct_correct"] else None
        role = "easy" if pct is not None and pct >= 70 else "hard" if pct is not None and pct <= 35 else "middle"
        available_tails[(row["subject"], int(row["target_baseline_grade"]), role)] += 1
    selected_tails = Counter((row["subject"], int(row["baseline_grade"]), row["tail_role"]) for row in plan)
    tail_shortfalls = []
    for subject, grade in pool_counts:
        for role in ("easy", "hard"):
            required = min(2, available_tails[(subject, grade, role)])
            if selected_tails[(subject, grade, role)] < required:
                tail_shortfalls.append((subject, grade, role, required, selected_tails[(subject, grade, role)]))
    check(not tail_shortfalls, f"Avoidable tail shortfalls: {tail_shortfalls}")

    with zipfile.ZipFile(workbook) as archive:
        root = ElementTree.fromstring(archive.read("xl/workbook.xml"))
        namespace = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
        sheets = [node.attrib["name"] for node in root.findall("m:sheets/m:sheet", namespace)]
    check(sheets == ["Baseline Item Map"], f"Unexpected workbook sheets: {sheets}")

    result = {
        "status": "PASS" if not failures else "FAIL",
        "official_shifted_pool_rows": len(shift),
        "selected_rows": len(plan),
        "selected_share_pct": round(100 * len(plan) / len(shift), 1),
        "required_anchor_links": len(anchor_counts),
        "anchors_per_link": sorted(set(anchor_counts.values())),
        "current_exact_evidence_anchor_rows": sum(row["source_wave"] != "historical" for row in anchor_plan),
        "historical_exact_source_anchor_rows_pending_full_fingerprint": sum(row["source_wave"] == "historical" for row in anchor_plan),
        "selection_log_rows": len(log),
        "selected_log_rows": len(selected_log),
        "unavoidable_tail_gaps": [
            {"subject": subject, "grade": grade, "tail": role, "available": available_tails[(subject, grade, role)]}
            for subject, grade in pool_counts for role in ("easy", "hard")
            if available_tails[(subject, grade, role)] < 2
        ],
        "workbook_sheets": sheets,
        "send_status": "Draft selection map only; not a final assembled instrument until source-language keys and shared-stimulus/rubric bundles are confirmed.",
        "failures": failures,
    }
    output = assert_output_path(out / "shifted_half_baseline_validation.json", work, roots)
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
