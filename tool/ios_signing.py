"""Validate the profile and derive explicit Xcode signing/export settings."""

from datetime import datetime, timezone
import os
from pathlib import Path
import plistlib
import re

BUNDLE_ID = "ar.com.lucasgrasso.trenBnHorarios"


def export_options(profile: dict, method: str, now: datetime) -> dict:
    if method not in {"app-store-connect", "release-testing"}:
        raise ValueError("IOS_EXPORT_METHOD must be app-store-connect or release-testing")
    if profile["ExpirationDate"].replace(tzinfo=timezone.utc) <= now:
        raise ValueError("iOS provisioning profile has expired")
    team = profile["TeamIdentifier"][0]
    profile_uuid = profile["UUID"]
    if not re.fullmatch(r"[A-Z0-9]+", team) or not re.fullmatch(r"[A-Fa-f0-9-]+", profile_uuid):
        raise ValueError("Invalid team ID or profile UUID")
    entitlements = profile["Entitlements"]
    prefix = profile["ApplicationIdentifierPrefix"][0]
    if entitlements.get("application-identifier") != f"{prefix}.{BUNDLE_ID}":
        raise ValueError(f"Profile must match the app's explicit bundle ID: {BUNDLE_ID}")
    if entitlements.get("get-task-allow") or profile.get("ProvisionsAllDevices"):
        raise ValueError("Use an Apple Distribution profile for App Store or Ad Hoc")
    ad_hoc = bool(profile.get("ProvisionedDevices"))
    if ad_hoc != (method == "release-testing"):
        raise ValueError("Profile type does not match IOS_EXPORT_METHOD")
    return {
        "method": method,
        "teamID": team,
        "signingStyle": "manual",
        "signingCertificate": "Apple Distribution",
        "provisioningProfiles": {BUNDLE_ID: profile_uuid},
        "manageAppVersionAndBuildNumber": False,
    }


if __name__ == "__main__":
    scratch = Path(os.environ["RUNNER_TEMP"])
    with (scratch / "profile.plist").open("rb") as source:
        profile = plistlib.load(source)
    options = export_options(
        profile, os.environ["EXPORT_METHOD"], datetime.now(timezone.utc)
    )
    with (scratch / "ExportOptions.plist").open("wb") as destination:
        plistlib.dump(options, destination)
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as environment:
        environment.write(f"IOS_TEAM_ID={options['teamID']}\n")
        environment.write(f"IOS_PROFILE_UUID={profile['UUID']}\n")
