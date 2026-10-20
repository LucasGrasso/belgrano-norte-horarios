"""Validate release metadata before allocating mobile build runners."""

import os
from pathlib import Path
import re


def release_version(pubspec: str, ref_type: str, tag: str) -> tuple[str, str]:
    if ref_type != "tag":
        raise ValueError("Select an existing vX.Y.Z tag, not a branch")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$", pubspec, re.M)
    if not match:
        raise ValueError("pubspec.yaml must have version: X.Y.Z+N with positive N")
    version, number = match.groups()
    if tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} does not match pubspec.yaml v{version}")
    if int(number) > 2_100_000_000:
        raise ValueError("Build number exceeds Android's versionCode limit")
    return version, number


if __name__ == "__main__":
    try:
        name, number = release_version(
            Path("pubspec.yaml").read_text(),
            os.environ.get("GITHUB_REF_TYPE", ""),
            os.environ.get("GITHUB_REF_NAME", ""),
        )
    except ValueError as error:
        raise SystemExit(str(error)) from error
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"name={name}\nnumber={number}\n")
