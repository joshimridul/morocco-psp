"""Path-boundary and identifier-output guards for the Morocco assessment audit."""

from __future__ import annotations

from pathlib import Path
from typing import Iterable


DIRECT_IDENTIFIER_PATTERNS = (
    "massar",
    "student_name",
    "studentname",
    "nom_eleve",
    "prenom_eleve",
    "national_id",
    "cin",
    "phone",
    "telephone",
    "email",
    "address",
    "adresse",
)

DIRECT_IDENTIFIER_EXACT_NAMES = {
    "id_student_panel",
    "student_id",
    "studentid",
    "school_id",
    "schoolid",
    "cd_etab",
    "gresa",
}


def resolved(path: str | Path) -> Path:
    return Path(path).expanduser().resolve(strict=False)


def is_within(path: str | Path, root: str | Path) -> bool:
    candidate = resolved(path)
    boundary = resolved(root)
    return candidate == boundary or boundary in candidate.parents


def assert_source_path(path: str | Path, source_roots: Iterable[str | Path]) -> Path:
    candidate = resolved(path)
    if not candidate.exists():
        raise FileNotFoundError(candidate)
    if not any(is_within(candidate, root) for root in source_roots):
        raise ValueError(f"Input is outside approved legacy roots: {candidate}")
    return candidate


def assert_output_path(
    path: str | Path,
    work_root: str | Path,
    source_roots: Iterable[str | Path],
    inputs: Iterable[str | Path] = (),
) -> Path:
    candidate = resolved(path)
    if not is_within(candidate, work_root) or candidate == resolved(work_root):
        raise ValueError(f"Output must be below the dedicated work root: {candidate}")
    # A project-lead-approved work root may itself be nested below a legacy
    # root. In that case, only the explicitly configured work-root subtree is
    # writable; the leading containment check still rejects every sibling,
    # parent, and other location below the legacy root.
    if any(
        is_within(candidate, root) and not is_within(work_root, root)
        for root in source_roots
    ):
        raise ValueError(f"Output resolves inside a legacy root: {candidate}")
    if any(candidate == resolved(input_path) for input_path in inputs):
        raise ValueError(f"Output equals an input path: {candidate}")
    return candidate


def assert_no_direct_identifier_columns(columns: Iterable[str]) -> None:
    unsafe = []
    for column in columns:
        normalized = str(column).strip().lower()
        if (
            normalized in DIRECT_IDENTIFIER_EXACT_NAMES
            or any(pattern in normalized for pattern in DIRECT_IDENTIFIER_PATTERNS)
        ):
            unsafe.append(str(column))
    if unsafe:
        raise ValueError(f"Direct-identifier-like columns are not exportable: {sorted(unsafe)}")
