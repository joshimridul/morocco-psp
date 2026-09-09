#!/usr/bin/env python3
"""Register candidate Year 2 IRT sources without modifying or reading records.

The registry deliberately distinguishes a reproducible development input from a
collaborator-confirmed canonical source.  A filename, directory name, or date is
never sufficient evidence of canonical status.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


SOURCES = (
    (
        "response_data",
        "baseline development input",
        "4 - Data processing/04_Baseline/Clean/baseline_data.dta",
        "provisional_development_input_requires_confirmation",
    ),
    (
        "response_data_candidate",
        "baseline dated alternative",
        "4 - Data processing/04_Baseline/Clean/baseline_data_2024-10-14_ya.dta",
        "candidate_not_selected",
    ),
    (
        "response_data",
        "pilot development input",
        "4 - Data processing/08_Pilot/Clean/pilot_data_20250505_ya.dta",
        "provisional_development_input_requires_confirmation",
    ),
    (
        "response_data",
        "endline development input",
        "4 - Data processing/09_Endline/Clean/endline_data_20250716_ks.dta",
        "provisional_development_input_requires_confirmation",
    ),
    (
        "response_data_candidate",
        "endline SCTO-form alternative",
        "4 - Data processing/09_Endline/Clean/endline_scto_data_20250717.dta",
        "candidate_not_selected_different_schema",
    ),
    (
        "combined_data_candidate",
        "combined Year 1-Year 2 file",
        "4 - Data processing/09_Endline/Clean/y1y2_tested_data.dta",
        "not_used_for_initial_calibration",
    ),
    (
        "item_map",
        "baseline Arabic map",
        "3 - Data collection/01_Baseline/3 - Item map/Arabic/MCQ_Item_map_arabic_2024-11-14_ya.xlsx",
        "provisional_version_evidence_requires_confirmation",
    ),
    (
        "item_map",
        "baseline French map",
        "3 - Data collection/01_Baseline/3 - Item map/French/MCQ_item map french 2024-10-11 ya.xlsx",
        "provisional_version_evidence_requires_confirmation",
    ),
    (
        "item_map",
        "baseline mathematics map",
        "3 - Data collection/01_Baseline/3 - Item map/Math/MCQ_Item map maths 2024-10-11 ya.xlsx",
        "provisional_version_evidence_requires_confirmation",
    ),
    (
        "item_map",
        "pilot consolidated map",
        "3 - Data collection/03_Pilot/03_Item Maps/Item_maps_20250507_ks.xlsx",
        "provisional_version_evidence_requires_confirmation",
    ),
    (
        "item_map",
        "endline consolidated map",
        "3 - Data collection/02_Endline/03_Item Maps/Item_maps_20250715_ks.xlsx",
        "provisional_version_evidence_requires_confirmation",
    ),
    (
        "item_map_candidate",
        "endline conflicted copy",
        "3 - Data collection/02_Endline/03_Item Maps/Archive/Item_maps_20250710_jl (Copie en conflit de Jawad Lahlou 2025-07-12).xlsx",
        "excluded_conflicted_copy",
    ),
    (
        "codebook",
        "baseline tested codebook",
        "3 - Data collection/01_Baseline/3 - Item map/stata_codebooks/baseline/tested_iecodebook.xlsx",
        "mapping_evidence",
    ),
)


def read_local_config(path: Path) -> dict[str, Path]:
    values: dict[str, Path] = {}
    pattern = re.compile(
        r"^\s*(y1_root|y2_root|y3_root|work_root):\s*[\"']?(.*?)[\"']?\s*$"
    )
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            values[match.group(1)] = Path(match.group(2)).expanduser().resolve()
    missing = {"y1_root", "y2_root", "y3_root", "work_root"} - values.keys()
    if missing:
        raise ValueError(f"Missing configuration keys: {sorted(missing)}")
    return values


def sha256(path: Path, chunk_size: int = 4 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def within(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    paths = read_local_config(args.config.resolve())
    source_roots = [paths["y1_root"], paths["y2_root"], paths["y3_root"]]
    out_dir = paths["work_root"] / "outputs/y1_y3_irt/00_y2_sources"
    if not within(out_dir.resolve(), paths["work_root"]):
        raise ValueError("Output must be below work_root")
    if any(
        within(out_dir.resolve(), root) and not within(paths["work_root"], root)
        for root in source_roots
    ):
        raise ValueError("Output cannot be inside a legacy source root")
    out_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, object]] = []
    for source_type, role, relative_path, status in SOURCES:
        candidate = (paths["y2_root"] / relative_path).resolve()
        if not within(candidate, paths["y2_root"]):
            raise ValueError(f"Source escaped y2_root: {relative_path}")
        row: dict[str, object] = {
            "year": 2,
            "root_alias": "y2_root",
            "relative_path": relative_path,
            "source_type": source_type,
            "role": role,
            "status": status,
            "canonical_confirmed": 0,
            "exists": candidate.is_file(),
            "size_bytes": "",
            "modified_utc": "",
            "sha256": "",
            "exact_duplicate_group": "",
        }
        if candidate.is_file():
            stat = candidate.stat()
            row.update(
                size_bytes=stat.st_size,
                modified_utc=datetime.fromtimestamp(
                    stat.st_mtime, timezone.utc
                ).isoformat(),
                sha256=sha256(candidate),
            )
        rows.append(row)

    by_hash: dict[str, list[int]] = defaultdict(list)
    for index, row in enumerate(rows):
        if row["sha256"]:
            by_hash[str(row["sha256"])].append(index)
    duplicate_n = 0
    for indexes in by_hash.values():
        if len(indexes) > 1:
            duplicate_n += 1
            for index in indexes:
                rows[index]["exact_duplicate_group"] = f"exact_duplicate_{duplicate_n:02d}"

    registry_path = out_dir / "y2_source_registry.csv"
    with registry_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    blockers = [
        {
            "issue_id": "Y2-SOURCE-001",
            "severity": "high",
            "status": "requires_collaborator_confirmation",
            "issue": "Canonical Year 2 wave-specific response files are not confirmed.",
            "scientific_consequence": "Development estimates may change if a different cleaned wave file is canonical.",
            "provisional_action": "Use only the explicitly registered development inputs and keep every score unapproved.",
        },
        {
            "issue_id": "Y2-MAP-001",
            "severity": "high",
            "status": "requires_collaborator_confirmation",
            "issue": "Canonical Year 2 item maps, scoring keys, and final instrument versions are not confirmed.",
            "scientific_consequence": "Item-ID and English-summary matches cannot establish final anchor equivalence.",
            "provisional_action": "Use hashes only for development links and require full version review before approval.",
        },
        {
            "issue_id": "Y2-SAMPLE-001",
            "severity": "high",
            "status": "requires_collaborator_confirmation",
            "issue": "Year 2 cohort and analytic-sample definitions are not yet frozen in tracked documentation.",
            "scientific_consequence": "Population distributions and later matched-DiD merges may use the wrong cohort/sample.",
            "provisional_action": "Estimate treatment-blind measurement models only; do not run causal regressions.",
        },
    ]
    blocker_path = out_dir / "y2_irt_blocking_issues.csv"
    with blocker_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(blockers[0]))
        writer.writeheader()
        writer.writerows(blockers)

    summary = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "registry_rows": len(rows),
        "existing_files": sum(bool(row["exists"]) for row in rows),
        "missing_files": sum(not bool(row["exists"]) for row in rows),
        "canonical_confirmed_files": 0,
        "exact_duplicate_groups": duplicate_n,
        "development_response_inputs": [
            row["relative_path"]
            for row in rows
            if row["source_type"] == "response_data"
        ],
        "status": "development_only_requires_source_confirmation",
    }
    (out_dir / "y2_source_registry_summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
