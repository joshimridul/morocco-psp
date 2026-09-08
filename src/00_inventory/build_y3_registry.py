#!/usr/bin/env python3
"""Build the pre-analysis Year 3 source registry and blocking-issues register.

The registry stores root aliases and relative paths only. It deliberately excludes
PII/master-key material, inherited code, archives, and conflicted copies from the
canonical candidate set. Those exclusions are logged rather than silently ignored.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from path_guard import assert_output_path, assert_source_path  # noqa: E402


EXCLUDE_PARTS = {"archive", "archives", "old", "temp", "temporary"}
EXCLUDE_TOKENS = (
    "copie en conflit",
    "conflicted copy",
    "recovered",
    "pii",
    "master key",
    "master_key",
    "preload",
)


@dataclass(frozen=True)
class RegistryRow:
    source_id: str
    root_alias: str
    relative_path: str
    wave: str
    source_role: str
    source_family: str
    extension: str
    bytes: int
    modified_utc: str
    sha256: str
    candidate_status: str
    exclusion_reason: str
    canonicality_status: str
    notes: str


def read_simple_paths(path: Path) -> dict[str, Path]:
    """Read the four absolute path values from the small local YAML file."""
    values: dict[str, Path] = {}
    pattern = re.compile(r"^\s*(y[123]_root|work_root):\s*[\"']?(.*?)[\"']?\s*$")
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            values[match.group(1)] = Path(match.group(2)).expanduser().resolve()
    required = {"y1_root", "y2_root", "y3_root", "work_root"}
    missing = required - values.keys()
    if missing:
        raise ValueError(f"Missing path keys in {path}: {sorted(missing)}")
    return values


def sha256(path: Path, chunk_size: int = 4 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def excluded_reason(path: Path) -> str:
    lower_parts = {part.lower() for part in path.parts}
    if lower_parts & EXCLUDE_PARTS:
        return "archive_or_temporary_location"
    lower = str(path).lower()
    for token in EXCLUDE_TOKENS:
        if token in lower:
            return f"excluded_token:{token}"
    return ""


def files_under(directory: Path, suffixes: Iterable[str]) -> list[Path]:
    wanted = {suffix.lower() for suffix in suffixes}
    return sorted(
        path
        for path in directory.rglob("*")
        if path.is_file() and path.suffix.lower() in wanted
    )


def classify(path: Path, y3_root: Path, github_root: Path) -> tuple[str, str, str, str, str]:
    """Return root alias, relative path, wave, family, role."""
    if path.is_relative_to(y3_root):
        root_alias = "y3_root"
        relative = path.relative_to(y3_root).as_posix()
    elif path.is_relative_to(github_root):
        root_alias = "github_root"
        relative = path.relative_to(github_root).as_posix()
    else:
        raise ValueError(f"Unclassified registry path: {path}")

    lower = relative.lower()
    if "01_baseline" in lower or "02_baseline" in lower or "03_baseline" in lower:
        wave = "baseline"
    elif "02_endline_pilot" in lower or "03_pilot" in lower or "04_pilot" in lower:
        wave = "pilot"
    elif "03_endline" in lower or "04_endline" in lower or "05_endline" in lower:
        wave = "endline"
    else:
        wave = "cross_wave"

    if path.suffix.lower() == ".dta":
        family = "response_or_sample_data"
    elif "item map" in lower or "item_map" in lower or "endline item map" in lower:
        family = "item_map"
    elif "instruments" in lower:
        family = "instrument_or_scoring_guide"
    elif "tables" in lower:
        family = "prior_aggregate_output"
    else:
        family = "supporting_document"

    if path.name == "y1y2y3_tested_data.dta":
        role = "reconciliation_only"
    elif family == "response_or_sample_data":
        role = "candidate_wave_source"
    elif family == "item_map":
        role = "candidate_metadata_source"
    elif family == "instrument_or_scoring_guide":
        role = "candidate_form_or_scoring_source"
    elif family == "prior_aggregate_output":
        role = "tie_out_reference_only"
    else:
        role = "supporting_context"
    return root_alias, relative, wave, family, role


def registry_candidates(y3_root: Path, github_root: Path) -> list[Path]:
    selected = [
        y3_root / "4 - Data processing/02_Baseline/Clean/baseline_data_20251107_eo.dta",
        y3_root / "4 - Data processing/01_Sampling/Baseline sample/deidentified_Y3baseline_sample_20251111_ks.dta",
        y3_root / "4 - Data processing/03_Pilot/Clean/pilot_clean_20260518_mji.dta",
        y3_root / "4 - Data processing/03_Pilot/Clean/surveycto_clean_20052026_mji.dta",
        y3_root / "4 - Data processing/04_Endline/Clean/endline_data_20260702_mji.dta",
        y3_root / "4 - Data processing/04_Endline/Clean/y1y2y3_tested_data.dta",
        y3_root / "3 - Data collection/01_Baseline/3 - Item map/Item_map_20251013_eo.xlsx",
        y3_root / "3 - Data collection/01_Baseline/3 - Item map/Y1-3 Item Map/Item_maps_compiled_16122025_eo.xlsx",
        y3_root / "3 - Data collection/01_Baseline/3 - Item map/Y1-3 Item Map/item-map-anchor.xlsx",
        y3_root / "3 - Data collection/02_Endline_Pilot/3 - Item map/Item_map_20260523_mji.xlsx",
        y3_root / "3 - Data collection/03_Endline/3 - Item map/Item_map_20260618_eo.xlsx",
        y3_root / "5 - Data analysis/03_Baseline/Analysis/Tables/baseline_items_toupdate_20260223_eo.xlsx",
        github_root / "exchange-with-ministry/received-from-ministry/Endline item map_from_btihaj.xlsx",
    ]

    instrument_dirs = [
        y3_root / "3 - Data collection/01_Baseline/4 - Instruments",
        y3_root / "3 - Data collection/02_Endline_Pilot/4 - Instruments",
        y3_root / "3 - Data collection/03_Endline/4 - Instruments",
    ]
    for directory in instrument_dirs:
        selected.extend(files_under(directory, {".pdf", ".docx", ".xlsx", ".xls"}))

    baseline_tables = y3_root / "5 - Data analysis/03_Baseline/Analysis/Tables"
    if baseline_tables.exists():
        selected.extend(
            path
            for path in baseline_tables.iterdir()
            if path.is_file()
            and (
                path.name.startswith("table-05-item-")
                or path.name.startswith("table-06-students-irt-")
            )
        )
    return sorted(set(selected))


def blocking_issues() -> list[dict[str, str]]:
    return [
        {"issue_id": "Y3-B001", "status": "open", "severity": "critical", "area": "source lineage", "issue": "Wave-specific files are candidates, not yet collaborator-confirmed canonical sources.", "scientific_consequence": "Results could change if a different source version is authoritative.", "provisional_action": "Hash all candidates; analyze current non-archive wave files; retain confirmation flag."},
        {"issue_id": "Y3-B002", "status": "team-owned", "severity": "critical", "area": "privacy", "issue": "A PII-like baseline output exists and privacy cleanup is assigned to another team member.", "scientific_consequence": "No effect on item estimates if excluded; material disclosure risk if opened or exported.", "provisional_action": "Exclude from registry and analysis; do not open; require separate privacy sign-off."},
        {"issue_id": "Y3-B003", "status": "open", "severity": "high", "area": "sample", "issue": "Baseline out-of-list review identifies 100 flags: 80 true out-of-list, 11 wrong-subject tests, and 9 apparently erroneous flags.", "scientific_consequence": "Sample composition and subject-form assignment may be wrong for affected records.", "provisional_action": "Create explicit inclusion flags and run sensitivity analyses; do not silently drop all 100."},
        {"issue_id": "Y3-B004", "status": "open", "severity": "high", "area": "content metadata", "issue": "Ministry domain coding is partial and not synchronized to the current baseline/endline master maps; the All tab is stale.", "scientific_consequence": "Content-balance and dimensionality results cannot be interpreted consistently across forms.", "provisional_action": "Build a reconciled row-level taxonomy with provenance and confirmation status."},
        {"issue_id": "Y3-B005", "status": "open", "severity": "high", "area": "grade/form metadata", "issue": "Observed map labels include Arabic Grade 7 and inconsistent mathematics Grade 5/6 labels.", "scientific_consequence": "Items can be assigned to the wrong administered grade or link role.", "provisional_action": "Resolve grade from form, instrument, variable, and map jointly; retain conflict flag."},
        {"issue_id": "Y3-B006", "status": "open", "severity": "medium", "area": "item provenance", "issue": "Origin/provenance is missing for 37 Arabic rows and 1 mathematics row in the Ministry-returned map.", "scientific_consequence": "Exposure, novelty, and across-year anchor eligibility cannot be verified.", "provisional_action": "Infer only where exact version evidence exists; otherwise mark requires confirmation."},
        {"issue_id": "Y3-B007", "status": "open", "severity": "critical", "area": "scoring", "issue": "No verified machine-readable key/rubric/form manifest has yet been tied to every response variable.", "scientific_consequence": "Score reconstruction and item statistics may use an incorrect key or denominator.", "provisional_action": "Triangulate item maps, examiner guides, SurveyCTO labels, and stored totals before estimation."},
        {"issue_id": "Y3-B008", "status": "open", "severity": "high", "area": "testlets/rubrics", "issue": "An item-map row may be a response field, rubric criterion, or passage-dependent subitem rather than an independent item.", "scientific_consequence": "Alpha, factor, local-dependence, and IRT models can overstate information or violate local independence.", "provisional_action": "Create stimulus_id/testlet_id/rubric_id and fit sensitivity models that preserve bundles."},
        {"issue_id": "Y3-B009", "status": "open", "severity": "high", "area": "French forms", "issue": "The returned Ministry work does not resolve the requested grade-specific French form redesign.", "scientific_consequence": "Shared material may have poor targeting or excessive exposure across grades.", "provisional_action": "Evaluate grade-specific targeting and recommend distinct forms with controlled anchors."},
        {"issue_id": "Y3-B010", "status": "open", "severity": "high", "area": "security/exposure", "issue": "Item exposure, feedback, copying, and prior-use status are not fully documented.", "scientific_consequence": "Statistically stable items may still be invalid anchors or operational items.", "provisional_action": "Keep substantive/exposure review separate from empirical quality; block unverified anchors."},
        {"issue_id": "Y3-B011", "status": "open", "severity": "high", "area": "link design", "issue": "The intended uses of baseline, pilot, and endline scales and required reporting links are not formally signed off.", "scientific_consequence": "A defensible anchor for one link may be inappropriate for another.", "provisional_action": "Report separate candidate sets for within-grade pre/post, adjacent-grade vertical, and across-year trend links."},
        {"issue_id": "Y3-B012", "status": "open", "severity": "high", "area": "sample/cohort", "issue": "Pilot and endline cohort/sample definitions require reconciliation across wave-specific source files.", "scientific_consequence": "Development/validation splits and population inference may be mis-specified.", "provisional_action": "Construct a form-sample graph from wave files before pooled or linked estimation."},
        {"issue_id": "Y3-B013", "status": "deferred", "severity": "medium", "area": "legacy lineage", "issue": "The combined Y1-Y3 file and inherited code lineage are not yet audited.", "scientific_consequence": "The combined file cannot establish common-scale validity or canonical transformations.", "provisional_action": "Use only for later reconciliation after wave-specific results; defer inherited-code inspection."},
        {"issue_id": "Y3-B014", "status": "open", "severity": "critical", "area": "item selection", "issue": "Treatment assignment must remain blind during initial item screening.", "scientific_consequence": "Selecting items on estimated treatment effects can mechanically bias impact estimates.", "provisional_action": "Exclude treatment fields from selection files and decision rules; treatment DIF only as later sensitivity."},
    ]


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--github-root", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()

    paths = read_simple_paths(args.config.resolve())
    y3_root = paths["y3_root"]
    work_root = paths["work_root"]
    github_root = args.github_root.resolve()
    source_roots = [paths["y1_root"], paths["y2_root"], y3_root]
    out_dir = assert_output_path(args.out_dir, work_root, source_roots)

    rows: list[RegistryRow] = []
    missing: list[str] = []
    for index, path in enumerate(registry_candidates(y3_root, github_root), start=1):
        if not path.exists():
            missing.append(str(path))
            continue
        if path.is_relative_to(y3_root):
            assert_source_path(path, source_roots)
        reason = excluded_reason(path)
        root_alias, relative, wave, family, role = classify(path, y3_root, github_root)
        stat = path.stat()
        status = "excluded" if reason else "candidate"
        canonical = "not_candidate" if reason else "requires_collaborator_confirmation"
        rows.append(
            RegistryRow(
                source_id=f"Y3S-{index:04d}",
                root_alias=root_alias,
                relative_path=relative,
                wave=wave,
                source_role=role,
                source_family=family,
                extension=path.suffix.lower(),
                bytes=stat.st_size,
                modified_utc=datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
                sha256=sha256(path),
                candidate_status=status,
                exclusion_reason=reason,
                canonicality_status=canonical,
                notes="",
            )
        )

    registry_dicts = [asdict(row) for row in rows]
    registry_path = out_dir / "y3_source_registry.csv"
    write_csv(registry_path, registry_dicts, list(RegistryRow.__annotations__.keys()))
    issues = blocking_issues()
    issue_path = out_dir / "y3_blocking_issues.csv"
    write_csv(issue_path, issues, list(issues[0].keys()))

    summary = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "registry_rows": len(rows),
        "candidate_rows": sum(row.candidate_status == "candidate" for row in rows),
        "excluded_rows": sum(row.candidate_status == "excluded" for row in rows),
        "missing_expected_paths": missing,
        "sha256_duplicate_groups": {},
        "blocking_issue_count": len(issues),
    }
    by_hash: dict[str, list[str]] = {}
    for row in rows:
        by_hash.setdefault(row.sha256, []).append(row.source_id)
    summary["sha256_duplicate_groups"] = {
        digest: source_ids for digest, source_ids in by_hash.items() if len(source_ids) > 1
    }
    summary_path = out_dir / "y3_registry_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"registry": str(registry_path), "issues": str(issue_path), **summary}, ensure_ascii=False))


if __name__ == "__main__":
    main()
