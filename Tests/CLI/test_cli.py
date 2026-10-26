"""Executable-contract tests; all artifacts are synthetic and temporary."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

BINARY = os.environ.get("SHORTCUTCTL_BIN", ".build/debug/shortcutctl")


class CLIContractTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="shortcutctl-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def invoke(self, *arguments):
        return subprocess.run(
            [BINARY, *map(str, arguments)], check=False, capture_output=True, timeout=15
        )

    def success(self, *arguments):
        result = self.invoke(*arguments, "--json")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(result.stderr, b"")
        envelope = json.loads(result.stdout)
        self.assertTrue(envelope["ok"])
        self.assertEqual(envelope["schemaVersion"], 1)
        return envelope["data"]

    def test_help_for_every_command(self):
        for command in [
            "create",
            "build",
            "inspect",
            "decompile",
            "lint",
            "run",
            "test",
        ]:
            with self.subTest(command=command):
                result = self.invoke(command, "--help")
                self.assertEqual(result.returncode, 0)
                self.assertIn(b"--json", result.stdout)

    def test_round_trip_project_to_plist_to_project(self):
        project, workflow, restored = [
            self.root / name
            for name in ["source.json", "workflow.shortcut", "restored.json"]
        ]
        self.success(
            "create", project, "--name", "Test 世界", "--template", "dictionary"
        )
        self.success("lint", project)
        build = self.success("build", project, "--output", workflow)
        self.assertFalse(build["signed"])
        inspected = self.success("inspect", workflow)
        self.assertEqual(inspected["actionCount"], 4)
        self.success("decompile", workflow, "--output", restored)
        self.assertEqual(
            json.loads(project.read_text())["workflow"],
            json.loads(restored.read_text())["workflow"],
        )

    def test_no_overwrite_and_dry_run(self):
        project = self.root / "project.json"
        self.success("create", project, "--dry-run")
        self.assertFalse(project.exists())
        self.success("create", project)
        before = project.read_bytes()
        result = self.invoke("create", project, "--json")
        self.assertEqual(result.returncode, 5)
        self.assertEqual(json.loads(result.stderr)["error"]["code"], "output_exists")
        self.assertEqual(project.read_bytes(), before)
        output = self.root / "build.shortcut"
        self.success("build", project, "--output", output, "--dry-run")
        self.assertFalse(output.exists())

    def test_json_parse_errors_and_chinese_diagnostics(self):
        result = self.invoke("build", "--unknown-option", "--json", "--language", "zh")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        failure = json.loads(result.stderr)
        self.assertFalse(failure["ok"])
        self.assertEqual(failure["error"]["code"], "invalid_arguments")
        self.assertTrue(failure["error"]["messageZH"])
        result = self.invoke("inspect", self.root / "missing", "--language", "zh")
        self.assertEqual(result.returncode, 5)
        self.assertIn("文件操作失败", result.stderr.decode())

    def test_signed_container_is_explicitly_unsupported(self):
        signed = self.root / "signed.shortcut"
        signed.write_bytes(b"AEA1not-a-real-archive")
        result = self.invoke("decompile", signed, "--json")
        self.assertEqual(result.returncode, 4)
        self.assertEqual(
            json.loads(result.stderr)["error"]["code"], "signed_container_unsupported"
        )

    def test_invalid_workflow_and_strict_unknown_actions(self):
        project = self.root / "bad.json"
        project.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "name": "Bad",
                    "workflow": {"WFWorkflowActions": "invalid"},
                }
            )
        )
        result = self.invoke("lint", project, "--json")
        self.assertEqual(result.returncode, 3)
        envelope = json.loads(result.stdout)
        self.assertFalse(envelope["ok"])
        self.assertEqual(envelope["data"]["diagnostics"][0]["code"], "invalid_actions")
        project.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "name": "Unknown",
                    "workflow": {
                        "WFWorkflowActions": [
                            {
                                "WFWorkflowActionIdentifier": "example.unknown",
                                "WFWorkflowActionParameters": {},
                            }
                        ]
                    },
                }
            )
        )
        self.success("lint", project)
        result = self.invoke("lint", project, "--strict", "--json")
        self.assertEqual(result.returncode, 3)

    def test_native_dry_run_does_not_execute(self):
        planned = self.success("run", "intentionally-not-installed", "--dry-run")
        self.assertTrue(planned["dryRun"])
        self.assertFalse(planned["executed"])
        project = self.root / "project.json"
        self.success("create", project)
        planned = self.success(
            "test", project, "--shortcut", "intentionally-not-installed", "--dry-run"
        )
        self.assertFalse(planned["executed"])
        self.assertEqual(len(planned["cases"]), 2)

    def test_native_failure_does_not_report_success(self):
        result = self.invoke(
            "run",
            "shortcutctl-nonexistent-4D4CA480-6845-437B-97CC-4A5568DF9A04",
            "--timeout",
            "3",
            "--json",
        )
        self.assertIn(result.returncode, [6, 124])
        self.assertFalse(json.loads(result.stderr)["ok"])

    def test_build_is_deterministic_across_processes(self):
        project = self.root / "project.json"
        self.success("create", project, "--template", "dictionary")
        for encoding in ["xml", "binary"]:
            with self.subTest(encoding=encoding):
                outputs = []
                for index in range(3):
                    output = self.root / f"{encoding}-{index}.shortcut"
                    self.success(
                        "build", project, "--output", output, "--format", encoding
                    )
                    outputs.append(output.read_bytes())
                self.assertEqual(len(set(outputs)), 1)


if __name__ == "__main__":
    unittest.main()
