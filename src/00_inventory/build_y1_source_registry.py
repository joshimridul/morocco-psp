#!/usr/bin/env python3
"""Build a hash-based Year 1 source registry without reading record contents."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


SOURCES = (
    ("data_candidate", "replication baseline", "8 - Replication package/Data/02 - Baseline/Clean/Baseline_tested.dta", "candidate"),
    ("data_candidate", "replication endline", "8 - Replication package/Data/03 - Endline/Clean/Endline_tested.dta", "candidate"),
    ("data_candidate", "published baseline", "4 - Data processing/Data repository/data/published/baseline/Baseline-tested-neam.dta", "candidate"),
    ("data_candidate", "published endline", "4 - Data processing/Data repository/data/published/endline/Endline-tested-neam.dta", "candidate"),
    ("data_candidate", "processing baseline clean", "4 - Data processing/Baseline/Clean/Baseline-tested-neam.dta", "candidate"),
    ("data_candidate", "processing endline clean", "4 - Data processing/Endline/Clean/Endline-tested-neam.dta", "candidate"),
    ("scoring_data", "Arabic delivered-score source", "4 - Data processing/Endline/Temp/temp3.dta", "verified_score_reference"),
    ("scoring_data", "French delivered-score source", "4 - Data processing/Endline/Temp/temp4.dta", "verified_score_reference"),
    ("scoring_data", "Maths delivered-score source", "4 - Data processing/Endline/Temp/temp5.dta", "verified_score_reference"),
    ("stored_model", "Arabic uirt model", "4 - Data processing/Endline/Temp/irt_arabic.ster", "verified_score_reference"),
    ("stored_model", "French uirt model", "4 - Data processing/Endline/Temp/irt_french.ster", "verified_score_reference"),
    ("stored_model", "Maths uirt model", "4 - Data processing/Endline/Temp/irt_math.ster", "verified_score_reference"),
    ("legacy_code", "replication entry point", "8 - Replication package/Do/replica_morocco1.do", "historical_evidence"),
    ("legacy_code", "final scoring", "5 - Data analysis/10_Endline/Analysis/Programs/01-Testscores-20251008-adb.do", "historical_evidence"),
    ("legacy_code", "pilot scoring", "5 - Data analysis/9_Endline_pilot/Analysis/Programs/1_endline_pilot_20240605_adb.do", "historical_evidence"),
    ("legacy_code", "endline cleaning", "5 - Data analysis/10_Endline/Setup/02_Endline_cleaning_2024-08-01_neam.do", "historical_evidence"),
    ("legacy_code", "endline-baseline scores", "5 - Data analysis/10_Endline/Setup/03_Endline_baseline_scores_2024-08-01_neam.do", "historical_evidence"),
    ("legacy_code", "baseline cleaning", "5 - Data analysis/4_Baseline/Setup/4_baseline-cleaning-20240729-neam.do", "historical_evidence"),
    ("codebook", "baseline tested iecodebook", "3 - Data collection/Item map/stata_codebooks/baseline/baseline_tested_iecodebook.xlsx", "mapping_evidence"),
    ("codebook", "endline tested iecodebook", "3 - Data collection/Item map/stata_codebooks/endline/endline_tested_iecodebook.xlsx", "mapping_evidence"),
    ("anchor_map", "baseline manual anchor renames", "3 - Data collection/Item map/stata_codebooks/baseline/baseline_rename_anchors_manual_neam.xlsx", "mapping_evidence"),
    ("anchor_map", "endline manual anchor renames", "3 - Data collection/Item map/stata_codebooks/endline/endline_rename_anchors_manual_neam.xlsx", "mapping_evidence"),
    ("anchor_map", "anchor summary", "3 - Data collection/Item map/Resources/Table - Summary of anchors items.xlsx", "mapping_evidence"),
    ("anchor_map", "endline crosswalk", "3 - Data collection/Item map/Resources/crosswalk/crosswalk endline - all subjects.xlsx", "mapping_evidence"),
    ("item_map", "Arabic item map", "3 - Data collection/Item map/Arabic/Item map arabic 2024-08-26 seo.xlsx", "version_evidence"),
    ("item_map", "French item map", "3 - Data collection/Item map/French/item map french 2024-09-11 adb.xlsx", "version_evidence"),
    ("item_map", "Maths item map", "3 - Data collection/Item map/Math/Item map maths 2024-09-11 adb.xlsx", "version_evidence"),
)


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


def sha256(path: Path, chunk_size: int = 4 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--github-root", type=Path, required=True)
    args = parser.parse_args()

    github_root = args.github_root.resolve()
    config = read_local_config(args.config.resolve())
    guard = load_path_guard(github_root)
    source_roots = [config["y1_root"], config["y2_root"], config["y3_root"]]
    out_dir = config["work_root"] / "outputs/y1_y3_irt/00_y1_reference/source_registry"
    guard.assert_output_path(out_dir, config["work_root"], source_roots)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, object]] = []
    for source_type, role, relative_path, status in SOURCES:
        candidate = config["y1_root"] / relative_path
        row: dict[str, object] = {
            "year": 1,
            "root_alias": "y1_root",
            "relative_path": relative_path,
            "source_type": source_type,
            "role": role,
            "status": status,
            "exists": candidate.is_file(),
            "size_bytes": "",
            "modified_utc": "",
            "sha256": "",
            "duplicate_group": "",
        }
        if candidate.is_file():
            source = guard.assert_source_path(candidate, source_roots)
            stat = source.stat()
            row.update(
                size_bytes=stat.st_size,
                modified_utc=datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat(),
                sha256=sha256(source),
            )
        rows.append(row)

    by_hash: dict[str, list[int]] = defaultdict(list)
    for index, row in enumerate(rows):
        if row["sha256"]:
            by_hash[str(row["sha256"])].append(index)
    duplicate_number = 0
    for indexes in by_hash.values():
        if len(indexes) > 1:
            duplicate_number += 1
            for index in indexes:
                rows[index]["duplicate_group"] = f"exact_duplicate_{duplicate_number:02d}"

    csv_path = out_dir / "y1_source_registry.csv"
    json_path = out_dir / "y1_source_registry_summary.json"
    for output in (csv_path, json_path):
        guard.assert_output_path(output, config["work_root"], source_roots)

    fieldnames = list(rows[0])
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    summary = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "registry_rows": len(rows),
        "existing_files": sum(bool(row["exists"]) for row in rows),
        "missing_files": sum(not bool(row["exists"]) for row in rows),
        "exact_duplicate_groups": duplicate_number,
        "output": "y1_source_registry.csv",
    }
    json_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
