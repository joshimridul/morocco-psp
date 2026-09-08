from pathlib import Path
import importlib.util
import tempfile
import unittest


MODULE_PATH = Path(__file__).parents[1] / "src" / "00_inventory" / "path_guard.py"
SPEC = importlib.util.spec_from_file_location("path_guard", MODULE_PATH)
path_guard = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(path_guard)


class PathGuardTest(unittest.TestCase):
    def test_output_below_work_root_is_allowed(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            work = base / "work"
            source = base / "source"
            output = work / "outputs" / "table.csv"
            result = path_guard.assert_output_path(output, work, [source])
            self.assertEqual(result, output.resolve())

    def test_output_in_source_root_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            work = base / "work"
            source = base / "source"
            with self.assertRaises(ValueError):
                path_guard.assert_output_path(source / "new.csv", work, [source])

    def test_output_equal_to_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            work = base / "work"
            source = base / "source"
            input_path = work / "derived" / "input.csv"
            with self.assertRaises(ValueError):
                path_guard.assert_output_path(input_path, work, [source], [input_path])

    def test_direct_identifier_columns_are_rejected(self):
        with self.assertRaises(ValueError):
            path_guard.assert_no_direct_identifier_columns(["subject", "massar_code"])

    def test_project_specific_identifier_columns_are_rejected(self):
        for column in ("id_student_panel", "student_id", "school_id", "cd_etab"):
            with self.subTest(column=column), self.assertRaises(ValueError):
                path_guard.assert_no_direct_identifier_columns(["subject", column])

    def test_aggregate_school_count_is_allowed(self):
        path_guard.assert_no_direct_identifier_columns(
            ["subject", "n_students", "n_schools", "n_pairs"]
        )


if __name__ == "__main__":
    unittest.main()
