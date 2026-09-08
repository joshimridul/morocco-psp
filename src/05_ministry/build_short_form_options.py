#!/usr/bin/env python3
"""Build provisional emergency short-form options for the next baseline.

The script uses only protected, already-produced Year 3 diagnostic outputs.  It
distinguishes a selected link-specific anchor set from the much larger pool of
empirically eligible anchor candidates, then fills each form to roughly half
length while protecting broad domain and difficulty coverage.

No item text or response data are written to GitHub.  All data-bearing outputs
are written below the configured protected work_root.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "00_inventory"))
from build_y3_registry import read_simple_paths  # noqa: E402
from path_guard import assert_output_path  # noqa: E402


TARGET_ANCHORS_PER_LINK = 5
TARGET_LENGTH_SHARE = 0.50
MIN_ITEMS_PER_BROAD_DOMAIN = 2
MIN_ITEMS_PER_TAIL = 2


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
    text = re.sub(r"[^a-z0-9]+", " ", value.casefold()).strip()
    compact = text.replace(" ", "")
    if subject in {"Arabic", "French"}:
        if compact in {"po", "productionoral"} or ("production" in text and "oral" in text):
            return "Oral production"
        if compact in {"pe", "productionecrit", "productionecrite"} or (
            "production" in text and ("ecrit" in text or "writing" in text)
        ):
            return "Written production"
        if compact in {"lf", "lecturefluidite"} or any(word in text for word in ("decod", "fluid", "letter", "word reading")):
            return "Decoding/fluency"
        if compact == "co" or ("comprehension" in text and "oral" in text):
            return "Oral comprehension"
        if compact == "lc" or "lecture" in text or "comprehension" in text or "reading" in text:
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
    return clean(value) or "Unclassified"


def tail_role(pct_correct: float | None) -> str:
    if pct_correct is None:
        return "unknown"
    if pct_correct >= 70:
        return "easy"
    if pct_correct <= 35:
        return "hard"
    return "middle"


def item_information(a: float | None, b: float | None, theta: float) -> float:
    if a is None or b is None or a <= 0:
        return 0.0
    exponent = max(-35.0, min(35.0, a * (theta - b)))
    p = 1.0 / (1.0 + math.exp(-exponent))
    return a * a * p * (1.0 - p)


def mean_information(row: dict[str, Any]) -> float:
    a = as_float(row.get("discrimination_a"))
    b = as_float(row.get("difficulty_b"))
    return sum(item_information(a, b, theta) for theta in (-2, -1, 0, 1, 2)) / 5


def parse_repair_link(value: str) -> tuple[str, str]:
    subject, remainder = value.split(" G", 1)
    if "pre/post" in remainder:
        grade = re.search(r"([1-6])", remainder).group(1)
        return f"within_grade_pre_post|{subject}|{grade}", subject
    grades = re.findall(r"[1-6]", remainder)
    return f"adjacent_grade_vertical|{subject}|{grades[0]}-{grades[1]}", subject


def link_grades(link_id: str) -> list[int]:
    link_type, _, endpoint = link_id.split("|", 2)
    if link_type == "within_grade_pre_post":
        return [int(endpoint)]
    return [int(value) for value in endpoint.split("-")]


def anchor_row_score(row: dict[str, str], domain: str, already_selected: bool) -> float:
    tier = row["anchor_candidate_tier"]
    score = 100.0 if tier == "Tier A core candidate" else 55.0
    score += 80.0 if already_selected else 0.0
    p_a = as_float(row.get("point_biserial_rest_a")) or 0.0
    p_b = as_float(row.get("point_biserial_rest_b")) or 0.0
    score += 20.0 * min(p_a, p_b)
    if row.get("local_dependence_item_warning_a") == "1" or row.get("local_dependence_item_warning_b") == "1":
        score -= 4.0
    if row.get("irt_item_fit_warning_a") == "1" or row.get("irt_item_fit_warning_b") == "1":
        score -= 3.0
    if row.get("split_stability_warning_a") == "1" or row.get("split_stability_warning_b") == "1":
        score -= 8.0
    if domain and domain != "Unclassified":
        score += 1.0
    return score


def select_link_anchors(
    candidates: list[dict[str, str]],
    repairs: list[dict[str, str]],
    current_lookup: dict[tuple[str, int, str], dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, set[str]]]:
    repair_by_link: dict[str, dict[str, str]] = {}
    for row in repairs:
        link_id, _ = parse_repair_link(row["link"])
        repair_by_link[link_id] = row

    by_link: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in candidates:
        if row["anchor_candidate_tier"] in {"Tier A core candidate", "Tier B expanded candidate"}:
            by_link[row["link_id"]].append(row)

    selected_by_subject: dict[str, set[str]] = defaultdict(set)
    output: list[dict[str, Any]] = []
    # Disconnected links have no candidate-evidence rows by construction, so
    # the repair plan must also contribute link IDs to the universe.
    all_links = sorted({row["link_id"] for row in candidates} | set(repair_by_link))
    for link_id in all_links:
        rows = by_link.get(link_id, [])
        subject = link_id.split("|")[1]
        grades = link_grades(link_id)
        selected: list[tuple[str, str, str]] = []
        repair = repair_by_link.get(link_id)
        if repair:
            for value in repair["retain_current_candidates"].split(","):
                item_id = clean(value)
                if item_id and item_id != "none":
                    selected.append((item_id, "current item", "repair plan"))
            for value in repair["add_from_historical_bank"].split(","):
                item_id = clean(value)
                if item_id and item_id != "none":
                    selected.append((item_id, "historical addition", "repair plan"))
        else:
            ranked = []
            for row in rows:
                item_id = row["item_id"]
                current = next(
                    (
                        current_lookup[(subject, grade, normalized_id(item_id))]
                        for grade in grades
                        if (subject, grade, normalized_id(item_id)) in current_lookup
                    ),
                    {},
                )
                domain = canonical_domain(subject, current.get("content_domain", ""))
                ranked.append(
                    (
                        anchor_row_score(row, domain, normalized_id(item_id) in selected_by_subject[subject]),
                        domain,
                        item_id,
                        row["anchor_candidate_tier"],
                    )
                )
            ranked.sort(reverse=True)
            used_domains: set[str] = set()
            while ranked and len(selected) < TARGET_ANCHORS_PER_LINK:
                best_index = max(
                    range(len(ranked)),
                    key=lambda index: ranked[index][0] + (4.0 if ranked[index][1] not in used_domains else 0.0),
                )
                _, domain, item_id, tier = ranked.pop(best_index)
                selected.append((item_id, "current item", tier))
                used_domains.add(domain)

        deduplicated: list[tuple[str, str, str]] = []
        seen: set[str] = set()
        for item_id, source, reason in selected:
            key = normalized_id(item_id)
            if key in seen:
                continue
            seen.add(key)
            deduplicated.append((item_id, source, reason))
        for item_id, source, reason in deduplicated[:TARGET_ANCHORS_PER_LINK]:
            selected_by_subject[subject].add(normalized_id(item_id))
            output.append(
                {
                    "link_id": link_id,
                    "link_type": link_id.split("|")[0],
                    "subject": subject,
                    "grades": ",".join(str(value) for value in grades),
                    "item_id": item_id,
                    "normalized_item_id": normalized_id(item_id),
                    "source": source,
                    "selection_basis": reason,
                    "status": "selected provisional anchor; freeze exact version",
                }
            )
    return output, selected_by_subject


def spearman_brown(alpha: float | None, length_ratio: float) -> float | None:
    if alpha is None or not 0 < alpha < 1 or length_ratio <= 0:
        return None
    return length_ratio * alpha / (1 + (length_ratio - 1) * alpha)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    paths = read_simple_paths(args.config.resolve())
    work = paths["work_root"]
    roots = [paths["y1_root"], paths["y2_root"], paths["y3_root"]]

    decisions = read_rows(work / "outputs/y3_ministry/03_forms/y3_ministry_item_decisions.csv")
    candidates = read_rows(work / "derived/y3_ministry/y3_anchor_candidate_evidence.csv")
    repairs = read_rows(work / "outputs/y3_ministry/03_forms/y3_minimal_anchor_repairs.csv")
    pilot_bank = read_rows(work / "outputs/y3_ministry/03_forms/y3_pilot_item_bank.csv")
    tail_coverage = read_rows(work / "outputs/y3_ministry/03_forms/y3_tail_coverage_check.csv")
    historical = read_rows(work / "private_manifests/historical_bank_candidate_evidence.csv")
    reliability = read_rows(work / "outputs/y3_ministry/01_item_quality/y3_form_reliability_uncertainty.csv")

    current_lookup: dict[tuple[str, int, str], dict[str, Any]] = {}
    forms: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for row in decisions:
        subject = row["subject"]
        grade = int(row["administered_grade"])
        enriched: dict[str, Any] = dict(row)
        enriched.update(
            {
                "normalized_item_id": normalized_id(row["item_id"]),
                "content_domain": canonical_domain(subject, row["proposed_content_domain"]),
                "cognitive_domain": clean(row["proposed_cognitive_domain"]) or "Unclassified",
                "pct_correct_value": as_float(row["pct_correct"]),
                "discrimination_a": as_float(row["discrimination_a"]),
                "difficulty_b": as_float(row["difficulty_b"]),
                "point_biserial_value": as_float(row["point_biserial_rest"]),
                "tail": tail_role(as_float(row["pct_correct"])),
                "source": "current Year 3 form",
            }
        )
        forms[(subject, grade)].append(enriched)
        current_lookup[(subject, grade, enriched["normalized_item_id"])] = enriched

    historical_by_key = {
        (row["subject"], normalized_id(row["candidate_id"])): row for row in historical
    }
    pilot_by_key = {
        (row["subject"], normalized_id(row["item_id"])): row for row in pilot_bank
        if row["item_id"] != "TO BE SELECTED"
    }
    needed_tail_by_form: dict[tuple[str, int], list[str]] = defaultdict(list)
    for row in tail_coverage:
        form_key = (row["subject"], int(row["grade"]))
        if int(row["good_easy_items_current"]) < int(row["minimum_each_tail"]):
            needed_tail_by_form[form_key].append("easy")
        if int(row["good_hard_items_current"]) < int(row["minimum_each_tail"]):
            needed_tail_by_form[form_key].append("hard")
    supplements_by_form: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for pilot in pilot_bank:
        if pilot["item_id"] == "TO BE SELECTED":
            continue
        roles = {clean(value) for value in pilot["proposed_role"].split(";")}
        if not ({"tail support", "replacement now"} & roles):
            continue
        subject = pilot["subject"]
        key = normalized_id(pilot["item_id"])
        hist = historical_by_key.get((subject, key), {})
        historical_p = as_float(hist.get("historical_p_correct"))
        pct = historical_p * 100 if historical_p is not None and historical_p <= 1 else historical_p
        for grade_text in pilot["target_grade"].split(","):
            if not clean(grade_text):
                continue
            grade = int(grade_text)
            current = current_lookup.get((subject, grade, key), {})
            desired_tails = needed_tail_by_form.get((subject, grade), [])
            projected_tail = desired_tails[0] if "tail support" in roles and len(desired_tails) == 1 else tail_role(pct)
            supplements_by_form[(subject, grade)].append(
                {
                    "subject": subject,
                    "grade": grade,
                    "item_id": pilot["item_id"],
                    "normalized_item_id": key,
                    "content_domain": current.get("content_domain") or canonical_domain(subject, hist.get("content_domain", "")),
                    "cognitive_domain": current.get("cognitive_domain") or clean(hist.get("cognitive_domain")) or "Unclassified",
                    "pct_correct_value": pct,
                    "tail": projected_tail,
                    "discrimination_a": current.get("discrimination_a") if current else as_float(hist.get("historical_discrimination_a")),
                    "difficulty_b": current.get("difficulty_b") if current else as_float(hist.get("historical_difficulty_b")),
                    "point_biserial_value": current.get("point_biserial_value") if current else as_float(hist.get("historical_itemrestcor")),
                    "empirical_warning_count": "",
                    "provisional_recommendation": pilot["proposed_role"],
                    "source": "current surface revision" if current else "historical addition",
                    "is_selected_anchor": 0,
                    "anchor_links": [],
                    "supplement_priority": 1,
                }
            )

    selected_anchor_rows, _ = select_link_anchors(candidates, repairs, current_lookup)
    anchors_by_form: dict[tuple[str, int], dict[str, dict[str, Any]]] = defaultdict(dict)
    for anchor in selected_anchor_rows:
        subject = anchor["subject"]
        for grade in (int(value) for value in anchor["grades"].split(",")):
            key = anchor["normalized_item_id"]
            existing = anchors_by_form[(subject, grade)].get(key)
            if existing:
                existing["anchor_links"].append(anchor["link_id"])
                continue
            current = current_lookup.get((subject, grade, key))
            hist = historical_by_key.get((subject, key), {})
            pilot = pilot_by_key.get((subject, key), {})
            pct = as_float(current.get("pct_correct")) if current else None
            if pct is None and hist:
                historical_p = as_float(hist.get("historical_p_correct"))
                pct = historical_p * 100 if historical_p is not None and historical_p <= 1 else historical_p
            anchors_by_form[(subject, grade)][key] = {
                "subject": subject,
                "grade": grade,
                "item_id": current.get("item_id") if current else anchor["item_id"],
                "normalized_item_id": key,
                "is_selected_anchor": 1,
                "anchor_links": [anchor["link_id"]],
                "source": "current Year 3 form" if current else "historical addition",
                "content_domain": current.get("content_domain") if current else canonical_domain(subject, hist.get("content_domain", "")),
                "cognitive_domain": current.get("cognitive_domain") if current else clean(hist.get("cognitive_domain")) or "Unclassified",
                "pct_correct_value": pct,
                "tail": tail_role(pct),
                "discrimination_a": as_float(current.get("discrimination_a")) if current else as_float(hist.get("historical_discrimination_a")),
                "difficulty_b": as_float(current.get("difficulty_b")) if current else as_float(hist.get("historical_difficulty_b")),
                "point_biserial_value": as_float(current.get("point_biserial_rest")) if current else as_float(hist.get("historical_itemrestcor")),
                "empirical_warning_count": current.get("empirical_warning_count", "") if current else "",
                "provisional_recommendation": current.get("provisional_recommendation", "") if current else pilot.get("proposed_role", "historical anchor repair"),
            }

    alpha_lookup = {
        (row["subject"], int(row["grade"])): as_float(row["alpha"])
        for row in reliability if row["wave"] == "endline"
    }

    summary_rows: list[dict[str, Any]] = []
    item_plan_rows: list[dict[str, Any]] = []
    for form_key in sorted(forms, key=lambda value: (value[0], value[1])):
        subject, grade = form_key
        current_items = forms[form_key]
        current_n = len(current_items)
        target_n = max(math.ceil(current_n * TARGET_LENGTH_SHARE), len(anchors_by_form[form_key]))
        selected: dict[str, dict[str, Any]] = dict(anchors_by_form[form_key])

        def counts(field: str) -> dict[str, int]:
            result: dict[str, int] = defaultdict(int)
            for item in selected.values():
                result[clean(item.get(field)) or "Unclassified"] += 1
            return result

        available_domains = sorted({item["content_domain"] for item in current_items if item["content_domain"] != "Unclassified"})
        available_cognitive = sorted({item["cognitive_domain"] for item in current_items if item["cognitive_domain"] != "Unclassified"})

        def candidate_priority(item: dict[str, Any]) -> float:
            warning = as_float(item.get("empirical_warning_count")) or 0.0
            pbis = item.get("point_biserial_value") or 0.0
            info = mean_information(item)
            recommendation = clean(item.get("provisional_recommendation"))
            penalty = 15.0 if recommendation.startswith(("revise", "replace", "retire")) else 0.0
            domain_bonus = 8.0 if counts("content_domain").get(item["content_domain"], 0) < MIN_ITEMS_PER_BROAD_DOMAIN else 0.0
            cognitive_bonus = 3.0 if counts("cognitive_domain").get(item["cognitive_domain"], 0) == 0 else 0.0
            tail_bonus = 5.0 if counts("tail").get(item["tail"], 0) < MIN_ITEMS_PER_TAIL and item["tail"] in {"easy", "hard"} else 0.0
            supplement_bonus = 8.0 if item.get("supplement_priority") else 0.0
            return 12.0 * info + 10.0 * pbis - 2.5 * warning - penalty + domain_bonus + cognitive_bonus + tail_bonus + supplement_bonus

        pool = [item for item in current_items if item["normalized_item_id"] not in selected]
        for item in supplements_by_form.get(form_key, []):
            if item["normalized_item_id"] in selected:
                continue
            existing = next(
                (candidate for candidate in pool if candidate["normalized_item_id"] == item["normalized_item_id"]),
                None,
            )
            if existing:
                existing.update(item)
            else:
                pool.append(item)
        while len(selected) < target_n and pool:
            best = max(pool, key=candidate_priority)
            selected[best["normalized_item_id"]] = {**best, "is_selected_anchor": 0, "anchor_links": []}
            pool.remove(best)

        def unmet_constraints() -> list[str]:
            messages = []
            domain_counts = counts("content_domain")
            for domain in available_domains:
                if domain_counts.get(domain, 0) < min(MIN_ITEMS_PER_BROAD_DOMAIN, sum(item["content_domain"] == domain for item in current_items)):
                    messages.append(f"content:{domain}")
            cognitive_counts = counts("cognitive_domain")
            for domain in available_cognitive:
                if cognitive_counts.get(domain, 0) == 0:
                    messages.append(f"cognitive:{domain}")
            tail_counts = counts("tail")
            for role in ("easy", "hard"):
                if tail_counts.get(role, 0) < MIN_ITEMS_PER_TAIL:
                    messages.append(f"tail:{role}")
            return messages

        # Add the best targeted item for any constraint still missed by the half-length draft.
        while pool and unmet_constraints():
            before = set(unmet_constraints())
            useful = []
            for item in pool:
                addresses = set()
                if f"content:{item['content_domain']}" in before:
                    addresses.add(f"content:{item['content_domain']}")
                if f"cognitive:{item['cognitive_domain']}" in before:
                    addresses.add(f"cognitive:{item['cognitive_domain']}")
                if f"tail:{item['tail']}" in before:
                    addresses.add(f"tail:{item['tail']}")
                if addresses:
                    useful.append((len(addresses), candidate_priority(item), item))
            if not useful:
                break
            best = max(useful, key=lambda value: (value[0], value[1]))[2]
            selected[best["normalized_item_id"]] = {**best, "is_selected_anchor": 0, "anchor_links": []}
            pool.remove(best)

        selected_items = list(selected.values())
        current_info = sum(mean_information(item) for item in current_items)
        selected_info = sum(mean_information(item) for item in selected_items)
        alpha = alpha_lookup.get(form_key)
        alpha_forecast = spearman_brown(alpha, len(selected_items) / current_n)
        selected_domains = counts("content_domain")
        selected_cognitive = counts("cognitive_domain")
        selected_tails = counts("tail")
        issues = unmet_constraints()
        summary_rows.append(
            {
                "subject": subject,
                "grade": grade,
                "current_item_n": current_n,
                "half_length_n": math.ceil(current_n * TARGET_LENGTH_SHARE),
                "selected_anchor_n": len(anchors_by_form[form_key]),
                "provisional_minimum_item_n": len(selected_items),
                "reduction_pct": round(100 * (1 - len(selected_items) / current_n), 1),
                "endline_alpha_full_form": round(alpha, 3) if alpha is not None else "",
                "length_only_alpha_forecast": round(alpha_forecast, 3) if alpha_forecast is not None else "",
                "irt_information_retained_pct": round(100 * selected_info / current_info, 1) if current_info else "",
                "easy_item_n": selected_tails.get("easy", 0),
                "hard_item_n": selected_tails.get("hard", 0),
                "broad_content_domains_n": len([value for value in selected_domains if value != "Unclassified"]),
                "cognitive_domains_n": len([value for value in selected_cognitive if value != "Unclassified"]),
                "unresolved_constraints": "; ".join(issues),
                "operational_status": "provisional until passage/testlet bundles and administration time are confirmed",
            }
        )
        for item in sorted(selected_items, key=lambda value: (-int(value.get("is_selected_anchor", 0)), clean(value.get("item_id")))):
            item_plan_rows.append(
                {
                    "subject": subject,
                    "grade": grade,
                    "item_id": item["item_id"],
                    "selected_anchor": item.get("is_selected_anchor", 0),
                    "anchor_links": "; ".join(item.get("anchor_links", [])),
                    "source": item.get("source", ""),
                    "content_domain": item.get("content_domain", ""),
                    "cognitive_domain": item.get("cognitive_domain", ""),
                    "tail_role": item.get("tail", ""),
                    "pct_correct": round(item["pct_correct_value"], 1) if item.get("pct_correct_value") is not None else "",
                    "point_biserial_rest": round(item["point_biserial_value"], 3) if item.get("point_biserial_value") is not None else "",
                    "selection_note": "freeze unchanged" if item.get("is_selected_anchor") else "scored non-anchor selected for coverage/information",
                }
            )

    output_dir = work / "outputs/y3_ministry/05_short_form"
    summary_path = assert_output_path(output_dir / "y4_baseline_short_form_summary.csv", work, roots)
    anchors_path = assert_output_path(output_dir / "y4_baseline_selected_anchors.csv", work, roots)
    plan_path = assert_output_path(output_dir / "y4_baseline_short_form_item_plan.csv", work, roots)
    notes_path = assert_output_path(output_dir / "y4_baseline_short_form_notes.json", work, roots)
    write_rows(summary_path, summary_rows, list(summary_rows[0]))
    write_rows(anchors_path, selected_anchor_rows, list(selected_anchor_rows[0]))
    write_rows(plan_path, item_plan_rows, list(item_plan_rows[0]))
    notes_path.parent.mkdir(parents=True, exist_ok=True)
    notes_path.write_text(
        json.dumps(
            {
                "status": "provisional emergency short-form design",
                "target_length_share": TARGET_LENGTH_SHARE,
                "target_anchors_per_link": TARGET_ANCHORS_PER_LINK,
                "selection_blind_to_treatment": True,
                "anchor_rule": "Only selected link-specific anchors are mandatory and frozen; Tier A/B denotes candidate eligibility, not automatic inclusion.",
                "minimum_definition": "Approximately half length, increased only where selected anchors or broad domain/cognitive/tail constraints require it.",
                "alpha_warning": "Spearman-Brown values are length-only forecasts, not re-estimated reliability on administered short forms.",
                "information_warning": "IRT information uses existing item parameters and is provisional for historical additions.",
                "testlet_blocker": "Passage, image, oral-task, and rubric bundle identifiers remain incomplete. Final item order/count requires manual bundle confirmation.",
                "trend_anchor_boundary": "Across-year trend anchors are not added to the mandatory floor until exact Year 4 link intent and item-version equivalence are confirmed.",
                "source_outputs": [
                    "y3_ministry_item_decisions.csv",
                    "y3_anchor_candidate_evidence.csv",
                    "y3_minimal_anchor_repairs.csv",
                    "y3_pilot_item_bank.csv",
                    "y3_tail_coverage_check.csv",
                    "historical_bank_candidate_evidence.csv",
                    "y3_form_reliability_uncertainty.csv",
                ],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "summary": str(summary_path),
                "anchors": str(anchors_path),
                "item_plan": str(plan_path),
                "notes": str(notes_path),
                "forms": len(summary_rows),
                "selected_anchor_rows": len(selected_anchor_rows),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
