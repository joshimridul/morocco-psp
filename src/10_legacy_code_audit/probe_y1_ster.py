#!/usr/bin/env python3
"""Safely inspect the stored Year 1 uirt estimation objects.

Inputs remain read-only under y1_root. Detailed logs and summaries are written
only below work_root. This script does not execute any inherited do-file.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


STER_FILES = {
    "arabic": "4 - Data processing/Endline/Temp/irt_arabic.ster",
    "french": "4 - Data processing/Endline/Temp/irt_french.ster",
    "maths": "4 - Data processing/Endline/Temp/irt_math.ster",
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

    do_file = github_root / "src/10_legacy_code_audit/probe_y1_uirt_ster.do"
    if not do_file.exists():
        raise FileNotFoundError(do_file)
    if not config["stata"].exists():
        raise FileNotFoundError(config["stata"])

    out_dir = config["work_root"] / "outputs/y1_y3_irt/00_y1_reference/ster_probe"
    guard.assert_output_path(out_dir, config["work_root"], source_roots)
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest: dict[str, object] = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "script": "src/10_legacy_code_audit/probe_y1_uirt_ster.do",
        "stata_executable": config["stata"].name,
        "models": [],
    }

    for subject, relative_path in STER_FILES.items():
        ster_path = guard.assert_source_path(config["y1_root"] / relative_path, source_roots)
        output_log = out_dir / f"y1_{subject}_ster_probe.log"
        output_summary = out_dir / f"y1_{subject}_ster_summary.txt"
        output_params = out_dir / f"y1_{subject}_item_parameters.csv"
        output_group = out_dir / f"y1_{subject}_group_parameters.csv"
        driver_output = out_dir / f"y1_{subject}_stata_driver.txt"
        for output in (output_log, output_summary, output_params, output_group, driver_output):
            guard.assert_output_path(output, config["work_root"], source_roots, [ster_path])

        command = [str(config["stata"]), "-b", "do", str(do_file)]
        run_environment = os.environ.copy()
        run_environment.update(
            {
                "MOROCCO_Y1_STER_FILE": str(ster_path),
                "MOROCCO_Y1_SUBJECT": subject,
                "MOROCCO_Y1_OUTPUT_LOG": str(output_log),
                "MOROCCO_Y1_OUTPUT_SUMMARY": str(output_summary),
                "MOROCCO_Y1_OUTPUT_PARAMS": str(output_params),
                "MOROCCO_Y1_OUTPUT_GROUP": str(output_group),
            }
        )
        result = subprocess.run(
            command,
            cwd=out_dir,
            env=run_environment,
            capture_output=True,
            text=True,
            timeout=600,
            check=False,
        )
        driver_output.write_text(
            f"returncode={result.returncode}\n\nSTDOUT\n{result.stdout}\n\nSTDERR\n{result.stderr}",
            encoding="utf-8",
        )

        default_batch_log = out_dir / "probe_y1_uirt_ster.log"
        batch_log = out_dir / f"y1_{subject}_stata_batch.log"
        if default_batch_log.exists():
            shutil.copy2(default_batch_log, batch_log)

        log_text = output_log.read_text(encoding="utf-8", errors="replace") if output_log.exists() else ""
        summary_text = (
            output_summary.read_text(encoding="utf-8", errors="replace")
            if output_summary.exists()
            else ""
        )
        success = (
            result.returncode == 0
            and "PROBE_COMPLETE" in log_text
            and "probe_status=complete" in summary_text
            and output_params.exists()
            and output_group.exists()
        )

        manifest["models"].append(
            {
                "subject": subject,
                "source_root_alias": "y1_root",
                "relative_path": relative_path,
                "bytes": ster_path.stat().st_size,
                "sha256": sha256(ster_path),
                "returncode": result.returncode,
                "success": success,
                "probe_log": output_log.name,
                "summary": output_summary.name,
                "item_parameters": output_params.name,
                "group_parameters": output_group.name,
                "batch_log": batch_log.name if batch_log.exists() else "",
            }
        )
        if not success:
            raise RuntimeError(f"Year 1 {subject} stored-model probe failed; inspect {output_log}")

    manifest_path = out_dir / "y1_ster_probe_manifest.json"
    guard.assert_output_path(manifest_path, config["work_root"], source_roots)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "complete", "models": len(STER_FILES), "output": str(out_dir)}))


if __name__ == "__main__":
    main()
