#!/usr/bin/env python3
"""Run unit/CLI contracts and enforce combined first-party line coverage."""

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*arguments, **kwargs):
    return subprocess.run(arguments, cwd=ROOT, check=True, **kwargs)


def main():
    run("swift", "test", "--enable-code-coverage")
    run("swift", "build", "--enable-code-coverage")
    binary_directory = Path(
        run(
            "swift", "build", "--show-bin-path", capture_output=True, text=True
        ).stdout.strip()
    )
    binary = binary_directory / "shortcutctl"
    unit_profile = binary_directory / "codecov/default.profdata"
    if not unit_profile.is_file():
        raise SystemExit(f"Swift test did not produce {unit_profile}")
    destination = ROOT / "coverage"
    destination.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="cli-coverage-", dir=ROOT / ".build"
    ) as temporary:
        profiles = Path(temporary)
        environment = dict(os.environ)
        environment["SHORTCUTCTL_BIN"] = str(binary)
        environment["LLVM_PROFILE_FILE"] = str(profiles / "cli-%p.profraw")
        run(
            "python3",
            "-m",
            "unittest",
            "discover",
            "-s",
            "Tests/CLI",
            "-v",
            env=environment,
        )
        raw_profiles = sorted(profiles.glob("*.profraw"))
        if not raw_profiles:
            raise SystemExit("CLI coverage instrumentation produced no profiles")
        merged = profiles / "merged.profdata"
        run(
            "xcrun",
            "llvm-profdata",
            "merge",
            "-sparse",
            str(unit_profile),
            *map(str, raw_profiles),
            "-o",
            str(merged),
        )
        options = [
            str(binary),
            f"-instr-profile={merged}",
            "-ignore-filename-regex=(/\\.build/|/Tests/)",
        ]
        report = run(
            "xcrun", "llvm-cov", "report", *options, capture_output=True, text=True
        ).stdout
        (destination / "report.txt").write_text(report)
        print(report)
        exported = run(
            "xcrun", "llvm-cov", "export", *options, capture_output=True
        ).stdout
        summary = json.loads(exported)["data"][0]["totals"]
        (destination / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        if summary["lines"]["percent"] < 80:
            raise SystemExit("First-party line coverage is below 80%")


if __name__ == "__main__":
    main()
