#!/usr/bin/env python3
"""Assemble item decisions, one-grade shift map, French redesign brief, and advice."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "00_inventory"))
from build_y3_registry import read_simple_paths  # noqa: E402
from path_guard import assert_output_path  # noqa: E402


TIER_RANK = {
    "Tier A core candidate": 4,
    "Tier B expanded candidate": 3,
    "reserve: requires review": 2,
    "not eligible empirically": 1,
    "not eligible: prompt-summary mismatch": 0,
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, rows: list[dict[str, Any]], fields: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = fields or list(rows[0].keys())
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def as_float(value: str) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def flag(row: dict[str, str], field: str) -> bool:
    return row.get(field, "") == "1"


def best_anchor(records: list[dict[str, str]]) -> tuple[str, str, str]:
    if not records:
        return "no empirical anchor role", "", ""
    best = max(records, key=lambda row: TIER_RANK.get(row["anchor_candidate_tier"], -1))
    eligible = [
        row for row in records if row["anchor_candidate_tier"] in {
            "Tier A core candidate", "Tier B expanded candidate", "reserve: requires review"
        }
    ]
    return (
        best["anchor_candidate_tier"],
        ";".join(sorted({row["link_type"] for row in eligible})),
        ";".join(sorted({row["link_id"] for row in eligible})),
    )


def recommendation(evidence: dict[str, str], item_type: str, anchor_tier: str) -> tuple[str, str, str]:
    if item_type != "binary":
        return (
            "diagnostic/separate fluency or rubric measure",
            "requires scoring/rubric and category-function review",
            "Nonbinary field is not commensurate with the dichotomous IRT scale and must be reported or modeled separately.",
        )
    if anchor_tier == "Tier A core candidate":
        return (
            "provisional anchor—freeze unchanged",
            "moderate pending full-version/exposure review",
            "Strong treatment-blind endpoint behavior and no material DIF warning for at least one intended link.",
        )
    if anchor_tier == "Tier B expanded candidate":
        return (
            "reserve anchor—freeze unchanged pending review",
            "moderate-low pending full-version/exposure review",
            "Empirically eligible as an expanded anchor, but below the core evidence tier.",
        )
    if flag(evidence, "negative_discrimination_warning") or flag(evidence, "severe_facility_warning"):
        return (
            "replace/retire candidate",
            "high empirical concern; substantive review required",
            "Severe facility or negative item-rest relationship makes unchanged reuse hard to defend.",
        )
    if flag(evidence, "low_discrimination_warning") or flag(evidence, "extreme_facility_warning"):
        return (
            "revise or replace, then re-pilot",
            "moderate-high empirical concern",
            "The item is too extreme or weakly related to the rest score for its present operational role.",
        )
    if flag(evidence, "nonresponse_warning"):
        return (
            "revise administration/wording/scoring, then re-pilot",
            "moderate empirical concern",
            "Don't-know plus blank nonresponse exceeds the review threshold; investigate administration, targeting, and scoring.",
        )
    if flag(evidence, "irt_item_fit_warning") or flag(evidence, "split_stability_warning"):
        return (
            "retain only after psychometric review and re-pilot",
            "moderate empirical concern",
            "Item fit or school-split parameter stability raises a replicability warning.",
        )
    if flag(evidence, "local_dependence_item_warning"):
        return (
            "retain as scored non-anchor; preserve task/testlet bundle",
            "moderate",
            "Item behavior is acceptable individually, but residual dependence requires explicit stimulus/testlet treatment.",
        )
    return (
        "retain as scored non-anchor",
        "moderate pending substantive/version review",
        "No major treatment-blind empirical warning; anchor eligibility remains link-specific and version-dependent.",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    paths = read_simple_paths(args.config.resolve())
    work = paths["work_root"]
    roots = [paths["y1_root"], paths["y2_root"], paths["y3_root"]]

    domains = read_rows(work / "outputs/y3_ministry/03_forms/y3_completed_domain_map.csv")
    evidence_rows = read_rows(work / "derived/y3_ministry/y3_item_decision_evidence.csv")
    evidence = {
        (row["wave"], row["subject"], row["grade"], row["item_id"]): row for row in evidence_rows
    }
    operational = read_rows(work / "derived/y3_ministry/y3_item_operational_stats.csv")
    operational_by_key = {
        (row["wave"], row["subject"], row["grade"], row["item_id"]): row for row in operational
    }
    anchors = read_rows(work / "derived/y3_ministry/y3_anchor_candidate_evidence.csv")
    anchor_by_endpoint: dict[tuple[str, str, str, str], list[dict[str, str]]] = defaultdict(list)
    for row in anchors:
        if row["wave_a"] == "endline":
            anchor_by_endpoint[("endline", row["subject"], row["grade_a"], row["item_id"])].append(row)
        if row["wave_b"] == "endline":
            anchor_by_endpoint[("endline", row["subject"], row["grade_b"], row["item_id"])].append(row)

    decisions: list[dict[str, Any]] = []
    for row in domains:
        key = ("endline", row["subject"], row["form_grade"], row["item_id"])
        empirical = evidence.get(key, {})
        operation = operational_by_key.get(key, {})
        item_type = operation.get("item_type", "not observed")
        anchor_tier, anchor_roles, anchor_links = best_anchor(anchor_by_endpoint.get(key, []))
        rec, confidence, rationale = recommendation(empirical, item_type, anchor_tier)
        decisions.append(
            {
                "subject": row["subject"],
                "administered_grade": row["form_grade"],
                "form_group": row["form_group"],
                "item_id": row["item_id"],
                "scto_question_id": row["scto_question_id"],
                "question_number": row["question_number"],
                "question_summary": row["question_summary"],
                "grade_origin": row["grade_origin"],
                "proposed_content_domain": row["proposed_content_domain"],
                "proposed_cognitive_domain": row["proposed_cognitive_domain"],
                "domain_completion_source": row["domain_completion_source"],
                "domain_confirmation_required": row["requires_ministry_confirmation"],
                "item_type": item_type,
                "n_form": operation.get("n_form", ""),
                "pct_correct": operation.get("pct_correct", ""),
                "pct_dont_know": operation.get("pct_dont_know", ""),
                "pct_missing": operation.get("pct_missing", ""),
                "point_biserial_rest": operation.get("point_biserial_rest", ""),
                "irt_model_type": empirical.get("irt_model_type", ""),
                "discrimination_a": empirical.get("discrimination_a", ""),
                "difficulty_b": empirical.get("difficulty_b", ""),
                "empirical_quality_status": empirical.get("empirical_quality_status", "not modeled as binary"),
                "empirical_warning_count": empirical.get("empirical_warning_count", ""),
                "local_dependence_warning": empirical.get("local_dependence_item_warning", ""),
                "school_split_warning": empirical.get("split_stability_warning", ""),
                "existing_map_anchor_flag": row["map_anchor_flag"],
                "best_empirical_anchor_tier": anchor_tier,
                "eligible_anchor_roles": anchor_roles,
                "eligible_anchor_link_ids": anchor_links,
                "full_version_review_status": "required: prompt/stimulus/options/key-rubric/layout/administration/scoring/exposure",
                "substantive_necessity_status": "requires Ministry/curriculum blueprint judgment",
                "provisional_recommendation": rec,
                "recommendation_confidence": confidence,
                "recommendation_rationale": rationale,
                "final_approval_status": "not final until Ministry content and full-version review",
            }
        )

    decision_path = assert_output_path(
        work / "outputs/y3_ministry/03_forms/y3_ministry_item_decisions.csv", work, roots
    )
    write_rows(decision_path, decisions)

    private_registry = read_rows(work / "private_manifests/y3_item_version_registry_private.csv")
    domain_by_endline_key = {
        (row["subject"], row["form_grade"], row["item_id"]): row for row in domains
    }
    consistent_domain_by_item: dict[tuple[str, str], tuple[str, str]] = {}
    grouped: dict[tuple[str, str], set[tuple[str, str]]] = defaultdict(set)
    for row in domains:
        grouped[(row["subject"], row["item_id"])].add(
            (row["proposed_content_domain"], row["proposed_cognitive_domain"])
        )
    for key, pairs in grouped.items():
        if len(pairs) == 1:
            consistent_domain_by_item[key] = next(iter(pairs))

    shift_rows: list[dict[str, Any]] = []
    for target_grade in range(1, 7):
        source_wave = "baseline" if target_grade == 1 else "endline"
        source_grade = 1 if target_grade == 1 else target_grade - 1
        for source in private_registry:
            if source["wave"] != source_wave or source["form_grade"] != str(source_grade):
                continue
            key = (source_wave, source["subject"], str(source_grade), source["item_id"])
            empirical = evidence.get(key, {})
            operation = operational_by_key.get(key, {})
            item_type = operation.get("item_type", "not observed")
            if source_wave == "endline":
                domain = domain_by_endline_key.get((source["subject"], str(source_grade), source["item_id"]), {})
                content = domain.get("proposed_content_domain", "")
                cognitive = domain.get("proposed_cognitive_domain", "")
                domain_source = domain.get("domain_completion_source", "")
            else:
                pair = consistent_domain_by_item.get((source["subject"], source["item_id"]), ("", ""))
                content, cognitive = pair
                domain_source = "same item in completed endline map" if pair[0] and pair[1] else "baseline Grade 1 domain confirmation required"

            if item_type != "binary":
                shift_rec = "carry only as separate fluency/rubric component after scoring review"
            elif flag(empirical, "negative_discrimination_warning") or flag(empirical, "severe_facility_warning"):
                shift_rec = "do not shift unchanged; replace or substantively redesign"
            elif flag(empirical, "low_discrimination_warning") or flag(empirical, "extreme_facility_warning"):
                shift_rec = "revise or replace before target-grade pilot"
            elif flag(empirical, "nonresponse_warning"):
                shift_rec = "shift only after wording/administration review and target-grade pilot"
            else:
                source_p = as_float(operation.get("pct_correct", ""))
                shift_rec = (
                    "carry provisionally but expect ease at target grade; pilot targeting"
                    if source_p is not None and source_p >= 80
                    else "carry provisionally and re-pilot at target grade"
                )

            shift_rows.append(
                {
                    "subject": source["subject"],
                    "target_baseline_grade": target_grade,
                    "source_wave": source_wave,
                    "source_administered_grade": source_grade,
                    "source_form_group": source["form_group"],
                    "item_id": source["item_id"],
                    "source_scto_question_id": source["scto_question_id"],
                    "source_question_number": source["question_number"],
                    "question_summary": source["question_summary"],
                    "grade_origin": source["grade_origin"],
                    "proposed_content_domain": content,
                    "proposed_cognitive_domain": cognitive,
                    "domain_source": domain_source,
                    "item_type": item_type,
                    "source_pct_correct": operation.get("pct_correct", ""),
                    "source_point_biserial_rest": operation.get("point_biserial_rest", ""),
                    "source_empirical_quality_status": empirical.get("empirical_quality_status", ""),
                    "shift_recommendation": shift_rec,
                    "target_form_status": "proposed mapping; target-grade pilot and Ministry blueprint approval required",
                    "new_target_scto_id": "to be assigned after form assembly",
                }
            )

    shift_path = assert_output_path(
        work / "outputs/y3_ministry/03_forms/y3_one_grade_shift_map.csv", work, roots
    )
    write_rows(shift_path, shift_rows)

    link_coverage = read_rows(work / "outputs/y3_ministry/02_anchors/y3_anchor_link_coverage.csv")
    french_decisions = [row for row in decisions if row["subject"] == "French"]
    french_rows: list[dict[str, Any]] = []
    for grade in range(1, 7):
        items = [row for row in french_decisions if row["administered_grade"] == str(grade)]
        links = [
            row for row in link_coverage
            if row["subject"] == "French" and (row["grade_a"] == str(grade) or row["grade_b"] == str(grade))
        ]
        french_rows.append(
            {
                "grade": grade,
                "current_form_group": ",".join(sorted({row["form_group"] for row in items})),
                "current_item_n": len(items),
                "tier_a_anchor_item_n": sum(row["best_empirical_anchor_tier"] == "Tier A core candidate" for row in items),
                "tier_b_anchor_item_n": sum(row["best_empirical_anchor_tier"] == "Tier B expanded candidate" for row in items),
                "revision_or_replacement_item_n": sum(
                    row["provisional_recommendation"].startswith(("revise", "replace", "retain only")) for row in items
                ),
                "connected_link_count": len(links),
                "links_with_at_least_5_candidates": sum(
                    row["preliminary_coverage_status"] == "at least 5 core/expanded candidates" for row in links
                ),
                "recommended_form_design": "create a distinct grade-specific operational form; retain only controlled bridge anchors to adjacent grades and pre/post",
                "blueprint_status": "preserve content/cognitive coverage provisionally; Ministry must approve grade-specific targets",
                "anchor_freeze_rule": "do not edit prompt, stimulus, options, key/rubric, layout, scoring, or administration for retained anchors",
            }
        )
    french_path = assert_output_path(
        work / "outputs/y3_ministry/03_forms/y3_french_grade_specific_redesign.csv", work, roots
    )
    write_rows(french_path, french_rows)

    advice = [
        (1, "Freeze anchors by link, not globally", "Use separate pre/post, adjacent-grade, and trend anchor sets; version-lock every component and retain reserve sets."),
        (2, "Repair disconnected and weak links", "Retain eligible current anchors and add only enough unchanged, content-balanced bank items to reach five pilot candidates per deficient link."),
        (3, "Create six French forms", "Replace shared N23 and N456 operational forms with grade-specific blueprints while keeping a controlled bridge subset."),
        (4, "Add stimulus/testlet/rubric IDs", "Map every passage, image, oral task, and rubric criterion; model or score dependent bundles jointly."),
        (5, "Finish domain adjudication", "Review the 101 inherited/rule-completed rows and approve a controlled bilingual taxonomy and grade-specific blueprint weights."),
        (6, "Verify keys and reconstruct every score", "Tie each response field to the final key/rubric and form version; retain automated tie-out tests."),
        (7, "Pilot at the target grade", "A one-grade shift changes targeting. Pilot by school with enough pupils per form for CTT and pre-specified IRT fallback rules."),
        (8, "Treat oral/fluency fields separately", "Define units, caps, timing, rubric categories, rater training, and agreement; do not mix count fields into dichotomous IRT."),
        (9, "Use content-balanced anchor sets", "Do not choose only the statistically cleanest narrow items; cover domains, difficulty, tasks, and independent stimuli."),
        (10, "Keep item selection treatment-blind", "Freeze scoring and anchors before any treatment-related DIF sensitivity analysis."),
        (11, "Control exposure and revisions", "Maintain an exposure/change log and retire compromised items even when historical statistics are strong."),
        (12, "Revalidate after form assembly", "Re-estimate reliability, information, dimensionality, local dependence, and link constants on the assembled forms and school-held-out samples."),
    ]
    advice_rows = [
        {"priority": priority, "recommendation": title, "implementation": detail}
        for priority, title, detail in advice
    ]
    advice_path = assert_output_path(
        work / "outputs/y3_ministry/03_forms/y3_instrument_advice.csv", work, roots
    )
    write_rows(advice_path, advice_rows)

    summary = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "endline_item_form_decision_rows": len(decisions),
        "decision_counts": Counter(row["provisional_recommendation"] for row in decisions),
        "one_grade_shift_rows": len(shift_rows),
        "shift_recommendation_counts": Counter(row["shift_recommendation"] for row in shift_rows),
        "french_grade_design_rows": len(french_rows),
        "advice_items": len(advice_rows),
        "decision_boundary": "Recommendations are empirical/provisional. Ministry curriculum necessity, full item-version equivalence, exposure, scoring, and blueprint approval remain separate required judgments.",
    }
    summary_path = assert_output_path(
        work / "outputs/y3_ministry/03_forms/y3_ministry_decision_summary.json", work, roots
    )
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False, default=dict), encoding="utf-8")
    print(json.dumps({
        "decisions": str(decision_path), "shift_map": str(shift_path), "french_redesign": str(french_path),
        "advice": str(advice_path), **summary
    }, ensure_ascii=False, default=dict))


if __name__ == "__main__":
    main()
