#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Effortless Metrics, Inc.

"""Best-effort descendant telemetry, independent of the suite's stdout pipeline.

Only diagnostic commands have deadlines here. This process never signals a test
process, changes test selection, or supplies the suite's exit status.
"""

import argparse
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


POLL_SECONDS = 30
STALL_SECONDS = 120
MAX_WATCH_SECONDS = 75 * 60
PS_TIMEOUT_SECONDS = 3
SAMPLE_SECONDS = 2
SAMPLE_TIMEOUT_SECONDS = 5
MAX_CAPTURES = 4
MAX_PROCESSES = 256
MAX_PS_BYTES = 2 * 1024 * 1024
LOG_TAIL_BYTES = 256 * 1024
LOG_PATHS = (
    "artifacts/ci/full-suite.log",
    "SwiftMTPKit/coverage/test_output.log",
    "SwiftMTPKit/coverage/fuzz_output.log",
    "SwiftMTPKit/coverage/storybook_output.log",
)
PS_COMMAND = (
    "/bin/ps", "-ww", "-axo",
    "pid=,ppid=,pgid=,rss=,pcpu=,state=,etime=,lstart=,comm=",
)
TEST_START = re.compile(rb"(?m)^Test (?:Suite|Case) .+ started(?: at|\.)")


@dataclass(frozen=True)
class Process:
    pid: int
    ppid: int
    pgid: int
    rss_kib: int
    cpu_percent: float
    state: str
    elapsed: str
    started: str
    comm: str

    @property
    def identity(self):
        # Never trust a cached numeric PID alone, including after an exec.
        return self.pid, self.ppid, self.pgid, self.started, self.comm


def parse_processes(text):
    """Parse ps's executable-name column, never its secret-bearing argv column."""
    result = {}
    for line in text.splitlines():
        fields = line.split(None, 12)
        if len(fields) != 13:
            continue
        try:
            process = Process(
                *(int(value) for value in fields[:4]), float(fields[4]),
                fields[5], fields[6], " ".join(fields[7:12]), fields[12],
            )
        except ValueError:
            continue
        if process.pid > 0 and process.ppid >= 0 and process.pgid > 0:
            result[process.pid] = process
    return result


def process_snapshot():
    """Bound ps execution and retained output; unrelated rows are not recorded."""
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    with tempfile.TemporaryFile() as output:
        result = subprocess.run(
            PS_COMMAND, stdout=output, stderr=subprocess.DEVNULL,
            timeout=PS_TIMEOUT_SECONDS, check=False, env=env,
        )
        if result.returncode:
            raise RuntimeError(f"ps exited {result.returncode}")
        output.seek(0)
        data = output.read(MAX_PS_BYTES + 1)
    if len(data) > MAX_PS_BYTES:
        raise RuntimeError("ps output exceeded diagnostic bound")
    return parse_processes(data.decode("utf-8", errors="replace"))


def descendants(snapshot, root_pid, watcher_pid):
    """Exclude unrelated processes, ancestry cycles, and this watcher's subtree."""
    owned = {}
    for pid, process in snapshot.items():
        current = pid
        seen = set()
        while current in snapshot and current not in seen:
            if current == watcher_pid:
                break
            if current == root_pid:
                if pid != root_pid:
                    owned[pid] = process
                break
            seen.add(current)
            current = snapshot[current].ppid
    return owned


def is_xctest(process):
    name = Path(process.comm).name
    return name in {"xctest", "swiftpm-xctest-helper"} or ".xctest/Contents/MacOS/" in process.comm


def capture_candidates(owned, root_pid):
    """Prefer test hosts, their SwiftPM ancestor, then their pipeline tees."""
    hosts = sorted((p for p in owned.values() if is_xctest(p)), key=lambda p: p.pid)
    swiftpm = {}
    tee_parents = {root_pid}
    for host in hosts:
        current = host.ppid
        seen = set()
        while current in owned and current not in seen:
            seen.add(current)
            process = owned[current]
            if Path(process.comm).name in {"swift", "swift-test"}:
                swiftpm[process.pid] = process
                tee_parents.add(process.ppid)
            current = process.ppid
    tees = sorted(
        (p for p in owned.values() if Path(p.comm).name == "tee" and p.ppid in tee_parents),
        key=lambda p: p.pid,
    )
    candidates = hosts + sorted(swiftpm.values(), key=lambda p: p.pid) + tees
    return candidates[:MAX_CAPTURES]


def same_owned_process(snapshot, root, candidate, watcher_pid):
    current_root = snapshot.get(root.pid)
    current = descendants(snapshot, root.pid, watcher_pid).get(candidate.pid)
    return (
        current_root is not None and current_root.identity == root.identity
        and current is not None and current.identity == candidate.identity
    )


def log_observation():
    """Read bounded tails for real XCTest starts; watcher output is not progress."""
    sizes = {}
    tests_started = False
    for name in LOG_PATHS:
        try:
            with open(name, "rb") as stream:
                size = stream.seek(0, os.SEEK_END)
                sizes[name] = size
                stream.seek(max(0, size - LOG_TAIL_BYTES))
                tests_started |= TEST_START.search(stream.read(LOG_TAIL_BYTES)) is not None
        except OSError:
            sizes[name] = None
    return sizes, tests_started


class StallState:
    def __init__(self):
        self.sizes = None
        self.hosts = ()
        self.armed = False
        self.last_progress = 0.0
        self.capture_attempted = False

    def observe(self, now, sizes, hosts, tests_started):
        if sizes != self.sizes:
            self.last_progress = now
            self.sizes = sizes.copy()
        identities = tuple(sorted(host.identity for host in hosts))
        if identities != self.hosts:
            self.hosts = identities
            self.armed = False
            self.last_progress = now
        if identities and tests_started and not self.armed:
            self.armed = True
            self.last_progress = now
        due = self.armed and not self.capture_attempted and now - self.last_progress >= STALL_SECONDS
        if due:
            self.capture_attempted = True
        return due


def emit(output_dir, event, **fields):
    record = {"time": datetime.now(timezone.utc).isoformat(), "event": event, **fields}
    with (output_dir / "resources.jsonl").open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, sort_keys=True) + "\n")


def capture_once(root, candidates, watcher_pid, output_dir, stopped, snapshotter=process_snapshot):
    """A single bounded batch; revalidate identity/ownership before every sample."""
    for index, candidate in enumerate(candidates[:MAX_CAPTURES]):
        if stopped():
            break
        try:
            before = snapshotter()
            if not same_owned_process(before, root, candidate, watcher_pid):
                emit(output_dir, "sample_skipped_identity", pid=candidate.pid)
                continue
            if stopped():
                break
            if sys.platform != "darwin" or not Path("/usr/bin/sample").is_file():
                emit(output_dir, "sample_unavailable", platform=sys.platform)
                break
            path = output_dir / f"sample-{index + 1}-{candidate.pid}.txt"
            command_output = output_dir / f"sample-{index + 1}-{candidate.pid}-command.txt"
            # Only this diagnostic subprocess may be killed by its own timeout.
            # The watcher never signals the suite, XCTest, SwiftPM, or tee.
            with command_output.open("wb") as stream:
                result = subprocess.run(
                    ["/usr/bin/sample", str(candidate.pid), str(SAMPLE_SECONDS), "10", "-file", str(path)],
                    stdout=stream, stderr=subprocess.STDOUT,
                    timeout=SAMPLE_TIMEOUT_SECONDS, check=False,
                )
            after = snapshotter()
            valid = same_owned_process(after, root, candidate, watcher_pid)
            emit(
                output_dir, "sample_finished", pid=candidate.pid, file=path.name,
                returncode=result.returncode, identity_still_valid=valid,
                report_present=path.is_file(), command_output=command_output.name,
            )
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            # Do not emit command arguments or retry an unbounded capture.
            emit(output_dir, "sample_error", pid=candidate.pid, error_type=type(error).__name__)


def watch(root_pid, output_dir, stop_file):
    watcher_pid = os.getpid()
    start = time.monotonic()
    next_poll = start
    root = None
    state = StallState()

    def stopped():
        return stop_file.exists() or os.getppid() != root_pid

    while not stopped() and time.monotonic() - start < MAX_WATCH_SECONDS:
        now = time.monotonic()
        if now < next_poll:
            time.sleep(min(0.25, next_poll - now))
            continue
        next_poll = now + POLL_SECONDS
        try:
            snapshot = process_snapshot()
            current_root = snapshot.get(root_pid)
            if current_root is None:
                break
            if root is None:
                root = current_root
            elif current_root.identity != root.identity:
                emit(output_dir, "root_identity_changed")
                break
            owned = descendants(snapshot, root_pid, watcher_pid)
            sizes, tests_started = log_observation()
            processes = sorted(owned.values(), key=lambda p: p.pid)
            emit(
                output_dir, "resources", root_pid=root_pid, log_sizes=sizes,
                processes=[asdict(p) for p in processes[:MAX_PROCESSES]],
                omitted_processes=max(0, len(processes) - MAX_PROCESSES),
            )
            hosts = [process for process in processes if is_xctest(process)]
            if state.observe(now, sizes, hosts, tests_started):
                emit(output_dir, "stall_sample", stagnant_seconds=now - state.last_progress)
                capture_once(root, capture_candidates(owned, root_pid), watcher_pid, output_dir, stopped)
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            emit(output_dir, "watch_error", error_type=type(error).__name__)
    emit(output_dir, "watch_stopped")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root-pid", type=int, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--stop-file", type=Path, required=True)
    args = parser.parse_args()
    if args.root_pid <= 1 or args.root_pid != os.getppid():
        parser.error("root PID must be this watcher's current parent")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    watch(args.root_pid, args.output_dir, args.stop_file)


if __name__ == "__main__":
    main()
