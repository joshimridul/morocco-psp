#!/usr/bin/env python3
"""Build the compact protected pilot item bank from approved shortlist outputs.

Secure item text, answers, and edits remain under the protected work_root. The
tracked script contains only assembly logic and never embeds assessment items.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "00_inventory"))
from build_y3_registry import read_simple_paths  # noqa: E402
from path_guard import assert_output_path  # noqa: E402


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def normalized_id(value: str) -> str:
    text = re.sub(r"[^a-z0-9]+", "", value.casefold())
    text = re.sub(r"y[123](?:nv|v)?[0-9]*$", "", text)
    return re.sub(r"(?:nv|v)[0-9]*$", "", text)


def candidate_from_display(value: str) -> str:
    return value.split(" — ", 1)[0].strip()


def grades_from_link(link: str) -> list[int]:
    match = re.search(r" G([1-6])(?:–G([1-6])| pre/post)", link)
    if not match:
        return []
    return sorted({int(value) for value in match.groups() if value})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    paths = read_simple_paths(args.config.resolve())
    work = paths["work_root"]
    roots = [paths["y1_root"], paths["y2_root"], paths["y3_root"]]

    bank = read_rows(work / "private_manifests/historical_bank_candidate_evidence.csv")
    actions = read_rows(work / "outputs/y3_ministry/03_forms/y3_minimal_replacement_actions.csv")
    repairs = read_rows(work / "outputs/y3_ministry/03_forms/y3_minimal_anchor_repairs.csv")
    tails = read_rows(work / "outputs/y3_ministry/03_forms/y3_tail_coverage_check.csv")
    override_path = work / "private_manifests/manual_surface_change_overrides.csv"
    overrides = read_rows(override_path) if override_path.exists() else []

    bank_by_key = {(row["subject"], normalized_id(row["candidate_id"])): row for row in bank}
    roles: dict[tuple[str, str], set[str]] = defaultdict(set)
    grades: dict[tuple[str, str], set[int]] = defaultdict(set)

    for row in actions:
        candidate = candidate_from_display(row["primary_candidate"])
        if not candidate or candidate.startswith("no defensible"):
            continue
        key = (row["subject"], normalized_id(candidate))
        roles[key].add("replacement now" if row["priority"] == "change now" else "conditional replacement")
        grades[key].add(int(row["grade"]))

    for row in repairs:
        subject = row["link"].split(" G", 1)[0]
        for candidate in row["add_from_historical_bank"].split(", "):
            if not candidate or candidate == "candidate search unresolved":
                continue
            key = (subject, normalized_id(candidate))
            roles[key].add("anchor: " + row["link"])
            grades[key].update(grades_from_link(row["link"]))

    for row in tails:
        for candidate in row["proposed_items_for_tail_coverage"].split(", "):
            if not candidate:
                continue
            key = (row["subject"], normalized_id(candidate))
            roles[key].add("tail support")
            grades[key].add(int(row["grade"]))

    override_by_key = {(row["subject"], normalized_id(row["item_id"])): row for row in overrides}
    for key, row in override_by_key.items():
        roles[key].add(row.get("role") or "surface refresh")
        if row.get("target_grade"):
            grades[key].add(int(row["target_grade"]))

    output_rows: list[dict[str, Any]] = []
    resolved_tail_forms = {
        (row["subject"], int(row["target_grade"]))
        for row in overrides if row.get("role") == "tail support" and row.get("target_grade")
    }
    for key in sorted(roles, key=lambda value: (value[0], min(grades[value]) if grades[value] else 99, value[1])):
        subject, _ = key
        source = bank_by_key.get(key)
        override = override_by_key.get(key, {})
        role_values = sorted(roles[key])
        is_anchor = any(value.startswith("anchor:") for value in role_values)
        item_id = (source or override).get("candidate_id") or override.get("item_id") or key[1]
        item_text = override.get("original_item_text") or (source or {}).get("question_summary", "")
        answer = override.get("original_answer") or (source or {}).get("correct_answer_or_guideline", "")
        if is_anchor:
            suggested_change = "None—use the exact source version unchanged."
            change_made = "None (anchor)."
            revised_answer = answer
        elif subject == "Maths":
            suggested_change = override.get("suggested_surface_change", "Maths surface edit still to be drafted.")
            change_made = override.get("change_made", "")
            revised_answer = override.get("revised_answer", "")
        else:
            suggested_change = "Ministry: change only a name, object, or number; preserve the same skill and answer logic."
            change_made = ""
            revised_answer = ""

        issues = []
        if source is None and not override:
            issues.append("source item not resolved")
        if not item_text:
            issues.append("exact item text missing")
        if not answer:
            issues.append("answer/rubric confirmation required")
        if subject == "Maths" and not is_anchor and (not change_made or not revised_answer):
            issues.append("Maths edit incomplete")
        status = "ready for content approval" if not issues else "; ".join(issues)
        output_rows.append({
            "subject": subject,
            "target_grade": ",".join(str(value) for value in sorted(grades[key])),
            "item_id": item_id,
            "proposed_role": "; ".join(role_values),
            "item_text": item_text,
            "correct_answer_or_guideline": answer,
            "suggested_surface_change": suggested_change,
            "change_made": change_made,
            "revised_answer": revised_answer,
            "source_bank": override.get("source_reference") or (source or {}).get("historical_source", ""),
            "review_status": status,
        })

    for row in tails:
        if row["status"] != "Ministry item adaptation required":
            continue
        form = (row["subject"], int(row["grade"]))
        if form in resolved_tail_forms:
            continue
        output_rows.append({
            "subject": row["subject"],
            "target_grade": row["grade"],
            "item_id": "TO BE SELECTED",
            "proposed_role": "tail support",
            "item_text": "",
            "correct_answer_or_guideline": "",
            "suggested_surface_change": "Ministry: adapt one non-anchor item to supply the missing strict tail role.",
            "change_made": "",
            "revised_answer": "",
            "source_bank": "",
            "review_status": "item and answer required",
        })

    fields = [
        "subject", "target_grade", "item_id", "proposed_role", "item_text",
        "correct_answer_or_guideline", "suggested_surface_change", "change_made",
        "revised_answer", "source_bank", "review_status",
    ]
    output_path = assert_output_path(
        work / "outputs/y3_ministry/03_forms/y3_pilot_item_bank.csv", work, roots
    )
    write_rows(output_path, output_rows, fields)
    print({
        "output": str(output_path),
        "rows": len(output_rows),
        "anchors_unchanged": sum("anchor:" in row["proposed_role"] for row in output_rows),
        "ready_for_content_approval": sum(row["review_status"] == "ready for content approval" for row in output_rows),
    })


if __name__ == "__main__":
    main()
