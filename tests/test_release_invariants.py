from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReleaseInvariantTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text()

    def test_stata_missing_value_rule_is_explicit(self):
        scorers = [
            "src/21_y1_y3_irt/run_joint_multigroup_scoring.R",
            "src/21_y1_y3_irt/run_multiyear_chained_scoring.R",
            "src/21_y1_y3_irt/run_y3_direct_fixed_anchor_scoring.R",
            "src/21_y1_y3_irt/build_plain_score_robustness.R",
        ]
        for path in scorers:
            with self.subTest(path=path):
                text = self.read(path)
                self.assertIn('tag == "a"', text)
                self.assertNotRegex(text, r"scored\s*\[\s*is_tagged_na\(")

    def test_pooled_weights_are_recomputed_for_each_outcome(self):
        programs = self.read("src/30_ministry_irt_report/lib/analysis_programs.do")
        grade = self.read("src/30_ministry_irt_report/20_estimate_grade.do")
        heterogeneity = self.read("src/30_ministry_irt_report/30_estimate_heterogeneity.do")
        self.assertIn("subject_cohort_n", programs)
        self.assertIn("cohort_grade_n", grade)
        self.assertIn("group_cohort_n", heterogeneity)
        self.assertIn("i.post#i.grade#i.pair_est", programs)
        self.assertIn("i.post#i.grade#i.pair_est", heterogeneity)
        self.assertIn('if "`method\'" == "ministry_sum"', programs)
        self.assertIn('if "`method\'" == "ministry_sum"', grade)
        self.assertIn('if "`method\'" == "ministry_sum"', heterogeneity)
        self.assertIn("tag(school_est) if e(sample)", programs)

    def test_required_link_floor_applies_to_every_subject(self):
        purification = self.read(
            "src/21_y1_y3_irt/run_multiyear_anchor_purification.R"
        )
        targeted = self.read(
            "src/21_y1_y3_irt/build_targeted_purified_constraints.R"
        )
        self.assertIn("required_link_bridge_sensitivity", purification)
        self.assertIn("bridge_floor_retained", purification)
        self.assertNotIn(
            'rule_profile == "math_bridge5" && link$subject[[1]] == "Maths"',
            purification,
        )
        self.assertIn("required_link_bridge_constraint", targeted)

    def test_primary_irt_has_declared_convergence_budget(self):
        analysis = self.read("config/analysis.yml")
        scorer = self.read("src/21_y1_y3_irt/run_joint_multigroup_scoring.R")
        self.assertIn("primary_calibration_max_cycles: 4000", analysis)
        self.assertIn("estimated_discrimination_upper_bound: 10", analysis)
        self.assertIn("this_calibration_max_cycles", scorer)
        self.assertIn("is_primary_specification", scorer)
        self.assertIn("values$ubound[free_slope_rows]", scorer)

    def test_regression_qa_requires_success_marker(self):
        validator = self.read("src/30_ministry_irt_report/90_validate_outputs.do")
        qa = self.read("src/30_ministry_irt_report/qa/adversarial_review.R")
        self.assertIn("morocco_psp_regression_qa_passed.txt", validator)
        self.assertIn('writeLines("regression_qa_complete"', qa)

    def test_regression_release_requires_complete_operational_panel(self):
        verifier = self.read(
            "src/30_ministry_irt_report/verify_measurement_release.R"
        )
        self.assertIn("length(observed_nodes) != 66L", verifier)
        self.assertIn("Cohort 3 Arabic Grades 1--2", verifier)
        self.assertIn('c("baseline|1", "endline|1", "baseline|2", "endline|2")', verifier)
        self.assertIn('file.path(repo_root, "src/22_treatment_effects")', verifier)
        self.assertIn('file.path(repo_root, "src/30_ministry_irt_report")', verifier)

    def test_every_report_build_runs_the_measurement_gate(self):
        master = self.read("src/30_ministry_irt_report/00_master.do")
        gate = master.index('"${CODE}/verify_measurement_release.R"')
        cache_branch = master.index("if `reuse_estimates' == 0")
        self.assertLess(gate, cache_branch)
        self.assertIn('00_master_`run_stamp\'.log', master)

    def test_repository_guard_checks_index_paths_even_if_worktree_file_is_absent(self):
        guard = self.read("scripts/check_repository_data_boundary.py")
        self.assertNotIn("(REPO_ROOT / path).is_file()", guard)
        hook = self.read(".githooks/pre-commit")
        self.assertIn("--all-tracked", hook)

    def test_robustness_grid_includes_score_and_sample_checks(self):
        master = self.read("src/30_ministry_irt_report/00_master.do")
        match = re.search(r'global ROBUSTNESS_METHODS "([^"]+)"', master)
        self.assertIsNotNone(match)
        methods = match.group(1).split()
        self.assertEqual(len(methods), 18)
        self.assertIn("primary_wle", methods)
        self.assertIn("ministry_sum_same_sample", methods)

    def test_ministry_tieout_uses_delivered_stable_table(self):
        qa = self.read("src/30_ministry_irt_report/qa/adversarial_review.R")
        self.assertIn("table-prelim-ITT-3year-stable-sample.tex", qa)
        self.assertNotIn("stable_ministry_reference", qa)
        self.assertIn('"sum_score_same_sample_matches_primary"', qa)
        self.assertIn('"critical"', qa)

    def test_reader_appendix_distinguishes_location_scale_and_coverage(self):
        appendix = self.read("src/30_ministry_irt_report/report/irt_technical_appendix.tex")
        self.assertIn("scale factor", appendix)
        self.assertIn("does \\emph{not} automatically cancel", appendix)
        self.assertIn("a missing link changes which students can be scored", appendix)
        self.assertNotIn("no eligible binary questions", appendix)


if __name__ == "__main__":
    unittest.main()
