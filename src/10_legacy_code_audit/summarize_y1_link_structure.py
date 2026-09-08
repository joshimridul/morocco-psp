#!/usr/bin/env python3
"""Summarize Year 1 shared-parameter links from protected crosswalk outputs."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def load_path_guard(github_root: Path):
    module_path = github_root / "src/00_inventory/path_guard.py"
    spec = importlib.util.spec_from_file_location("path_guard", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load path guard: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_local_config(path: Path) -> dict[str, Path]:
    values: dict[str, Path] = {}
    pattern = re.compile(r"^\s*(y1_root|y2_root|y3_root|work_root):\s*[\"']?(.*?)[\"']?\s*$")
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            values[match.group(1)] = Path(match.group(2)).expanduser().resolve()
    required = {"y1_root", "y2_root", "y3_root", "work_root"}
    missing = required - values.keys()
    if missing:
        raise ValueError(f"Missing configuration keys: {sorted(missing)}")
    return values


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--github-root", type=Path, required=True)
    args = parser.parse_args()

    github_root = args.github_root.resolve()
    config = read_local_config(args.config.resolve())
    guard = load_path_guard(github_root)
    source_roots = [config["y1_root"], config["y2_root"], config["y3_root"]]
    out_dir = config["work_root"] / "outputs/y1_y3_irt/00_y1_reference/item_crosswalk"
    guard.assert_output_path(out_dir, config["work_root"], source_roots)

    administration_path = out_dir / "y1_model_item_administration.csv"
    crosswalk_path = out_dir / "y1_source_variable_item_crosswalk.csv"
    with administration_path.open(encoding="utf-8", newline="") as handle:
        administration = list(csv.DictReader(handle))
    with crosswalk_path.open(encoding="utf-8", newline="") as handle:
        crosswalk = list(csv.DictReader(handle))

    underlying = {
        row["analytic_item_id"]: row["underlying_item_id"] or row["analytic_item_id"]
        for row in crosswalk
    }
    subject_summaries = []
    edge_rows = []
    for subject in ("arabic", "french", "maths"):
        rows = [row for row in administration if row["subject"] == subject]
        waves_by_model_item: dict[str, set[str]] = defaultdict(set)
        waves_by_item_family: dict[str, set[str]] = defaultdict(set)
        endline_grades_by_model_item: dict[str, set[int]] = defaultdict(set)
        for row in rows:
            item_id = row["analytic_item_id"]
            wave = row["wave"]
            waves_by_model_item[item_id].add(wave)
            waves_by_item_family[underlying.get(item_id, item_id)].add(wave)
            if wave == "endline":
                endline_grades_by_model_item[item_id].add(int(float(row["administered_grade"])))

        cross_wave_families = {
            family for family, waves in waves_by_item_family.items()
            if waves == {"baseline", "endline"}
        }
        shared_model_items = {
            item_id for item_id, waves in waves_by_model_item.items()
            if waves == {"baseline", "endline"}
        }
        constrained_families = {
            underlying.get(item_id, item_id) for item_id in shared_model_items
        } & cross_wave_families

        adjacent_counts = {}
        for lower_grade in range(1, 6):
            upper_grade = lower_grade + 1
            count = sum(
                lower_grade in grades and upper_grade in grades
                for grades in endline_grades_by_model_item.values()
            )
            adjacent_counts[f"{lower_grade}-{upper_grade}"] = count
            edge_rows.append(
                {
                    "year": 1,
                    "subject": subject,
                    "link_type": "endline_adjacent_grade_shared_parameter",
                    "from_grade": lower_grade,
                    "to_grade": upper_grade,
                    "shared_parameter_count": count,
                    "verification_status": "analytic_constraint_verified_item_version_pending",
                }
            )

        subject_summaries.append(
            {
                "subject": subject,
                "model_items": len(waves_by_model_item),
                "cross_wave_item_families": len(cross_wave_families),
                "cross_wave_families_constrained_same_parameter": len(constrained_families),
                "cross_wave_families_freed_or_split": len(cross_wave_families - constrained_families),
                "endline_adjacent_grade_shared_parameter_counts": adjacent_counts,
            }
        )

    summary_path = out_dir / "y1_link_structure_summary.json"
    edges_path = out_dir / "y1_link_edges.csv"
    summary = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "interpretation": (
            "Counts describe constraints and observed administration in the verified Year 1 scoring model. "
            "They are not final anchor counts until prompt, stimulus, options, key/rubric, layout, and exposure are verified."
        ),
        "subjects": subject_summaries,
    }
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    fieldnames = list(edge_rows[0])
    guard.assert_no_direct_identifier_columns(fieldnames)
    with edges_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(edge_rows)
    print(json.dumps({"status": "complete", "subjects": len(subject_summaries), "edges": len(edge_rows)}))


if __name__ == "__main__":
    main()
