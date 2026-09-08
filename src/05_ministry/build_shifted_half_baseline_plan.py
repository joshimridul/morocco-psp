#!/usr/bin/env python3
"""Build the half-length next-baseline plan on the agreed one-grade shift."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "00_inventory"))
from build_y3_registry import read_simple_paths  # noqa: E402
from path_guard import assert_output_path  # noqa: E402


COGNITIVE_LABELS = {
    "KNOWL": "Knowledge",
    "APPL": "Application",
    "REASON": "Reasoning",
    "COMP": "Comprehension",
    "SYNT": "Synthesis",
    "ANALYSE": "Analysis",
    "EVAL": "Evaluation",
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def clean(value: Any) -> str:
    return "" if value is None else str(value).strip()


def as_float(value: Any) -> float | None:
    try:
        result = float(clean(value))
    except ValueError:
        return None
    return result if math.isfinite(result) else None


def normalized_id(value: str) -> str:
    text = re.sub(r"[^a-z0-9]+", "", value.casefold())
    text = re.sub(r"y[123](?:nv|v)?[0-9]*$", "", text)
    return re.sub(r"(?:nv|v)[0-9]*$", "", text)


def canonical_domain(subject: str, value: str) -> str:
    text = re.sub(r"[^a-z0-9]+", " ", clean(value).casefold()).strip()
    compact = text.replace(" ", "")
    if subject in {"Arabic", "French"}:
        if compact in {"po", "productionoral"} or ("production" in text and "oral" in text):
            return "Oral production"
        if compact in {"pe", "productionecrit", "productionecrite"} or "writing" in text:
            return "Written production"
        if compact in {"lf", "lecturefluidite"} or any(word in text for word in ("decod", "fluid")):
            return "Decoding/fluency"
        if compact == "co" or ("comprehension" in text and "oral" in text):
            return "Oral comprehension"
        if compact == "lc" or "lecture" in text or "reading" in text:
            return "Reading comprehension"
    if subject == "Maths":
        if compact in {"gm", "geometricshapesandmeasures"} or any(word in text for word in ("geometr", "measure")):
            return "Geometry/measurement"
        if compact == "data" or "data" in text:
            return "Data"
        if compact == "rp" or "problem" in text:
            return "Problem solving"
        if "algebr" in text:
            return "Algebraic thinking"
        if compact in {"calcul", "numeracy", "calculnumeracy"} or any(word in text for word in ("calcul", "number", "numeracy")):
            return "Number/calculation"
    return clean(value) or "To confirm"


def tail_role(pct: float | None) -> str:
    if pct is None:
        return "unknown"
    if pct >= 70:
        return "easy"
    if pct <= 35:
        return "hard"
    return "middle"


def cognitive_label(value: str) -> str:
    text = clean(value)
    return COGNITIVE_LABELS.get(text.upper(), text or "To confirm")


def parse_repair_link(value: str) -> tuple[str, str, list[int]]:
    subject, rest = value.split(" G", 1)
    if "pre/post" in rest:
        grade = int(re.search(r"[1-6]", rest).group())
        return f"within_grade_pre_post|{subject}|{grade}", subject, [grade]
    grades = [int(value) for value in re.findall(r"[1-6]", rest)]
    return f"adjacent_grade_vertical|{subject}|{grades[0]}-{grades[1]}", subject, grades


def split_ids(value: str) -> list[str]:
    return [part.strip() for part in value.split(",") if part.strip() and part.strip() != "none"]


def candidate_rank(row: dict[str, str]) -> tuple[float, float, float, str]:
    tier = 2.0 if row["anchor_candidate_tier"] == "Tier A core candidate" else 1.0
    pbis_a = as_float(row["point_biserial_rest_a"]) or 0.0
    pbis_b = as_float(row["point_biserial_rest_b"]) or 0.0
    difference = abs(as_float(row["unconditional_p_difference"]) or 0.0)
    return (tier, min(pbis_a, pbis_b), -difference, row["item_id"])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    paths = read_simple_paths(args.config.resolve())
    work = paths["work_root"]
    roots = [paths["y1_root"], paths["y2_root"], paths["y3_root"]]

    shift = read_rows(work / "outputs/y3_ministry/03_forms/y3_one_grade_shift_map.csv")
    candidates = read_rows(work / "derived/y3_ministry/y3_anchor_candidate_evidence.csv")
    repairs = read_rows(work / "outputs/y3_ministry/03_forms/y3_minimal_anchor_repairs.csv")
    pilot = read_rows(work / "outputs/y3_ministry/03_forms/y3_pilot_item_bank.csv")
    historical = read_rows(work / "private_manifests/historical_bank_candidate_evidence.csv")
    decisions = read_rows(work / "outputs/y3_ministry/03_forms/y3_ministry_item_decisions.csv")

    forms: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for row in shift:
        subject = row["subject"]
        grade = int(row["target_baseline_grade"])
        enriched: dict[str, Any] = dict(row)
        enriched.update({
            "target_grade": grade,
            "content_domain": canonical_domain(subject, row["proposed_content_domain"]),
            "cognitive_domain": cognitive_label(row["proposed_cognitive_domain"]),
            "pct": as_float(row["source_pct_correct"]),
            "pbis": as_float(row["source_point_biserial_rest"]),
            "tail": tail_role(as_float(row["source_pct_correct"])),
            "source_type": f"Year 3 {row['source_wave']} Grade {row['source_administered_grade']}",
            "selected_anchor": False,
            "anchor_link": "",
            "anchor_version_status": "",
        })
        forms[(subject, grade)].append(enriched)

    candidate_by_link: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in candidates:
        if (
            row["prompt_hash_consistent"] == "1"
            and row["anchor_candidate_tier"] in {"Tier A core candidate", "Tier B expanded candidate"}
        ):
            candidate_by_link[row["link_id"]].append(row)
    repair_by_link = {parse_repair_link(row["link"])[0]: row for row in repairs}
    pilot_exact: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in pilot:
        if row["item_id"] != "TO BE SELECTED":
            pilot_exact[(row["subject"], row["item_id"])].append(row)
    historical_exact = {(row["subject"], row["candidate_id"]): row for row in historical}

    selected_anchor_specs: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    anchor_audit: list[dict[str, Any]] = []
    for subject in ("Arabic", "French", "Maths"):
        for target_grade in range(1, 7):
            if target_grade == 1:
                link_id = f"within_grade_pre_post|{subject}|1"
                endpoint_grades = "1"
            else:
                link_id = f"adjacent_grade_vertical|{subject}|{target_grade - 1}-{target_grade}"
                endpoint_grades = f"{target_grade - 1},{target_grade}"
            repair = repair_by_link.get(link_id)
            specs: list[tuple[str, str, str]] = []
            if repair:
                specs.extend((item_id, "current exact-version candidate", "repair retain") for item_id in split_ids(repair["retain_current_candidates"]))
                specs.extend((item_id, "historical exact source version", "repair addition") for item_id in split_ids(repair["add_from_historical_bank"]))
            else:
                ranked = sorted(candidate_by_link.get(link_id, []), key=candidate_rank, reverse=True)
                specs.extend((row["item_id"], "current exact-version candidate", row["anchor_candidate_tier"]) for row in ranked[:5])
            if len(specs) != 5:
                raise RuntimeError(f"{link_id} has {len(specs)} exact anchor specifications, expected 5")

            form_rows = forms[(subject, target_grade)]
            by_exact_id = {row["item_id"]: row for row in form_rows}
            for item_id, source_kind, basis in specs:
                if source_kind.startswith("current"):
                    source = by_exact_id.get(item_id)
                    if not source:
                        raise RuntimeError(f"Exact current anchor {item_id} absent from shifted pool {subject} G{target_grade}")
                    item = dict(source)
                    version_status = "Exact prompt-hash-consistent current version; full stimulus/options/key review pending"
                else:
                    pilot_rows = pilot_exact.get((subject, item_id), [])
                    pilot_row = pilot_rows[0] if pilot_rows else {}
                    hist = historical_exact.get((subject, item_id), {})
                    prompt = pilot_row.get("item_text") or hist.get("question_summary", "")
                    if not prompt:
                        raise RuntimeError(f"Historical anchor source text unresolved: {subject} {item_id}")
                    item = {
                        "subject": subject,
                        "target_grade": target_grade,
                        "target_baseline_grade": str(target_grade),
                        "source_wave": "historical",
                        "source_administered_grade": hist.get("grade_origin", ""),
                        "source_form_group": "historical bank",
                        "item_id": item_id,
                        "source_scto_question_id": "",
                        "source_question_number": "",
                        "question_summary": prompt,
                        "proposed_content_domain": hist.get("content_domain", ""),
                        "proposed_cognitive_domain": hist.get("cognitive_domain", ""),
                        "content_domain": canonical_domain(subject, hist.get("content_domain", "")),
                        "cognitive_domain": cognitive_label(hist.get("cognitive_domain", "")),
                        "item_type": "binary",
                        "pct": (as_float(hist.get("historical_p_correct")) or 0) * 100 if as_float(hist.get("historical_p_correct")) is not None and (as_float(hist.get("historical_p_correct")) or 0) <= 1 else as_float(hist.get("historical_p_correct")),
                        "pbis": as_float(hist.get("historical_itemrestcor")),
                        "source_empirical_quality_status": "historical candidate; target-grade pilot required",
                        "shift_recommendation": "Copy exact source version; pilot in target grade",
                        "source_type": f"Historical bank: {pilot_row.get('source_bank') or hist.get('historical_source', '')}",
                    }
                    item["tail"] = tail_role(item["pct"])
                    version_status = "Exact historical source version must be copied; full source-language fingerprint pending"
                item["selected_anchor"] = True
                item["anchor_link"] = link_id
                item["anchor_version_status"] = version_status
                selected_anchor_specs[(subject, target_grade)].append(item)
                anchor_audit.append({
                    "link_id": link_id,
                    "subject": subject,
                    "target_baseline_grade": target_grade,
                    "link_endpoint_grades": endpoint_grades,
                    "item_id": item_id,
                    "source_kind": source_kind,
                    "selection_basis": basis,
                    "version_status": version_status,
                })

    decision_lookup = {
        (row["subject"], int(row["administered_grade"]), row["item_id"]): row for row in decisions
    }
    selected_plan: list[dict[str, Any]] = []
    log_rows: list[dict[str, Any]] = []
    summary_rows: list[dict[str, Any]] = []

    for form_key in sorted(forms):
        subject, grade = form_key
        source_rows = forms[form_key]
        target_n = math.ceil(len(source_rows) * 0.5)
        selected: dict[str, dict[str, Any]] = {}
        for anchor in selected_anchor_specs[form_key]:
            selected[f"anchor|{anchor['item_id']}"] = anchor

        pool = [row for row in source_rows if row["item_type"] == "binary"]
        anchor_exact_ids = {
            row["item_id"] for row in selected.values()
            if row["source_wave"] != "historical"
        }
        pool = [row for row in pool if row["item_id"] not in anchor_exact_ids]

        available_domains = {row["content_domain"] for row in pool if row["content_domain"] != "To confirm"}
        available_cognitive = {row["cognitive_domain"] for row in pool if row["cognitive_domain"] != "To confirm"}

        def selected_counts(field: str) -> Counter[str]:
            return Counter(clean(row.get(field)) or "Unclassified" for row in selected.values())

        def priority(row: dict[str, Any]) -> float:
            pbis = row["pbis"] or 0.0
            pct = row["pct"]
            score = 20 * pbis
            quality = row["source_empirical_quality_status"].casefold()
            if "no empirical warning" in quality:
                score += 5
            elif "multiple warnings" in quality:
                score -= 4
            domain_counts = selected_counts("content_domain")
            cognitive_counts = selected_counts("cognitive_domain")
            tail_counts = selected_counts("tail")
            if row["content_domain"] in available_domains and domain_counts[row["content_domain"]] < 2:
                score += 12
            if row["cognitive_domain"] in available_cognitive and cognitive_counts[row["cognitive_domain"]] == 0:
                score += 6
            if row["tail"] in {"easy", "hard"} and tail_counts[row["tail"]] < 2:
                score += 10
            if pct is None:
                score -= 2
            return score

        while len(selected) < target_n and pool:
            best = max(pool, key=lambda row: (priority(row), row["item_id"]))
            selected[f"current|{best['item_id']}"] = best
            pool.remove(best)
        if len(selected) != target_n:
            raise RuntimeError(f"Unable to fill {subject} G{grade}: {len(selected)}/{target_n}")

        ordered = sorted(
            selected.values(),
            key=lambda row: (
                1 if row["source_wave"] == "historical" else 0,
                float(row["source_question_number"]) if clean(row.get("source_question_number")).replace(".", "", 1).isdigit() else 9999,
                row["item_id"],
            ),
        )
        for number, row in enumerate(ordered, start=1):
            selected_plan.append({
                "subject": subject,
                "baseline_grade": grade,
                "baseline_item_no": number,
                "item_id": row["item_id"],
                "selected_anchor": "1" if row.get("selected_anchor") else "0",
                "anchor_link": row.get("anchor_link", ""),
                "anchor_version_status": row.get("anchor_version_status", ""),
                "source_wave": row["source_wave"],
                "source_grade": row.get("source_administered_grade", ""),
                "source_question_number": row.get("source_question_number", ""),
                "source": row["source_type"],
                "item_or_summary": row["question_summary"],
                "content_domain": row["content_domain"],
                "cognitive_domain": row["cognitive_domain"],
                "tail_role": row["tail"],
                "source_pct_correct": "" if row["pct"] is None else round(row["pct"], 3),
                "source_point_biserial_rest": "" if row["pbis"] is None else round(row["pbis"], 3),
                "selection_reason": (
                    f"Selected as the exact-version anchor for {row['anchor_link']}; keep unchanged."
                    if row.get("selected_anchor")
                    else "Selected after fixing anchors to preserve domain, cognitive, tail and discrimination coverage within the half-length limit."
                ),
            })

        selected_source_ids = {
            row["item_id"] for row in ordered if row["source_wave"] != "historical"
        }
        for row in source_rows:
            chosen = row["item_id"] in selected_source_ids
            decision = decision_lookup.get((subject, int(row["source_administered_grade"]), row["item_id"]), {}) if row["source_wave"] == "endline" else {}
            if chosen:
                reason = next(
                    item["selection_reason"] for item in selected_plan
                    if item["subject"] == subject
                    and item["baseline_grade"] == grade
                    and item["item_id"] == row["item_id"]
                )
            elif row["item_type"] != "binary":
                reason = (
                    "Not selected as an independent binary item; retain it only with its "
                    "fluency/rubric bundle and finalize that scoring decision during assembly."
                )
            else:
                reason = (
                    "Not selected: the half-length form was filled by stronger or more necessary "
                    "items after fixing exact-version anchors."
                )
            log_rows.append({
                "candidate_type": "official shifted source pool",
                "subject": subject,
                "baseline_grade": grade,
                "source_wave": row["source_wave"],
                "source_grade": row["source_administered_grade"],
                "item_id": row["item_id"],
                "question_summary": row["question_summary"],
                "selected": "YES" if chosen else "NO",
                "selected_anchor": "YES" if chosen and any(a["item_id"] == row["item_id"] and a["source_wave"] != "historical" for a in selected_anchor_specs[form_key]) else "",
                "anchor_link": next((a["anchor_link"] for a in selected_anchor_specs[form_key] if a["item_id"] == row["item_id"] and a["source_wave"] != "historical"), ""),
                "content_domain": row["content_domain"],
                "cognitive_domain": row["cognitive_domain"],
                "tail_role": row["tail"],
                "pct_correct": row["source_pct_correct"],
                "point_biserial_rest": row["source_point_biserial_rest"],
                "discrimination_a": decision.get("discrimination_a", ""),
                "difficulty_b": decision.get("difficulty_b", ""),
                "decision_reason": reason,
                "version_status": "Current official shifted source row",
                "source_reference": row["source_type"],
            })
        for anchor in selected_anchor_specs[form_key]:
            if anchor["source_wave"] != "historical":
                continue
            log_rows.append({
                "candidate_type": "historical anchor repair",
                "subject": subject,
                "baseline_grade": grade,
                "source_wave": "historical",
                "source_grade": anchor.get("source_administered_grade", ""),
                "item_id": anchor["item_id"],
                "question_summary": anchor["question_summary"],
                "selected": "YES",
                "selected_anchor": "YES",
                "anchor_link": anchor["anchor_link"],
                "content_domain": anchor["content_domain"],
                "cognitive_domain": anchor["cognitive_domain"],
                "tail_role": anchor["tail"],
                "pct_correct": "" if anchor["pct"] is None else anchor["pct"],
                "point_biserial_rest": "" if anchor["pbis"] is None else anchor["pbis"],
                "discrimination_a": "",
                "difficulty_b": "",
                "decision_reason": f"Selected as the exact historical source version for {anchor['anchor_link']}; copy this version unchanged rather than any local same-base-ID item.",
                "version_status": anchor["anchor_version_status"],
                "source_reference": anchor["source_type"],
            })

        selected_form = [row for row in selected_plan if row["subject"] == subject and row["baseline_grade"] == grade]
        tails = Counter(row["tail_role"] for row in selected_form)
        summary_rows.append({
            "subject": subject,
            "baseline_grade": grade,
            "official_shifted_pool_n": len(source_rows),
            "selected_n": len(selected_form),
            "selected_share_pct": round(100 * len(selected_form) / len(source_rows), 1),
            "selected_anchor_n": sum(row["selected_anchor"] == "1" for row in selected_form),
            "easy_n": tails["easy"],
            "hard_n": tails["hard"],
            "content_domain_n": len({row["content_domain"] for row in selected_form if row["content_domain"] != "To confirm"}),
            "cognitive_domain_n": len({row["cognitive_domain"] for row in selected_form if row["cognitive_domain"] != "To confirm"}),
            "source_rule": "prior baseline G1" if grade == 1 else f"prior endline G{grade - 1}",
        })

    selected_historical = {
        (row["subject"], row["item_id"])
        for row in selected_plan if row["source_wave"] == "historical"
    }
    for row in historical:
        if (row["subject"], row["candidate_id"]) in selected_historical:
            continue
        log_rows.append({
            "candidate_type": "unselected historical bank candidate",
            "subject": row["subject"],
            "baseline_grade": "",
            "source_wave": "historical",
            "source_grade": row["grade_origin"],
            "item_id": row["candidate_id"],
            "question_summary": row["question_summary"],
            "selected": "NO",
            "selected_anchor": "",
            "anchor_link": "",
            "content_domain": canonical_domain(row["subject"], row["content_domain"]),
            "cognitive_domain": cognitive_label(row["cognitive_domain"]),
            "tail_role": row["tail_role"],
            "pct_correct": row["historical_p_correct"],
            "point_biserial_rest": row["historical_itemrestcor"],
            "discrimination_a": row["historical_discrimination_a"],
            "difficulty_b": row["historical_difficulty_b"],
            "decision_reason": (
                "Not selected for this minimum baseline: it was not needed for an exact-version "
                "anchor repair after the official shifted source pools were reduced to half length."
            ),
            "version_status": row["version_review_status"],
            "source_reference": row["historical_source"],
        })

    output_dir = work / "outputs/y3_ministry/05_short_form/shifted_baseline"
    plan_path = assert_output_path(output_dir / "shifted_half_baseline_item_plan.csv", work, roots)
    log_path = assert_output_path(output_dir / "shifted_half_baseline_selection_log.csv", work, roots)
    anchor_path = assert_output_path(output_dir / "shifted_half_baseline_anchor_audit.csv", work, roots)
    summary_path = assert_output_path(output_dir / "shifted_half_baseline_summary.csv", work, roots)
    notes_path = assert_output_path(output_dir / "shifted_half_baseline_notes.json", work, roots)
    write_rows(plan_path, selected_plan, list(selected_plan[0]))
    write_rows(log_path, log_rows, list(log_rows[0]))
    write_rows(anchor_path, anchor_audit, list(anchor_audit[0]))
    write_rows(summary_path, summary_rows, list(summary_rows[0]))
    notes = {
        "status": "draft selection map; not a final assembled instrument",
        "grade_shift": "Baseline G1 uses prior baseline G1; baseline G2-G6 use prior endline G1-G5.",
        "anchor_rule": "Five exact-version candidates per required baseline-to-endline link. Historical repairs always use the specified source-bank version, never a local same-base-ID item.",
        "bundle_blocker": "Passage, image, oral-task and rubric bundles must be confirmed during booklet assembly.",
        "key_blocker": "Source-language answers/scoring remain to be tied to the selected rows from canonical examiner guides.",
        "selected_rows": len(selected_plan),
        "anchor_rows": len(anchor_audit),
    }
    notes_path.write_text(json.dumps(notes, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({**notes, "outputs": [str(plan_path), str(log_path), str(anchor_path), str(summary_path)]}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
