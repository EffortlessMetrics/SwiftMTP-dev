#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Effortless Metrics, Inc.

"""Exercise the CI log pipeline without running Swift or requiring macOS."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
SUITE_STEP = "Full Test Suite + Coverage Gate + Xcode Unit/UI Tests"
UPLOAD_STEP = "Preserve full-suite diagnostics"


def step_body(workflow, name):
    """Extract one named step at this workflow's existing indentation."""
    match = re.search(
        r"^      - name: " + re.escape(name) + r"\n((?:^        .*\n|^\n)*)",
        workflow,
        re.MULTILINE,
    )
    if match is None:
        raise AssertionError(f"Missing CI step: {name}")
    return match.group(1)


class CIDiagnosticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")
        cls.suite = step_body(cls.workflow, SUITE_STEP)
        cls.command = textwrap.dedent(cls.suite.split("        run: |\n", 1)[1])

    def run_fixture(self, status, failing_tee=False, command=None):
        with tempfile.TemporaryDirectory(prefix="swiftmtp-ci-diagnostics-") as directory:
            root = Path(directory)
            suite = root / "run-all-tests.sh"
            suite.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'fixture stdout\\n'\n"
                "printf 'fixture stderr\\n' >&2\n"
                f"exit {status}\n",
                encoding="utf-8",
            )
            suite.chmod(0o755)
            env = os.environ.copy()
            if failing_tee:
                bin_dir = root / "bin"
                bin_dir.mkdir()
                tee = bin_dir / "tee"
                tee.write_text("#!/bin/sh\ncat >/dev/null\nexit 23\n", encoding="utf-8")
                tee.chmod(0o755)
                env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]
            result = subprocess.run(
                ["bash", "-e", "-c", self.command if command is None else command],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
                timeout=10,
                check=False,
            )
            log = root / "artifacts" / "ci" / "full-suite.log"
            return result, log.read_text(encoding="utf-8") if log.exists() else None

    def test_success_keeps_stdout_and_stderr_in_artifact(self):
        result, log = self.run_fixture(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log, "fixture stdout\nfixture stderr\n")
        self.assertEqual(result.stdout, log)

    def test_failing_suite_is_not_hidden_by_successful_tee(self):
        result, log = self.run_fixture(42)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(log, "fixture stdout\nfixture stderr\n")

    def test_failure_control_detects_missing_pipefail(self):
        # The same failing suite becomes falsely green without the production guard.
        command = self.command.replace("set -o pipefail\n", "")
        result, _ = self.run_fixture(42, command=command)
        self.assertEqual(result.returncode, 0)

    def test_log_write_failure_is_not_success(self):
        result, _ = self.run_fixture(0, failing_tee=True)
        self.assertEqual(result.returncode, 23)

    def test_upload_runs_after_failure_with_budget_inside_job_deadline(self):
        upload = step_body(self.workflow, UPLOAD_STEP)
        self.assertRegex(upload, r"(?m)^        if: always\(\)$")
        self.assertNotIn("continue-on-error:", self.suite)
        self.assertIn("uses: actions/upload-artifact@v4", upload)
        self.assertIn("artifacts/ci/full-suite.log", upload)
        self.assertIn("SwiftMTPKit/coverage/test_output.log", upload)
        self.assertLess(self.workflow.index(SUITE_STEP), self.workflow.index(UPLOAD_STEP))
        self.assertLess(
            self.workflow.index(UPLOAD_STEP), self.workflow.index("Coverage gate (60% minimum)")
        )
        job_limit = int(re.search(r"^    timeout-minutes: (\d+)$", self.workflow, re.MULTILINE)[1])
        suite_limit = int(re.search(r"timeout-minutes: (\d+)", self.suite)[1])
        upload_limit = int(re.search(r"timeout-minutes: (\d+)", upload)[1])
        self.assertEqual(job_limit, 90)
        self.assertGreaterEqual(job_limit - suite_limit - upload_limit, 10)
        self.assertIn('COVERAGE_THRESHOLD: "60"', self.suite)
        self.assertIn('RUN_XCODE_UI_TESTS: "1"', self.suite)


if __name__ == "__main__":
    unittest.main()
