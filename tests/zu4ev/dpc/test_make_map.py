import importlib.util
import tempfile
import unittest
from pathlib import Path

path = Path(__file__).resolve().parents[3] / "platform/zu4ev/isp/dpc/make_map.py"
spec = importlib.util.spec_from_file_location("dpc_map", path)
dpc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dpc)


class MapTest(unittest.TestCase):
    def test_cluster_and_edges(self):
        points = {(0, 0), (1, 0), (63, 0), (1, 1), (2, 1), (3, 1)}
        self.assertEqual(dpc.make_runs(points, 64, 32), [(0, 0, 2), (63, 0, 1), (1, 1, 3)])

    def test_unrepairable(self):
        with self.assertRaisesRegex(ValueError, "unrepairable"):
            dpc.make_runs({(x, 0) for x in range(33)}, 64, 32)
        with self.assertRaisesRegex(ValueError, "unrepairable"):
            dpc.make_runs({(x, 0) for x in range(32)}, 32, 32)
        with self.assertRaisesRegex(ValueError, "1024 runs"):
            dpc.make_runs({(x, y) for x in range(0, 128, 2) for y in range(17)}, 128, 32)

    def test_repeated_vs_transient(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "survey.txt"
            p.write_text("DPC_SURVEY1 64 32 32 raw high 128\n0 0 32\n1 0 31\n2 0 30\nEND 3\n")
            points, meta = dpc.read_survey(p, 64, 32, 0.95)
            self.assertEqual(points, {(0, 0), (1, 0)})
            self.assertEqual(meta["min_hits"], 31)

    def test_truncated_duplicate_or_processed_survey(self):
        cases = ["0 0 32\n", "0 0 32\n0 0 32\nEND 2\n"]
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "survey.txt"
            for rows in cases:
                p.write_text("DPC_SURVEY1 64 32 32 raw high 128\n" + rows)
                with self.assertRaises(ValueError):
                    dpc.read_survey(p, 64, 32, 0.95)
            p.write_text("DPC_SURVEY1 64 32 32 corrected high 128\nEND 0\n")
            with self.assertRaises(ValueError):
                dpc.read_survey(p, 64, 32, 0.95)


if __name__ == "__main__":
    unittest.main()
