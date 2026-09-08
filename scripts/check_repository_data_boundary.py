#!/usr/bin/env python3
"""Fail if staged or tracked files cross the GitHub/Dropbox data boundary."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
BLOCKED_DIRECTORY_NAMES = {
    "data",
    "derived",
    "local",
    "logs",
    "outputs",
    "private",
    "scratch",
    "tmp",
}
BLOCKED_DATA_SUFFIXES = {
    ".arrow",
    ".dta",
    ".feather",
    ".parquet",
    ".rdata",
    ".rds",
    ".sas7bdat",
    ".sav",
    ".ster",
}
STRUCTURED_DATA_SUFFIXES = {".csv", ".jsonl", ".tsv", ".xls", ".xlsx"}
ALLOWED_STRUCTURED_FILES = {
    "docs/DATA_DICTIONARY_TEMPLATE.csv",
    "docs/ITEM_BANK_TEMPLATE.csv",
    "docs/SAMPLE_FORM_REGISTRY_TEMPLATE.csv",
    "docs/SOURCE_REGISTRY_TEMPLATE.csv",
    # The project lead explicitly approved these item maps for the private repo.
    "exchange-with-ministry/received-from-ministry/Endline item map_from_btihaj.xlsx",
    "exchange-with-ministry/sent-to-ministry/Baseline item map.xlsx",
    "exchange-with-ministry/sent-to-ministry/Endline item map.xlsx",
}
ALLOWED_BOUNDARY_MARKERS = {"data/README.md"}


def git_paths(staged: bool) -> list[str]:
    command = (
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"]
        if staged
        else ["git", "ls-files", "-z"]
    )
    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [path for path in result.stdout.decode("utf-8").split("\0") if path]


def violation(path_text: str) -> str | None:
    path = Path(path_text)
    if path_text in ALLOWED_BOUNDARY_MARKERS:
        return None
    if any(part.lower() in BLOCKED_DIRECTORY_NAMES for part in path.parts[:-1]):
        return "generated or data-bearing directory"
    suffix = path.suffix.lower()
    if suffix in BLOCKED_DATA_SUFFIXES:
        return f"blocked data-file extension {suffix}"
    if suffix in STRUCTURED_DATA_SUFFIXES and path_text not in ALLOWED_STRUCTURED_FILES:
        return "structured data file is not an approved template or item map"
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--all-tracked",
        action="store_true",
        help="scan every tracked file instead of staged additions and modifications",
    )
    args = parser.parse_args()
    violations = [
        (path, reason)
        for path in git_paths(staged=not args.all_tracked)
        if (reason := violation(path)) is not None
    ]
    if violations:
        print("Repository data-boundary check failed:", file=sys.stderr)
        for path, reason in violations:
            print(f"  {path}: {reason}", file=sys.stderr)
        print(
            "Move data-bearing outputs to the configured Dropbox work_root. "
            "Do not bypass this check for raw or student-level data.",
            file=sys.stderr,
        )
        return 1
    scope = "tracked files" if args.all_tracked else "staged additions and modifications"
    print(f"Repository data-boundary check passed for {scope}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
