#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Effortless Metrics, Inc.

"""Portable tests of the real workflow pipeline and its bounded resource watcher."""

from dataclasses import replace
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import Mock, patch

import ci_resource_watch as watch


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
SUITE_STEP = "Full Test Suite + Coverage Gate + Xcode Unit/UI Tests"
UPLOAD_STEP = "Preserve full-suite diagnostics"
UPLOAD_SHA = "ea165f8d65b6e75b540449e92b4886f43607fa02"


def step_match(workflow, name):
    """Find a unique real step header, never the same words in a comment."""
    matches = list(re.finditer(
        r"^      - name: " + re.escape(name) + r"\n((?:^        .*\n|^\n)*)",
        workflow, re.MULTILINE,
    ))
    if len(matches) != 1:
        raise AssertionError(f"Expected exactly one CI step: {name}")
    return matches[0]


def workflow_contract(workflow):
    """Check exact budgets, order, controls and the verified upload identity."""
    suite = step_match(workflow, SUITE_STEP)
    upload = step_match(workflow, UPLOAD_STEP)
    coverage = step_match(workflow, "Coverage gate (60% minimum)")
    assert suite.start() < upload.start() < coverage.start(), "Incorrect step order"
    body = suite[1]
    upload_body = upload[1]
    assert re.search(r"^        if: always\(\)$", upload_body, re.MULTILINE)
    assert re.search(
        r"^        uses: actions/upload-artifact@" + UPLOAD_SHA + r" # v4$",
        upload_body, re.MULTILINE,
    )
    assert re.search(r"^            artifacts/ci$", upload_body, re.MULTILINE)
    assert "SwiftMTPKit/coverage/test_output.log" in upload_body
    assert not re.search(r"^        continue-on-error:", body, re.MULTILINE)
    job = re.search(r"^  build-test:\n(.*?)(?=^  [\w-]+:|\Z)", workflow, re.MULTILINE | re.DOTALL)
    assert job is not None
    for section, indent, limit in ((job[1], 4, 90), (body, 8, 75), (upload_body, 8, 5)):
        matches = re.findall(r"^" + " " * indent + r"timeout-minutes: (\d+)$", section, re.MULTILINE)
        assert matches == [str(limit)], "Missing, repeated or incorrect deadline"
    assert 'COVERAGE_THRESHOLD: "60"' in body
    assert 'RUN_XCODE_UI_TESTS: "1"' in body
    assert "./run-all-tests.sh 2>&1 | tee artifacts/ci/full-suite.log\n" in body


FAKE_WATCHER = '''import argparse
import os
from pathlib import Path
import time
p = argparse.ArgumentParser()
p.add_argument("--root-pid")
p.add_argument("--output-dir")
p.add_argument("--stop-file", type=Path)
a = p.parse_args()
Path("watcher-started").write_text(str(os.getpid()))
print("watcher output stays separate", flush=True)
end = time.monotonic() + 5
while not a.stop_file.exists() and os.getppid() == int(a.root_pid) and time.monotonic() < end:
    time.sleep(0.01)
if not a.stop_file.exists() and os.getppid() == int(a.root_pid):
    raise SystemExit(91)
time.sleep(0.05)
Path("watcher-stopped").write_text("stopped")
raise SystemExit(17)
'''


class WorkflowDiagnosticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")
        cls.suite = step_match(cls.workflow, SUITE_STEP)[1]
        cls.command = textwrap.dedent(cls.suite.split("        run: |\n", 1)[1])

    def run_fixture(self, status, failing_tee=False, command=None, watcher=FAKE_WATCHER):
        """Run the actual shell block with a fake suite/watcher; return result and files."""
        with tempfile.TemporaryDirectory(prefix="swiftmtp-ci-diagnostics-") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "scripts/ci_resource_watch.py").write_text(watcher, encoding="utf-8")
            suite = root / "run-all-tests.sh"
            suite.write_text(
                "#!/usr/bin/env bash\n"
                "for attempt in {1..300}; do\n"
                "  [[ -f watcher-started ]] && break\n"
                "  sleep 0.01\n"
                "done\n"
                "[[ -f watcher-started ]] || exit 92\n"
                "printf 'fixture stdout\\n'\n"
                "printf 'fixture stderr\\n' >&2\n"
                f"exit {status}\n", encoding="utf-8",
            )
            suite.chmod(0o755)
            env = os.environ.copy()
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            if failing_tee:
                bin_dir = root / "bin"
                bin_dir.mkdir()
                tee = bin_dir / "tee"
                tee.write_text("#!/bin/sh\ncat >/dev/null\nexit 23\n", encoding="utf-8")
                tee.chmod(0o755)
                env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]
            result = subprocess.run(
                ["bash", "-e", "-c", self.command if command is None else command],
                cwd=root, env=env, text=True, capture_output=True, timeout=10, check=False,
            )
            # Marker-write failure uses the watcher's parent-loss exit instead
            # of waiting forever. Allow that bounded cleanup before removing fixtures.
            if watcher == FAKE_WATCHER:
                import time
                for _ in range(100):
                    if (root / "watcher-stopped").exists():
                        break
                    time.sleep(0.01)
            files = {}
            for name in ("artifacts/ci/full-suite.log", "artifacts/ci/watcher.log", "watcher-stopped"):
                path = root / name
                files[name] = path.read_text(encoding="utf-8") if path.exists() else None
            return result, files

    def test_success_keeps_stdout_and_stderr_and_joins_watcher(self):
        result, files = self.run_fixture(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(files["artifacts/ci/full-suite.log"], "fixture stdout\nfixture stderr\n")
        self.assertEqual(result.stdout, files["artifacts/ci/full-suite.log"])
        self.assertIn("watcher output stays separate", files["artifacts/ci/watcher.log"])
        self.assertEqual(files["watcher-stopped"], "stopped")

    def test_failing_suite_survives_successful_tee_and_watcher_exit_17(self):
        result, files = self.run_fixture(42)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(files["watcher-stopped"], "stopped")

    def test_missing_pipefail_negative_control_is_falsely_green(self):
        result, _ = self.run_fixture(42, command=self.command.replace("set -o pipefail\n", ""))
        self.assertEqual(result.returncode, 0)

    def test_tee_failure_is_preserved_and_watcher_is_joined(self):
        result, files = self.run_fixture(0, failing_tee=True)
        self.assertEqual(result.returncode, 23)
        self.assertEqual(files["watcher-stopped"], "stopped")

    def test_early_watcher_failure_does_not_replace_suite_result(self):
        watcher = "from pathlib import Path\nPath('watcher-started').touch()\nraise SystemExit(17)\n"
        for status in (0, 42):
            with self.subTest(status=status):
                result, _ = self.run_fixture(status, watcher=watcher)
                self.assertEqual(result.returncode, status)

    def test_stop_marker_write_failure_preserves_exit_and_parent_loss_stops_watcher(self):
        command = self.command.replace(': > "$watch_dir/stop"', ': > "$watch_dir"')
        result, files = self.run_fixture(42, command=command)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(files["watcher-stopped"], "stopped")

    def test_actual_configuration(self):
        workflow_contract(self.workflow)

    def test_timeout_comment_cannot_hide_invalid_budget(self):
        invalid = self.workflow.replace(
            "        timeout-minutes: 75\n",
            "        # timeout-minutes: 75\n        timeout-minutes: 85\n",
        )
        with self.assertRaises(AssertionError):
            workflow_contract(invalid)

    def test_name_comment_cannot_hide_upload_before_suite(self):
        suite = step_match(self.workflow, SUITE_STEP)
        upload = step_match(self.workflow, UPLOAD_STEP)
        invalid = (
            self.workflow[:suite.start()] + "      # " + SUITE_STEP + "\n"
            + upload[0] + suite[0] + self.workflow[upload.end():]
        )
        with self.assertRaises(AssertionError):
            workflow_contract(invalid)

    def test_floating_or_unrelated_upload_action_is_rejected(self):
        for action in ("actions/upload-artifact@v4", "unrelated/action@" + UPLOAD_SHA):
            with self.subTest(action=action), self.assertRaises(AssertionError):
                workflow_contract(self.workflow.replace("actions/upload-artifact@" + UPLOAD_SHA, action))

    def test_duplicate_named_step_is_rejected(self):
        with self.assertRaises(AssertionError):
            step_match(self.workflow + "      - name: " + UPLOAD_STEP + "\n", UPLOAD_STEP)


def process(pid, ppid, comm="bash", started="Sun Nov 8 05:00:00 2026"):
    return watch.Process(pid, ppid, 10, 1024, 1.0, "S", "00:30", started, comm)


class WatcherPolicyTests(unittest.TestCase):
    def setUp(self):
        self.root = process(10, 1)
        self.driver = process(20, 10, "swift-test")
        self.host = process(30, 20, "swiftpm-xctest-helper")
        self.snapshot = {p.pid: p for p in (
            self.root, self.driver, self.host, process(21, 10, "tee"),
            process(90, 10, "python3"), process(91, 90, "sample"),
            process(92, 90, "ps"), process(100, 1, "xctest"),
        )}

    def test_ps_parser_uses_executable_names_not_arguments(self):
        parsed = watch.parse_processes(
            " 30 20 10 1234 2.5 S 01:03 Sun Nov 8 05:00:00 2026 /path/with spaces/xctest\n"
            " malformed\n"
        )
        self.assertEqual(parsed[30].started, "Sun Nov 8 05:00:00 2026")
        self.assertEqual(parsed[30].comm, "/path/with spaces/xctest")
        self.assertEqual(parsed[30].rss_kib, 1234)
        self.assertNotIn("args", watch.PS_COMMAND[-1])
        self.assertNotIn("command", watch.PS_COMMAND[-1])

    def test_descendants_exclude_watcher_unrelated_and_cycles(self):
        snapshot = dict(self.snapshot)
        snapshot[110] = process(110, 111)
        snapshot[111] = process(111, 110)
        self.assertEqual(set(watch.descendants(snapshot, 10, 90)), {20, 21, 30})

    def test_candidate_order_and_relevant_tees(self):
        owned = watch.descendants(self.snapshot, 10, 90)
        owned[40] = process(40, 30, "tee")  # Test-internal tee is not the runner pipeline.
        self.assertEqual([p.pid for p in watch.capture_candidates(owned, 10)], [30, 20, 21])

    def test_changed_pid_birth_parent_root_or_exec_is_not_owned(self):
        for changed in (
            replace(self.host, started="Sun Nov 8 05:10:00 2026"),
            replace(self.host, ppid=100), replace(self.host, comm="unrelated"),
        ):
            snapshot = {**self.snapshot, changed.pid: changed}
            self.assertFalse(watch.same_owned_process(snapshot, self.root, self.host, 90))
        snapshot = {**self.snapshot, 10: replace(self.root, started="new root")}
        self.assertFalse(watch.same_owned_process(snapshot, self.root, self.host, 90))

    def test_compilation_or_marker_alone_does_not_arm_capture(self):
        for hosts, marker in (([], True), ([self.host], False)):
            state = watch.StallState()
            self.assertFalse(state.observe(0, {"log": 100}, hosts, marker))
            self.assertFalse(state.observe(1000, {"log": 100}, hosts, marker))

    def test_stall_requires_120_seconds_after_xctest_and_is_one_shot(self):
        state = watch.StallState()
        self.assertFalse(state.observe(0, {"log": 100}, [], False))
        self.assertFalse(state.observe(900, {"log": 100}, [self.host], True))
        self.assertFalse(state.observe(1019, {"log": 100}, [self.host], True))
        self.assertTrue(state.observe(1020, {"log": 100}, [self.host], True))
        self.assertFalse(state.observe(2000, {"log": 100}, [self.host], True))

    def test_growth_and_new_host_restart_stall_clock(self):
        state = watch.StallState()
        state.observe(0, {"log": 100}, [self.host], True)
        self.assertFalse(state.observe(119, {"log": 101}, [self.host], True))
        self.assertFalse(state.observe(238, {"log": 101}, [self.host], True))
        replacement = replace(self.host, started="new test process")
        self.assertFalse(state.observe(239, {"log": 101}, [replacement], True))
        self.assertFalse(state.observe(358, {"log": 101}, [replacement], True))
        self.assertTrue(state.observe(359, {"log": 101}, [replacement], True))

    def test_host_exit_disarms_capture(self):
        state = watch.StallState()
        state.observe(0, {"log": 100}, [self.host], True)
        self.assertFalse(state.observe(200, {"log": 100}, [], True))

    def run_capture(self, candidates=None, snapshots=None, failure=None, stopped=lambda: False,
                    create_report=False, returncode=0):
        """Use fake diagnostic commands; this never invokes macOS sample."""
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            real_is_file = Path.is_file

            def sample_available(path):
                return True if path == Path("/usr/bin/sample") else real_is_file(path)

            def fake_sample(argv, **kwargs):
                if failure is not None:
                    raise failure
                if create_report:
                    Path(argv[argv.index("-file") + 1]).write_text("fixture stack report\n", encoding="utf-8")
                return subprocess.CompletedProcess(argv, returncode)

            run = Mock(side_effect=fake_sample)
            snapshotter = Mock(side_effect=snapshots) if snapshots else Mock(return_value=self.snapshot)
            with patch.object(watch.sys, "platform", "darwin"), patch.object(Path, "is_file", sample_available), patch.object(watch.subprocess, "run", run):
                watch.capture_once(self.root, candidates or [self.host], 90, output, stopped, snapshotter)
            records = output / "resources.jsonl"
            return run, [json.loads(line) for line in records.read_text().splitlines()] if records.exists() else []

    def test_sample_has_explicit_artifact_file_and_command_deadline(self):
        run, records = self.run_capture()
        argv = run.call_args.args[0]
        self.assertEqual(argv[:4], ["/usr/bin/sample", "30", "2", "10"])
        self.assertEqual(argv[4], "-file")
        self.assertTrue(argv[5].endswith("sample-1-30.txt"))
        self.assertEqual(run.call_args.kwargs["timeout"], 5)
        self.assertTrue(records[0]["identity_still_valid"])
        self.assertEqual(records[0]["command_output"], "sample-1-30-command.txt")

    def test_successful_sample_report_presence_uses_the_actual_artifact(self):
        for create_report in (True, False):
            with self.subTest(create_report=create_report):
                _, records = self.run_capture(create_report=create_report)
                self.assertEqual(records[0]["returncode"], 0)
                self.assertIs(records[0]["report_present"], create_report)

    def test_sample_returncode_is_retained_independently_of_report_presence(self):
        _, records = self.run_capture(returncode=17)
        self.assertEqual(records[0]["returncode"], 17)
        self.assertFalse(records[0]["report_present"])

    def test_identity_change_before_capture_prevents_sampling(self):
        reused = {**self.snapshot, 30: replace(self.host, started="reused")}
        run, records = self.run_capture(snapshots=[reused])
        run.assert_not_called()
        self.assertEqual(records[0]["event"], "sample_skipped_identity")

    def test_post_capture_identity_change_invalidates_evidence(self):
        reused = {**self.snapshot, 30: replace(self.host, started="reused")}
        _, records = self.run_capture(snapshots=[self.snapshot, reused])
        self.assertFalse(records[0]["identity_still_valid"])

    def test_unrelated_process_and_stop_marker_prevent_sampling(self):
        run, _ = self.run_capture(candidates=[self.snapshot[100]])
        run.assert_not_called()
        run, _ = self.run_capture(stopped=lambda: True)
        run.assert_not_called()

    def test_sample_error_is_recorded_without_command_arguments(self):
        for error in (OSError("secret argument"), subprocess.TimeoutExpired("secret argument", 5)):
            with self.subTest(error=type(error).__name__):
                run, records = self.run_capture(failure=error)
                self.assertEqual(run.call_count, 1)
                self.assertEqual(records[0]["event"], "sample_error")
                self.assertNotIn("secret", json.dumps(records))

    def test_sample_batch_has_hard_capture_count_bound(self):
        run, _ = self.run_capture(candidates=[self.host] * 20)
        self.assertEqual(run.call_count, watch.MAX_CAPTURES)

    def test_ps_has_timeout_and_output_size_bound(self):
        def fake_ps(*args, **kwargs):
            self.assertEqual(kwargs["timeout"], 3)
            kwargs["stdout"].write(b"x" * (watch.MAX_PS_BYTES + 1))
            return subprocess.CompletedProcess([], 0)
        with patch.object(watch.subprocess, "run", side_effect=fake_ps), self.assertRaisesRegex(RuntimeError, "bound"):
            watch.process_snapshot()

    def test_watch_stops_if_root_identity_changes(self):
        changed = {**self.snapshot, 10: replace(self.root, started="new parent")}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with patch.object(watch.os, "getppid", return_value=10), patch.object(watch.os, "getpid", return_value=90), patch.object(watch.time, "monotonic", side_effect=[0, 0, 0, 30, 30]), patch.object(watch, "process_snapshot", side_effect=[self.snapshot, changed]), patch.object(watch, "log_observation", return_value=({"log": 100}, True)):
                watch.watch(10, output, output / "stop")
            records = [json.loads(line) for line in (output / "resources.jsonl").read_text().splitlines()]
            self.assertEqual([r["event"] for r in records], ["resources", "root_identity_changed", "watch_stopped"])
            self.assertEqual({p["pid"] for p in records[0]["processes"]}, {20, 21, 30})

    def test_watch_stops_on_parent_loss_without_sampling_or_polling(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with patch.object(watch.os, "getppid", return_value=1), patch.object(watch, "process_snapshot") as snapshotter:
                watch.watch(10, output, output / "stop")
            snapshotter.assert_not_called()
            records = [json.loads(line) for line in (output / "resources.jsonl").read_text().splitlines()]
            self.assertEqual([r["event"] for r in records], ["watch_stopped"])

    def test_cli_rejects_unrelated_root_and_exits_on_existing_stop_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            stop = output / "stop"
            stop.touch()
            command = [sys.executable, str(ROOT / "scripts/ci_resource_watch.py"), "--root-pid", str(os.getpid()), "--output-dir", str(output), "--stop-file", str(stop)]
            env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
            result = subprocess.run(command, capture_output=True, timeout=5, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            command[3] = "1"
            result = subprocess.run(command, capture_output=True, timeout=5, env=env)
            self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
