from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release_version import release_version


class ReleaseVersionTests(unittest.TestCase):
    def test_reads_app_version_and_build_number(self):
        self.assertEqual(release_version("version: 1.2.3+42\n", "tag", "v1.2.3"), ("1.2.3", "42"))

    def test_rejects_branch_runs_mismatches_and_invalid_builds(self):
        for version, ref_type, tag in [
            ("1.2.3+42", "branch", "main"),
            ("1.2.3+42", "tag", "v1.2.4"),
            ("1.2.3+0", "tag", "v1.2.3"),
            ("1.2.3", "tag", "v1.2.3"),
            ("1.2.3+2100000001", "tag", "v1.2.3"),
            ("1.2.3-rc.1+42", "tag", "v1.2.3-rc.1"),
        ]:
            with self.subTest(version=version, ref_type=ref_type, tag=tag):
                with self.assertRaises(ValueError):
                    release_version(f"version: {version}\n", ref_type, tag)


if __name__ == "__main__":
    unittest.main()
