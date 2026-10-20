from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ios_signing import BUNDLE_ID, export_options
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


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 20, tzinfo=timezone.utc)
        self.profile = {
            "ExpirationDate": datetime(2027, 1, 1),
            "TeamIdentifier": ["ABC1234567"],
            "UUID": "12345678-ABCD-1234-ABCD-123456789012",
            "ApplicationIdentifierPrefix": ["ABC1234567"],
            "Entitlements": {"application-identifier": f"ABC1234567.{BUNDLE_ID}", "get-task-allow": False},
        }

    def test_app_store_profile_exports_with_manual_signing(self):
        options = export_options(self.profile, "app-store-connect", self.now)
        self.assertEqual(options["provisioningProfiles"][BUNDLE_ID], self.profile["UUID"])
        self.assertFalse(options["manageAppVersionAndBuildNumber"])

    def test_ad_hoc_profile_requires_release_testing(self):
        self.profile["ProvisionedDevices"] = ["test-device"]
        self.assertEqual(export_options(self.profile, "release-testing", self.now)["method"], "release-testing")
        with self.assertRaises(ValueError):
            export_options(self.profile, "app-store-connect", self.now)

    def test_rejects_expired_development_enterprise_and_wrong_app_profiles(self):
        for change in [
            {"ExpirationDate": datetime(2026, 1, 1)},
            {"Entitlements": {"application-identifier": "ABC1234567.other"}},
            {"Entitlements": {"application-identifier": f"ABC1234567.{BUNDLE_ID}", "get-task-allow": True}},
            {"ProvisionsAllDevices": True},
        ]:
            with self.subTest(change=change):
                profile = deepcopy(self.profile)
                profile.update(change)
                with self.assertRaises(ValueError):
                    export_options(profile, "app-store-connect", self.now)

    def test_rejects_unknown_export_method(self):
        with self.assertRaises(ValueError):
            export_options(self.profile, "development", self.now)


if __name__ == "__main__":
    unittest.main()
