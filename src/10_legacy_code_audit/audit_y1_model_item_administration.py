#!/usr/bin/env python3
"""Run guarded aggregate wave-by-grade availability checks for Year 1 model items."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


SUBJECTS = {
    "arabic": "4 - Data processing/Endline/Temp/temp3.dta",
    "french": "4 - Data processing/Endline/Temp/temp4.dta",
    "maths": "4 - Data processing/Endline/Temp/temp5.dta",
}


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
    pattern = re.compile(
        r"^\s*(y1_root|y2_root|y3_root|work_root|stata):\s*[\"']?(.*?)[\"']?\s*$"
    )
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            values[match.group(1)] = Path(match.group(2)).expanduser().resolve()
    required = {"y1_root", "y2_root", "y3_root", "work_root", "stata"}
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
    do_file = github_root / "src/10_legacy_code_audit/audit_y1_model_item_administration.do"
    parameter_dir = config["work_root"] / "outputs/y1_y3_irt/00_y1_reference/ster_probe"
    out_dir = config["work_root"] / "outputs/y1_y3_irt/00_y1_reference/item_crosswalk"
    guard.assert_output_path(out_dir, config["work_root"], source_roots)
    out_dir.mkdir(parents=True, exist_ok=True)

    combined_rows: list[dict[str, str]] = []
    manifest: dict[str, object] = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "script": "src/10_legacy_code_audit/audit_y1_model_item_administration.do",
        "subjects": [],
    }

    for subject, relative_data in SUBJECTS.items():
        data_path = guard.assert_source_path(config["y1_root"] / relative_data, source_roots)
        parameter_path = parameter_dir / f"y1_{subject}_item_parameters.csv"
        with parameter_path.open(encoding="utf-8", newline="") as handle:
            item_ids = [row["item_id"] for row in csv.DictReader(handle)]
        guard.assert_no_direct_identifier_columns(["analytic_item_id", "baseline", "grade"])

        item_file = out_dir / f"y1_{subject}_model_items.txt"
        output_csv = out_dir / f"y1_{subject}_item_administration.csv"
        output_log = out_dir / f"y1_{subject}_item_administration.log"
        output_summary = out_dir / f"y1_{subject}_item_administration_summary.txt"
        driver_output = out_dir / f"y1_{subject}_item_administration_driver.txt"
        for output in (item_file, output_csv, output_log, output_summary, driver_output):
            guard.assert_output_path(output, config["work_root"], source_roots, [data_path])

        item_file.write_text("\n".join(item_ids) + "\n", encoding="utf-8")
        environment = os.environ.copy()
        environment.update(
            {
                "MOROCCO_Y1_ADMIN_DATA": str(data_path),
                "MOROCCO_Y1_ADMIN_ITEMS": str(item_file),
                "MOROCCO_Y1_ADMIN_OUTPUT": str(output_csv),
                "MOROCCO_Y1_ADMIN_LOG": str(output_log),
                "MOROCCO_Y1_ADMIN_SUMMARY": str(output_summary),
            }
        )
        result = subprocess.run(
            [str(config["stata"]), "-b", "do", str(do_file)],
            cwd=out_dir,
            env=environment,
            capture_output=True,
            text=True,
            timeout=1200,
            check=False,
        )
        driver_output.write_text(
            f"returncode={result.returncode}\n\nSTDOUT\n{result.stdout}\n\nSTDERR\n{result.stderr}",
            encoding="utf-8",
        )
        default_batch_log = out_dir / "audit_y1_model_item_administration.log"
        batch_log = out_dir / f"y1_{subject}_item_administration_stata_batch.log"
        if default_batch_log.exists():
            shutil.copy2(default_batch_log, batch_log)

        log_text = output_log.read_text(encoding="utf-8", errors="replace") if output_log.exists() else ""
        summary_text = output_summary.read_text(encoding="utf-8", errors="replace") if output_summary.exists() else ""
        success = (
            result.returncode == 0
            and "ADMIN_AUDIT_COMPLETE" in log_text
            and "missing_variable_count=0" in summary_text
        )
        if not success:
            raise RuntimeError(f"Year 1 {subject} administration audit failed; inspect {output_log}")

        with output_csv.open(encoding="utf-8", newline="") as handle:
            for row in csv.DictReader(handle):
                combined_rows.append(
                    {
                        "year": "1",
                        "subject": subject,
                        "analytic_item_id": row["analytic_item_id"],
                        "wave": "baseline" if row["baseline"] == "1" else "endline",
                        "administered_grade": row["grade"],
                        "n_students": row["n_students"],
                        "n_nonmissing": row["n_nonmissing"],
                        "administration_rate": row["administration_rate"],
                        "n_zero": row["n_zero"],
                        "n_one": row["n_one"],
                        "n_other": row["n_other"],
                    }
                )

        manifest["subjects"].append(
            {
                "subject": subject,
                "data_root_alias": "y1_root",
                "data_relative_path": relative_data,
                "data_sha256": sha256(data_path),
                "model_items": len(item_ids),
                "success": success,
                "summary": output_summary.name,
                "log": output_log.name,
            }
        )

    combined_path = out_dir / "y1_model_item_administration.csv"
    manifest_path = out_dir / "y1_item_administration_manifest.json"
    fieldnames = [
        "year",
        "subject",
        "analytic_item_id",
        "wave",
        "administered_grade",
        "n_students",
        "n_nonmissing",
        "administration_rate",
        "n_zero",
        "n_one",
        "n_other",
    ]
    guard.assert_no_direct_identifier_columns(fieldnames)
    with combined_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(combined_rows)
    manifest["administration_rows"] = len(combined_rows)
    manifest["nonbinary_cells"] = sum(int(row["n_other"]) > 0 for row in combined_rows)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "complete", "rows": len(combined_rows), "output": str(combined_path)}))


if __name__ == "__main__":
    main()
