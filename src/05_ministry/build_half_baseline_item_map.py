#!/usr/bin/env python3
"""Assemble the protected half-length baseline item map and decision log.

The Ministry-facing source table contains only selected items and essential
operational fields.  The separate internal log retains every current form-item
row plus the screened historical bank and records why each row was or was not
selected.  Secure item text and keys are written only below work_root.
"""

from __future__ import annotations

import argparse
import csv
import json
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

NUMBER_WORDS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
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


def normalized_id(value: str) -> str:
    text = re.sub(r"[^a-z0-9]+", "", value.casefold())
    text = re.sub(r"y[123](?:nv|v)?[0-9]*$", "", text)
    return re.sub(r"(?:nv|v)[0-9]*$", "", text)


def normalized_text(value: str) -> str:
    return re.sub(r"\s+", " ", clean(value).casefold()).strip()


def grade_values(value: str) -> list[int]:
    return [int(match) for match in re.findall(r"[1-6]", value)]


def numeric_question(value: str) -> float:
    match = re.search(r"\d+(?:\.\d+)?", clean(value))
    return float(match.group()) if match else 9999.0


def cognitive_label(value: str) -> str:
    text = clean(value)
    return COGNITIVE_LABELS.get(text.upper(), text or "Unclassified")


def infer_basic_math_answer(prompt: str) -> str:
    """Recompute only transparent single-operation answers from protected text."""
    multiplication = re.search(r"\b(\d+)\s*[x×*]\s*(\d+)\s*=", prompt, re.IGNORECASE)
    if multiplication:
        return str(int(multiplication.group(1)) * int(multiplication.group(2)))
    equal_groups = re.search(
        r"\b(\d+)\b.*?\b(?:equally\s+)?into\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+(?:groups|workshops)\b",
        prompt,
        re.IGNORECASE,
    )
    if equal_groups:
        total = int(equal_groups.group(1))
        divisor_text = equal_groups.group(2).casefold()
        divisor = int(divisor_text) if divisor_text.isdigit() else NUMBER_WORDS[divisor_text]
        if divisor and total % divisor == 0:
            return str(total // divisor)
    return ""


def find_exact_historical_answer(
    subject: str,
    item_id: str,
    prompt: str,
    historical_by_key: dict[tuple[str, str], list[dict[str, str]]],
) -> tuple[str, str]:
    prompt_key = normalized_text(prompt)
    for row in historical_by_key.get((subject, normalized_id(item_id)), []):
        if normalized_text(row["question_summary"]) == prompt_key and row["correct_answer_or_guideline"]:
            return row["correct_answer_or_guideline"], row["historical_source"]
    return "", ""


def selection_reason(
    selected: bool,
    anchor: bool,
    anchor_links: str,
    tail_role: str,
    recommendation: str,
    anchor_tier: str,
    source_role: str = "",
) -> str:
    if selected and anchor:
        links = anchor_links.replace("within_grade_pre_post", "baseline–endline").replace(
            "adjacent_grade_vertical", "adjacent-grade"
        )
        return f"Selected as a link-specific anchor ({links}); keep the exact item version unchanged."
    if selected:
        parts = ["Selected after fixing anchors to retain strong measurement information and domain coverage"]
        if tail_role == "easy":
            parts.append("supports measurement of lower-performing students")
        elif tail_role == "hard":
            parts.append("supports measurement of higher-performing students")
        if source_role:
            parts.append(source_role)
        return "; ".join(parts) + "."
    if "conditional replacement" in source_role:
        return "Not selected for the minimum form; retained only as a reserve replacement."
    if recommendation.startswith(("revise or replace", "retain only after", "replace", "retire")):
        return f"Not selected for the half-length baseline because the prior review recommended: {recommendation}."
    if anchor_tier in {"Tier A core candidate", "Tier B expanded candidate"}:
        return "Not selected: empirically eligible as an anchor candidate, but not needed after choosing five balanced anchors for the relevant link(s)."
    if tail_role in {"easy", "hard"}:
        return "Not selected: the required tail and domain coverage was already supplied by stronger or less problematic items."
    return "Not selected after the anchor, domain, tail, and information constraints were applied; other items contributed more to the minimum form."


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    paths = read_simple_paths(args.config.resolve())
    work = paths["work_root"]
    roots = [paths["y1_root"], paths["y2_root"], paths["y3_root"]]

    plan = read_rows(work / "outputs/y3_ministry/05_short_form/y4_baseline_short_form_item_plan.csv")
    decisions = read_rows(work / "outputs/y3_ministry/03_forms/y3_ministry_item_decisions.csv")
    domains = read_rows(work / "outputs/y3_ministry/03_forms/y3_completed_domain_map.csv")
    pilot_bank = read_rows(work / "outputs/y3_ministry/03_forms/y3_pilot_item_bank.csv")
    math_edits = read_rows(work / "private_manifests/y3_math_surface_edits.csv")
    historical = read_rows(work / "private_manifests/historical_bank_candidate_evidence.csv")

    decision_by_key = {
        (row["subject"], int(row["administered_grade"]), row["item_id"]): row for row in decisions
    }
    domain_by_key = {
        (row["subject"], int(row["form_grade"]), row["item_id"]): row for row in domains
    }
    plan_by_key = {
        (row["subject"], int(row["grade"]), row["item_id"]): row for row in plan
    }
    protected_anchor_versions = {
        (row["subject"], normalized_id(row["item_id"]))
        for row in plan if row["selected_anchor"] == "1"
    }
    math_by_key = {
        (row["subject"], int(row["administered_grade"]), row["item_id"]): row
        for row in math_edits
    }
    math_by_id: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in math_edits:
        math_by_id[(row["subject"], row["item_id"])].append(row)
    historical_by_key: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in historical:
        historical_by_key[(row["subject"], normalized_id(row["candidate_id"]))].append(row)

    pilot_by_grade_key: dict[tuple[str, int, str], dict[str, str]] = {}
    for row in pilot_bank:
        if row["item_id"] == "TO BE SELECTED":
            continue
        for grade in grade_values(row["target_grade"]):
            pilot_by_grade_key[(row["subject"], grade, normalized_id(row["item_id"]))] = row

    selected_rows: list[dict[str, Any]] = []
    selected_internal: dict[tuple[str, int, str], dict[str, Any]] = {}
    for plan_row in plan:
        subject = plan_row["subject"]
        grade = int(plan_row["grade"])
        item_id = plan_row["item_id"]
        key = (subject, grade, item_id)
        anchor = plan_row["selected_anchor"] == "1"
        current = decision_by_key.get(key)
        domain = domain_by_key.get(key, {})
        pilot = pilot_by_grade_key.get((subject, grade, normalized_id(item_id)))
        math_edit = math_by_key.get(key)
        original_question = current["question_summary"] if current else (pilot or {}).get("item_text", "")
        item_text = original_question
        answer = ""
        answer_status = ""
        source_reference = ""
        original_question_number = current["question_number"] if current else ""
        final_check = ""
        wording_status = "Exact selected anchor; do not edit" if anchor else "Existing wording"

        if current:
            source_reference = domain.get("source_map", "Year 3 endline item map")
            if subject == "Maths" and not anchor and plan_row["source"] == "current surface revision" and pilot:
                item_text = pilot["change_made"] or pilot["item_text"]
                answer = pilot["revised_answer"] or pilot["correct_answer_or_guideline"]
                answer_status = "Proposed revision independently checked"
                source_reference = pilot["source_bank"]
                wording_status = "Proposed easier revision"
                final_check = "Ministry to implement the revised numbers consistently in student and examiner versions."
            elif subject == "Maths" and not anchor and math_edit:
                item_text = math_edit["revised_item_english"] or original_question
                answer = math_edit["revised_answer_or_key"]
                answer_status = "Proposed revision independently checked"
                source_reference = math_edit["source_reference"]
                wording_status = "Proposed English surface revision"
                checks = ["Ministry to prepare the final Arabic wording"]
                if math_edit["visual_or_layout_edit_required"].startswith("YES"):
                    checks.append("update the figure/layout")
                if math_edit["testlet_or_bundle"]:
                    checks.append(f"update together with {math_edit['testlet_or_bundle']}")
                final_check = "; ".join(checks) + "."
            else:
                # An anchor may be absent from the edit file in its own grade but
                # have an exact prompt match in another grade-specific key file.
                for candidate in math_by_id.get((subject, item_id), []):
                    if normalized_text(candidate["question_summary"]) == normalized_text(original_question):
                        answer = candidate["current_answer_or_key"]
                        if answer:
                            answer_status = "Matched to checked examiner-guide key"
                            source_reference = candidate["source_reference"]
                            break
                if not answer and pilot and normalized_text(pilot["item_text"]) == normalized_text(original_question):
                    answer = pilot["correct_answer_or_guideline"]
                    answer_status = "Matched to protected pilot-bank source"
                    source_reference = pilot["source_bank"]
                if not answer:
                    answer, answer_source = find_exact_historical_answer(
                        subject, item_id, original_question, historical_by_key
                    )
                    if answer:
                        answer_status = "Exact prompt match to historical scoring guidance"
                        source_reference = answer_source
                if (
                    not answer
                    and subject == "Maths"
                    and not anchor
                    and (subject, normalized_id(item_id)) in protected_anchor_versions
                ):
                    answer = infer_basic_math_answer(original_question)
                    if answer:
                        answer_status = "Transparent arithmetic independently recomputed"
                        wording_status = "Exact version protected as an anchor in another grade; do not edit"
                        final_check = (
                            "Keep the wording unchanged because this exact item version is an anchor "
                            "in another grade; confirm the examiner guide shows the same answer."
                        )
                if not answer:
                    answer = "MINISTRY TO CONFIRM FROM EXAMINER GUIDE"
                    answer_status = "Confirmation required"
                    final_check = "Confirm the answer or scoring rule against the examiner guide."
                elif anchor:
                    final_check = "Use the exact source wording, stimulus, options, answer and scoring unchanged."
        else:
            if not pilot:
                raise RuntimeError(f"Selected non-current item not resolved in pilot bank: {subject} G{grade} {item_id}")
            item_text = pilot["item_text"]
            answer = pilot["correct_answer_or_guideline"]
            answer_status = "Source-bank answer/scoring guidance"
            source_reference = pilot["source_bank"]
            wording_status = "Historical source version"
            if anchor:
                final_check = "Copy the exact source-language item, stimulus, options and scoring unchanged into every indicated grade."
            elif subject == "Maths" and pilot["change_made"]:
                item_text = pilot["change_made"]
                answer = pilot["revised_answer"] or answer
                answer_status = "Proposed revision independently checked"
                wording_status = "Proposed English revision"
                final_check = "Ministry to prepare the final Arabic wording and synchronize student/examiner versions."
            else:
                final_check = "Confirm the exact source-language wording and scoring before assembly."

        if not clean(item_text):
            raise RuntimeError(f"Blank item text: {subject} G{grade} {item_id}")
        if not clean(answer):
            answer = "MINISTRY TO CONFIRM FROM EXAMINER GUIDE"
            answer_status = "Confirmation required"
            final_check = "Confirm the answer or scoring rule against the examiner guide."
        if not clean(final_check):
            final_check = "Confirm that the student and examiner versions match during final assembly."

        row = {
            "subject": subject,
            "grade": grade,
            "baseline_item_no": 0,
            "item_id": item_id,
            "anchor": "YES" if anchor else "",
            "item_or_summary": item_text,
            "answer_or_scoring": answer,
            "content_domain": plan_row["content_domain"],
            "cognitive_domain": cognitive_label(plan_row["cognitive_domain"]),
            "source": plan_row["source"],
            "final_check": final_check,
            "original_question_number": original_question_number,
            "wording_status": wording_status,
            "answer_status": answer_status,
            "source_reference": source_reference,
        }
        selected_rows.append(row)
        selected_internal[key] = row

    selected_rows.sort(
        key=lambda row: (
            row["subject"],
            row["grade"],
            numeric_question(row["original_question_number"]),
            1 if not row["original_question_number"] else 0,
            row["item_id"],
        )
    )
    order_counter: Counter[tuple[str, int]] = Counter()
    for row in selected_rows:
        order_counter[(row["subject"], row["grade"])] += 1
        row["baseline_item_no"] = order_counter[(row["subject"], row["grade"])]

    log_rows: list[dict[str, Any]] = []
    for current in decisions:
        subject = current["subject"]
        grade = int(current["administered_grade"])
        key = (subject, grade, current["item_id"])
        plan_row = plan_by_key.get(key)
        selected = plan_row is not None
        anchor = selected and plan_row["selected_anchor"] == "1"
        tail = plan_row["tail_role"] if selected else (
            "easy" if current["pct_correct"] and 70 <= float(current["pct_correct"]) <= 90
            else "hard" if current["pct_correct"] and 10 <= float(current["pct_correct"]) <= 35
            else "middle"
        )
        internal = selected_internal.get(key, {})
        log_rows.append({
            "candidate_type": "current Year 3 form item",
            "subject": subject,
            "grade": grade,
            "item_id": current["item_id"],
            "question_summary": current["question_summary"],
            "selected": "YES" if selected else "NO",
            "selected_anchor": "YES" if anchor else "",
            "anchor_links": plan_row["anchor_links"] if selected else current["eligible_anchor_link_ids"],
            "content_domain": plan_row["content_domain"] if selected else current["proposed_content_domain"],
            "cognitive_domain": cognitive_label(plan_row["cognitive_domain"] if selected else current["proposed_cognitive_domain"]),
            "tail_role": tail,
            "pct_correct": current["pct_correct"],
            "point_biserial_rest": current["point_biserial_rest"],
            "discrimination_a": current["discrimination_a"],
            "difficulty_b": current["difficulty_b"],
            "empirical_warning_count": current["empirical_warning_count"],
            "prior_recommendation": current["provisional_recommendation"],
            "decision_reason": selection_reason(
                selected,
                anchor,
                plan_row["anchor_links"] if selected else "",
                tail,
                current["provisional_recommendation"],
                current["best_empirical_anchor_tier"],
            ),
            "wording_status": internal.get("wording_status", "Not applicable"),
            "answer_status": internal.get("answer_status", "Not applicable"),
            "source_reference": internal.get("source_reference", domain_by_key.get(key, {}).get("source_map", "")),
        })

    pilot_ids = {(row["subject"], normalized_id(row["item_id"])) for row in pilot_bank if row["item_id"] != "TO BE SELECTED"}
    current_normalized_grade_keys = {
        (row["subject"], int(row["administered_grade"]), normalized_id(row["item_id"]))
        for row in decisions
    }
    for pilot in pilot_bank:
        grades = grade_values(pilot["target_grade"]) or [0]
        for grade in grades:
            # A shortlist row can describe an item that is already present on
            # the current form.  Its decision is already logged above at the
            # authoritative current item-version grain, so do not duplicate it.
            if (
                grade
                and (
                    pilot["subject"],
                    grade,
                    normalized_id(pilot["item_id"]),
                ) in current_normalized_grade_keys
            ):
                continue
            matching_plan = next(
                (
                    row for row in plan
                    if row["subject"] == pilot["subject"]
                    and int(row["grade"]) == grade
                    and normalized_id(row["item_id"]) == normalized_id(pilot["item_id"])
                ),
                None,
            )
            selected = matching_plan is not None
            anchor = selected and matching_plan["selected_anchor"] == "1"
            log_rows.append({
                "candidate_type": "historical/proposed shortlist item",
                "subject": pilot["subject"],
                "grade": grade or "",
                "item_id": pilot["item_id"],
                "question_summary": pilot["item_text"],
                "selected": "YES" if selected else "NO",
                "selected_anchor": "YES" if anchor else "",
                "anchor_links": matching_plan["anchor_links"] if selected else "",
                "content_domain": matching_plan["content_domain"] if selected else "",
                "cognitive_domain": cognitive_label(matching_plan["cognitive_domain"]) if selected else "",
                "tail_role": matching_plan["tail_role"] if selected else "",
                "pct_correct": "",
                "point_biserial_rest": "",
                "discrimination_a": "",
                "difficulty_b": "",
                "empirical_warning_count": "",
                "prior_recommendation": pilot["proposed_role"],
                "decision_reason": selection_reason(
                    selected,
                    anchor,
                    matching_plan["anchor_links"] if selected else "",
                    matching_plan["tail_role"] if selected else "",
                    "",
                    "",
                    pilot["proposed_role"],
                ),
                "wording_status": selected_internal.get(
                    (pilot["subject"], grade, matching_plan["item_id"] if selected else ""), {}
                ).get("wording_status", "Not selected"),
                "answer_status": pilot["review_status"],
                "source_reference": pilot["source_bank"] or "No source item provided; candidate not selected",
            })

    # Keep the rest of the screened historical bank visible in the audit log,
    # even though these rows did not reach the 42-row operational shortlist.
    for row in historical:
        if (row["subject"], normalized_id(row["candidate_id"])) in pilot_ids:
            continue
        log_rows.append({
            "candidate_type": "historical bank candidate",
            "subject": row["subject"],
            "grade": row["grade_origin"],
            "item_id": row["candidate_id"],
            "question_summary": row["question_summary"],
            "selected": "NO",
            "selected_anchor": "",
            "anchor_links": "",
            "content_domain": row["content_domain"],
            "cognitive_domain": cognitive_label(row["cognitive_domain"]),
            "tail_role": row["tail_role"],
            "pct_correct": row["historical_p_correct"],
            "point_biserial_rest": row["historical_itemrestcor"],
            "discrimination_a": row["historical_discrimination_a"],
            "difficulty_b": row["historical_difficulty_b"],
            "empirical_warning_count": "",
            "prior_recommendation": "screened historical candidate",
            "decision_reason": "Not selected into the minimal anchor, replacement, or tail shortlist; the chosen current/shortlisted items met the form constraints with fewer changes.",
            "wording_status": "Not selected",
            "answer_status": row["version_review_status"],
            "source_reference": row["historical_source"],
        })

    output_dir = work / "outputs/y3_ministry/05_short_form/final_baseline_map"
    selected_path = assert_output_path(output_dir / "baseline_half_length_item_map_source.csv", work, roots)
    log_path = assert_output_path(output_dir / "baseline_half_length_item_selection_log.csv", work, roots)
    summary_path = assert_output_path(output_dir / "baseline_half_length_item_map_summary.json", work, roots)
    selected_fields = [
        "subject", "grade", "baseline_item_no", "item_id", "anchor",
        "item_or_summary", "answer_or_scoring", "content_domain",
        "cognitive_domain", "source", "final_check",
    ]
    log_fields = [
        "candidate_type", "subject", "grade", "item_id", "question_summary",
        "selected", "selected_anchor", "anchor_links", "content_domain",
        "cognitive_domain", "tail_role", "pct_correct", "point_biserial_rest",
        "discrimination_a", "difficulty_b", "empirical_warning_count",
        "prior_recommendation", "decision_reason", "wording_status",
        "answer_status", "source_reference",
    ]
    write_rows(selected_path, selected_rows, selected_fields)
    write_rows(log_path, log_rows, log_fields)
    counts = Counter((row["subject"], row["grade"]) for row in selected_rows)
    summary = {
        "status": "assembled for adversarial review",
        "selected_item_rows": len(selected_rows),
        "selected_anchor_rows": sum(row["anchor"] == "YES" for row in selected_rows),
        "selection_log_rows": len(log_rows),
        "answer_confirmation_required_rows": sum(
            row["answer_status"] == "Confirmation required" for row in selected_rows
        ),
        "counts_by_subject_grade": {
            f"{subject}|{grade}": count for (subject, grade), count in sorted(counts.items())
        },
        "accepted_tail_exception": "French Grade 4 retains one empirically acceptable easy item rather than two; acceptable for a low-stakes pre-test but should be revisited after pilot timing and response data.",
        "ordering_note": "Current items retain relative Year 3 order; historical additions follow current items. Final operational order must preserve passage/oral-task bundles.",
        "outputs": [str(selected_path), str(log_path)],
    }
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
