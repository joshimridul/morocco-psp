from pathlib import Path
import importlib.util
import unittest


MODULE_PATH = Path(__file__).parents[1] / "src" / "05_ministry" / "build_minimal_change_package.py"
SPEC = importlib.util.spec_from_file_location("build_minimal_change_package", MODULE_PATH)
module = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(module)


def candidate(item_id, subject, domain, tail, grade=4):
    return {
        "candidate_id": item_id,
        "candidate_base_id": item_id,
        "subject": subject,
        "grade_origin": grade,
        "content_domain": domain,
        "tail_role": tail,
        "historical_discrimination_a": 1.2,
        "historical_itemrestcor": 0.3,
        "years_with_latest_id": "Y1",
        "question_summary_sha256": item_id,
    }


class MinimalChangeSelectionTest(unittest.TestCase):
    def test_historical_and_current_domain_labels_match(self):
        self.assertEqual(module.canonical_content_domain("LF", "Arabic"), "LF")
        self.assertEqual(
            module.canonical_content_domain("Lecture: décodage et fluidité", "Arabic"),
            "LF",
        )
        self.assertEqual(
            module.canonical_content_domain("Geometric shapes and measures", "Maths"),
            "GM",
        )

    def test_strict_tail_selection_never_substitutes_middle_item(self):
        bank = [
            candidate("easy", "Maths", "Calculation and Numeracy", "easy / lower-tail information"),
            candidate("middle", "Maths", "Calculation and Numeracy", "middle"),
        ]
        selected = module.select_candidates(
            bank,
            "Maths",
            {4},
            2,
            desired_tail="easy",
            require_tail_match=True,
        )
        self.assertEqual([row["candidate_id"] for row in selected], ["easy"])

    def test_replacement_selection_preserves_broad_domain(self):
        bank = [
            candidate("geometry", "Maths", "Geometric shapes and measures", "middle"),
            candidate("calculation", "Maths", "Calculation and Numeracy", "middle"),
        ]
        selected = module.select_candidates(
            bank,
            "Maths",
            {4},
            2,
            content_domain="GM",
            require_content_match=True,
        )
        self.assertEqual([row["candidate_id"] for row in selected], ["geometry"])


if __name__ == "__main__":
    unittest.main()
