"""Executable-contract tests; all artifacts are synthetic and temporary."""

import json
import os
import subprocess
import tempfile
import time
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
            "discover", "list", "view", "diff", "watch",
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

    def test_malformed_signed_container_is_rejected(self):
        signed = self.root / "signed.shortcut"
        signed.write_bytes(b"AEA1not-a-real-archive")
        result = self.invoke("decompile", signed, "--json")
        self.assertEqual(result.returncode, 4)
        self.assertEqual(json.loads(result.stderr)["error"]["code"], "invalid_signed_container")

    def test_diff_typed_values_and_check_exit(self):
        left, right = self.root / "left.json", self.root / "right.json"
        self.success("create", left)
        project = json.loads(left.read_text())
        right.write_text(json.dumps(project))
        self.assertTrue(self.success("diff", left, right, "--check")["equal"])
        project["workflow"]["custom"] = {"$plist": "data", "value": "AP8="}
        right.write_text(json.dumps(project))
        result = self.invoke("diff", left, right, "--check", "--json")
        self.assertEqual(result.returncode, 8)
        self.assertEqual(result.stderr, b"")
        report = json.loads(result.stdout)
        self.assertFalse(report["ok"])
        self.assertEqual(report["data"]["changes"][0]["path"], "/workflow/custom")
        self.assertFalse(self.success("diff", left, right)["equal"])
        human = self.invoke("diff", left, right)
        self.assertEqual(human.returncode, 0)
        self.assertIn(b'"$plist":"data"', human.stdout)
        self.assertIn(b"+ ", human.stdout)

    def test_discover_metadata_and_workflow(self):
        result = self.success("discover", "--query", "gettext")
        self.assertEqual(len(result["actions"]), 1)
        self.assertEqual(result["actions"][0]["kind"], "compatibility")
        metadata = self.root / "extract.actionsdata"
        metadata.write_text(json.dumps({"actions": {"Example": {"identifier": "Example", "title": {"key": "Test Title"}, "parameters": [{"name": "input"}], "custom": None}}}))
        result = self.success("discover", "--metadata", metadata, "--identifier", "Example")
        self.assertEqual(result["actions"][0]["parameters"], ["input"])
        self.assertIn("custom", result["actions"][0]["metadataJSON"])
        project = self.root / "source.json"
        self.success("create", project)
        result = self.success("discover", "--workflow", project)
        self.assertEqual({row["kind"] for row in result["actions"]}, {"observed"})
        self.assertFalse(self.success("discover", "--query", "NO-SUCH-ACTION")["actions"])

    def test_view_dry_run(self):
        self.assertFalse(self.success("view", "not-installed", "--dry-run")["executed"])
        result = self.invoke("list", "--folders", "--folder", "x", "--json")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stderr)["command"], "list")

    def test_watch_once_and_no_overwrite(self):
        source, output = self.root / "source.json", self.root / "result.shortcut"
        self.success("create", source)
        planned = self.success("watch", source, "--output", output, "--dry-run")
        self.assertTrue(planned["dryRun"])
        self.assertEqual(planned["event"], "planned")
        self.assertFalse(output.exists())
        event = self.success("watch", source, "--output", output, "--once")
        self.assertEqual(event["event"], "built")
        original = output.read_bytes()
        result = self.invoke("watch", source, "--output", output, "--once", "--json")
        self.assertEqual(result.returncode, 5)
        self.assertEqual(output.read_bytes(), original)
        self.success("watch", source, "--output", output, "--once", "--force")
        self.success("watch", source, "--once")

    def test_watch_recovers_from_invalid_source_and_atomic_save(self):
        source, output = self.root / "source.json", self.root / "result.shortcut"
        self.success("create", source)
        project = json.loads(source.read_text())
        with tempfile.TemporaryFile() as events, tempfile.TemporaryFile() as errors:
            process = subprocess.Popen([BINARY, "watch", str(source), "--output", str(output), "--interval", "0.02", "--debounce", "0.05", "--duration", "1.8", "--json"], stdout=events, stderr=errors)
            try:
                deadline = time.monotonic() + 1
                while not output.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(output.exists())
                before = output.read_bytes()
                source.write_text("{")
                time.sleep(0.25)
                self.assertEqual(output.read_bytes(), before)
                project["workflow"]["custom"] = "new"
                replacement = self.root / "replacement.json"
                replacement.write_text(json.dumps(project))
                replacement.replace(source)
                self.assertEqual(process.wait(timeout=5), 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
            events.seek(0)
            rows = [json.loads(row) for row in events.read().splitlines()]
            self.assertEqual([row["data"]["event"] for row in rows], ["built", "failed", "built"])
            self.assertFalse(rows[1]["ok"])
            self.assertNotEqual(output.read_bytes(), before)
            errors.seek(0)
            self.assertEqual(errors.read(), b"")

    def test_watch_pins_output_parent_and_preserves_external_edits(self):
        input_dir, output_dir = self.root / "input", self.root / "output"
        input_dir.mkdir()
        output_dir.mkdir()
        alias = self.root / "alias"
        alias.symlink_to(output_dir, target_is_directory=True)
        source = input_dir / "workflow.json"
        destination = output_dir / "workflow.json"
        self.success("create", source)
        project = json.loads(source.read_text())
        with tempfile.TemporaryFile() as events:
            process = subprocess.Popen([BINARY, "watch", str(source), "--output", str(alias / "workflow.json"), "--interval", "0.02", "--debounce", "0.04", "--duration", "1.7", "--json"], stdout=events, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 1
                while not destination.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(destination.exists())
                alias.unlink()
                alias.symlink_to(input_dir, target_is_directory=True)
                project["workflow"]["custom"] = "changed"
                source.write_text(json.dumps(project))
                time.sleep(0.3)
                self.assertEqual(json.loads(source.read_text()), project)
                destination.write_bytes(b"external work")
                project["workflow"]["custom"] = "changed again"
                source.write_text(json.dumps(project))
                _, errors = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 0, errors)
                self.assertEqual(destination.read_bytes(), b"external work")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
            events.seek(0)
            rows = [json.loads(row) for row in events.read().splitlines()]
            self.assertEqual([row["data"]["event"] for row in rows], ["built", "built", "failed"])
            self.assertEqual(rows[-1]["data"]["error"]["code"], "output_changed")

    def test_watch_reports_initial_failures_and_unsafe_paths(self):
        source = self.root / "source.json"
        source.write_text("{")
        result = self.invoke("watch", source, "--once", "--json")
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stderr, b"")
        self.assertFalse(json.loads(result.stdout)["ok"])
        result = self.invoke("watch", self.root / "missing", "--once", "--json")
        self.assertEqual(result.returncode, 5)
        self.assertEqual(json.loads(result.stdout)["data"]["error"]["code"], "read_failed")
        self.success("create", source, "--force")
        for args in [
            ["--output", source],
            ["--interval", "nan"],
            ["--debounce", "-1"],
            ["--duration", "inf"],
        ]:
            with self.subTest(args=args):
                self.assertNotEqual(self.invoke("watch", source, "--once", *args, "--json").returncode, 0)
        project = json.loads(source.read_text())
        project["workflow"]["WFWorkflowActions"][0]["WFWorkflowActionIdentifier"] = "example.future"
        source.write_text(json.dumps(project))
        self.success("watch", source, "--once")
        result = self.invoke("watch", source, "--once", "--strict", "--json")
        self.assertEqual(result.returncode, 3)
        self.assertEqual(json.loads(result.stdout)["data"]["diagnostics"][0]["code"], "unknown_action")

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
