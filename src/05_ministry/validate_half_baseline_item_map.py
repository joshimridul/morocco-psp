#!/usr/bin/env python3
"""Deterministically reconcile the half-length baseline deliverables."""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import zipfile
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "00_inventory"))
from build_y3_registry import read_simple_paths  # noqa: E402
from path_guard import assert_output_path  # noqa: E402


EXPECTED_COUNTS = {
    ("Arabic", 1): 26, ("Arabic", 2): 16, ("Arabic", 3): 16,
    ("Arabic", 4): 18, ("Arabic", 5): 18, ("Arabic", 6): 20,
    ("French", 1): 25, ("French", 2): 25, ("French", 3): 25,
    ("French", 4): 18, ("French", 5): 18, ("French", 6): 18,
    ("Maths", 1): 13, ("Maths", 2): 14, ("Maths", 3): 15,
    ("Maths", 4): 16, ("Maths", 5): 16, ("Maths", 6): 16,
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def normalized_id(value: str) -> str:
    text = re.sub(r"[^a-z0-9]+", "", value.casefold())
    text = re.sub(r"y[123](?:nv|v)?[0-9]*$", "", text)
    return re.sub(r"(?:nv|v)[0-9]*$", "", text)


def normalized_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.casefold()).strip()


def check(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    paths = read_simple_paths(args.config.resolve())
    work = paths["work_root"]
    roots = [paths["y1_root"], paths["y2_root"], paths["y3_root"]]
    short = work / "outputs/y3_ministry/05_short_form"
    final = short / "final_baseline_map"

    item_map = read_rows(final / "baseline_half_length_item_map_source.csv")
    log = read_rows(final / "baseline_half_length_item_selection_log.csv")
    plan = read_rows(short / "y4_baseline_short_form_item_plan.csv")
    anchors = read_rows(short / "y4_baseline_selected_anchors.csv")
    decisions = read_rows(work / "outputs/y3_ministry/03_forms/y3_ministry_item_decisions.csv")
    pilot = read_rows(work / "outputs/y3_ministry/03_forms/y3_pilot_item_bank.csv")
    workbook_path = final / "Morocco_Baseline_Half_Length_Item_Map.xlsx"

    failures: list[str] = []
    checks: dict[str, object] = {}
    check(len(decisions) == 639, f"Expected 639 current rows, found {len(decisions)}", failures)
    check(len(plan) == 333, f"Expected 333 plan rows, found {len(plan)}", failures)
    check(len(item_map) == 333, f"Expected 333 final map rows, found {len(item_map)}", failures)

    counts = Counter((row["subject"], int(row["grade"])) for row in item_map)
    check(counts == Counter(EXPECTED_COUNTS), f"Unexpected form counts: {dict(counts)}", failures)
    checks["counts_by_subject_grade"] = {
        f"{subject}|{grade}": count for (subject, grade), count in sorted(counts.items())
    }

    map_keys = [(row["subject"], int(row["grade"]), row["item_id"]) for row in item_map]
    check(len(map_keys) == len(set(map_keys)), "Duplicate item map subject-grade-item rows", failures)
    required = [
        "subject", "grade", "baseline_item_no", "item_id", "item_or_summary",
        "answer_or_scoring", "content_domain", "cognitive_domain", "source", "final_check",
    ]
    for field in required:
        blank = [key for key, row in zip(map_keys, item_map) if not row[field].strip()]
        check(not blank, f"Blank {field} in {len(blank)} selected rows", failures)

    anchor_map = [row for row in item_map if row["anchor"] == "YES"]
    check(len(anchor_map) == 162, f"Expected 162 anchor placements, found {len(anchor_map)}", failures)
    link_counts = Counter(row["link_id"] for row in anchors)
    check(len(link_counts) == 33, f"Expected 33 anchor links, found {len(link_counts)}", failures)
    check(all(value == 5 for value in link_counts.values()), "Every anchor link must contain exactly five items", failures)
    check(len(anchors) == 165, f"Expected 165 link-specific anchor selections, found {len(anchors)}", failures)

    anchored_by_grade = {
        (row["subject"], int(row["grade"]), normalized_id(row["item_id"]))
        for row in anchor_map
    }
    missing_link_placements = []
    for row in anchors:
        for grade in [int(value) for value in row["grades"].split(",")]:
            key = (row["subject"], grade, row["normalized_item_id"])
            if key not in anchored_by_grade:
                missing_link_placements.append((row["link_id"], grade, row["item_id"]))
    check(not missing_link_placements, f"Missing endpoint anchor placements: {missing_link_placements[:10]}", failures)

    selected_log = [row for row in log if row["selected"] == "YES"]
    log_keys = [(row["subject"], int(row["grade"]), row["item_id"]) for row in selected_log]
    check(len(selected_log) == 333, f"Expected 333 selected log rows, found {len(selected_log)}", failures)
    check(len(log_keys) == len(set(log_keys)), "Duplicate selected decisions in audit log", failures)
    check(set(log_keys) == set(map_keys), "Selected audit-log rows do not exactly match the item map", failures)
    check(all(row["decision_reason"].strip() for row in log), "Blank decision reason in audit log", failures)
    check(all(row["source_reference"].strip() for row in log), "Blank source reference in audit log", failures)
    mutated_anchors = [
        row for row in selected_log
        if row["selected_anchor"] == "YES"
        and any(word in row["wording_status"].casefold() for word in ("revision", "easier"))
    ]
    check(not mutated_anchors, f"Selected anchors show revision status: {len(mutated_anchors)}", failures)

    current_by_key = {
        (row["subject"], int(row["administered_grade"]), row["item_id"]): row for row in decisions
    }
    pilot_by_key = {}
    for row in pilot:
        for grade in [int(value) for value in re.findall(r"[1-6]", row["target_grade"])]:
            pilot_by_key[(row["subject"], grade, normalized_id(row["item_id"]))] = row
    anchor_text_mismatches = []
    for row in anchor_map:
        key = (row["subject"], int(row["grade"]), row["item_id"])
        current = current_by_key.get(key)
        if current:
            expected = current["question_summary"]
        else:
            source = pilot_by_key.get((row["subject"], int(row["grade"]), normalized_id(row["item_id"])))
            expected = source["item_text"] if source else ""
        if not expected or normalized_text(expected) != normalized_text(row["item_or_summary"]):
            anchor_text_mismatches.append(key)
    check(not anchor_text_mismatches, f"Anchor text mismatches: {anchor_text_mismatches[:10]}", failures)

    math_nonanchor_unconfirmed = [
        row for row in item_map
        if row["subject"] == "Maths" and row["anchor"] != "YES"
        and row["answer_or_scoring"].startswith("MINISTRY TO CONFIRM")
    ]
    check(
        not math_nonanchor_unconfirmed,
        f"Maths non-anchor revisions without a proposed answer: {len(math_nonanchor_unconfirmed)}",
        failures,
    )

    with zipfile.ZipFile(workbook_path) as archive:
        workbook_xml = ElementTree.fromstring(archive.read("xl/workbook.xml"))
        namespace = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
        sheet_names = [node.attrib["name"] for node in workbook_xml.findall("m:sheets/m:sheet", namespace)]
    check(sheet_names == ["Baseline Item Map"], f"Unexpected workbook sheets: {sheet_names}", failures)

    confirmation_counts = Counter(
        (row["subject"], int(row["grade"]))
        for row in item_map if row["answer_or_scoring"].startswith("MINISTRY TO CONFIRM")
    )
    checks.update({
        "status": "PASS" if not failures else "FAIL",
        "item_rows": len(item_map),
        "share_of_639_row_bank_pct": round(100 * len(item_map) / 639, 1),
        "anchor_placements": len(anchor_map),
        "anchor_links": len(link_counts),
        "anchors_per_link": sorted(set(link_counts.values())),
        "selection_log_rows": len(log),
        "selected_log_rows": len(selected_log),
        "answer_confirmation_required_rows": sum(confirmation_counts.values()),
        "answer_confirmation_required_by_subject_grade": {
            f"{subject}|{grade}": count
            for (subject, grade), count in sorted(confirmation_counts.items())
        },
        "accepted_tail_exception": "French Grade 4 has one easy item rather than the target of two.",
        "workbook_sheets": sheet_names,
        "failures": failures,
    })
    output_path = assert_output_path(final / "baseline_half_length_validation.json", work, roots)
    output_path.write_text(json.dumps(checks, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(checks, indent=2, ensure_ascii=False))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
