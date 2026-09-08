from pathlib import Path
import importlib.util
import unittest


MODULE_PATH = (
    Path(__file__).parents[1]
    / "src"
    / "21_y1_y3_irt"
    / "build_y3_y1_anchor_manifest.py"
)
SPEC = importlib.util.spec_from_file_location("build_y3_y1_anchor_manifest", MODULE_PATH)
module = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(module)


class AnchorManifestTest(unittest.TestCase):
    def test_uirt_to_mirt_intercept_conversion(self):
        a = 1.7
        b = -0.4
        d = -a * b
        theta = 0.8
        uirt_linear_predictor = a * (theta - b)
        mirt_linear_predictor = a * theta + d
        self.assertAlmostEqual(uirt_linear_predictor, mirt_linear_predictor, places=14)

    def test_exact_single_summary_requires_current_map_agreement(self):
        self.assertEqual(
            module.summary_equivalence_status({"one"}, {"one"}, "one"),
            "exact_single_summary",
        )
        self.assertEqual(
            module.summary_equivalence_status({"one"}, {"one"}, "two"),
            "summary_mismatch_or_missing",
        )

    def test_multiple_summaries_are_not_called_exact(self):
        self.assertEqual(
            module.summary_equivalence_status(
                {"one", "two"}, {"one", "two"}, "one"
            ),
            "overlapping_summary_set_requires_version_resolution",
        )


if __name__ == "__main__":
    unittest.main()
