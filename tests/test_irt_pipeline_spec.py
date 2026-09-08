import itertools
import pathlib
import unittest

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[1]


class IrtPipelineSpecificationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = yaml.safe_load((ROOT / "config/irt_pipeline.yml").read_text())

    def test_primary_rules_are_locked(self):
        rules = self.spec["rules"]
        self.assertTrue(rules["binary_items_only"])
        self.assertFalse(rules["treatment_used_for_item_selection"])
        self.assertTrue(rules["preserve_y1_item_parameters"])
        self.assertEqual(rules["y1_reference_population"], "endline_comparison")

    def test_admissible_joint_grid_is_complete_cartesian_product(self):
        grid = self.spec["joint_factorial"]
        combinations = set(itertools.product(
            grid["anchor_modes"], grid["sample_modes"], grid["model_scopes"]
        ))
        self.assertEqual(len(combinations), 8)
        self.assertIn(
            ("purified_andy_core_math_bridge5", "all", "subject_pooled_mixture"),
            combinations,
        )

    def test_plain_score_grid_has_both_rules_and_three_samples(self):
        plain = self.spec["plain_scores"]
        self.assertEqual(set(plain["standardizations"]), {"plain_code", "plain_report_grade"})
        self.assertEqual(len(set(plain["sample_variants"])), 3)

    def test_measurement_runner_does_not_invoke_regression_directory(self):
        runner = (ROOT / "src/21_y1_y3_irt/run_irt_pipeline.R").read_text()
        self.assertNotIn('script_path("src/22_treatment_effects', runner)


if __name__ == "__main__":
    unittest.main()
