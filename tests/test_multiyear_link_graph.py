import importlib.util
import pathlib
import unittest


MODULE_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "src/21_y1_y3_irt/build_multiyear_link_graph.py"
)
SPEC = importlib.util.spec_from_file_location("build_multiyear_link_graph", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class MultiyearLinkGraphTest(unittest.TestCase):
    def test_exact_occurrence_hash_requires_single_current_and_compiled_hash(self):
        self.assertEqual(MODULE.exact_occurrence_hash({"same"}, {"same"}), "same")
        self.assertEqual(MODULE.exact_occurrence_hash({"same", "other"}, {"same"}), "")
        self.assertEqual(MODULE.exact_occurrence_hash({"same"}, {"other"}), "")

    def test_selected_paths_require_five_anchors_on_every_edge(self):
        nodes = {"Y2|endline|Arabic|2", "Y3|baseline|Arabic|1"}
        subjects = {node: "Arabic" for node in nodes}
        rows = MODULE.selected_paths(
            nodes,
            subjects,
            {"Y2|endline|Arabic|2": 7},
            {("Y2|endline|Arabic|2", "Y3|baseline|Arabic|1"): 4},
            "strict_summary",
        )
        status = {row["node_id"]: row["path_status"] for row in rows}
        self.assertEqual(status["Y2|endline|Arabic|2"], "linked_development_only")
        self.assertEqual(
            status["Y3|baseline|Arabic|1"], "no_path_with_5_anchors_per_edge"
        )

    def test_direct_link_is_preferred_to_longer_bridge(self):
        nodes = {
            "Y2|endline|French|2",
            "Y3|baseline|French|2",
        }
        subjects = {node: "French" for node in nodes}
        rows = MODULE.selected_paths(
            nodes,
            subjects,
            {
                "Y2|endline|French|2": 20,
                "Y3|baseline|French|2": 5,
            },
            {("Y2|endline|French|2", "Y3|baseline|French|2"): 40},
            "strict_summary",
        )
        target = next(row for row in rows if row["node_id"] == "Y3|baseline|French|2")
        self.assertEqual(target["path_depth"], 1)
        self.assertEqual(target["parent_node_id"], "Y1|reference|French")


if __name__ == "__main__":
    unittest.main()
