#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2025 Effortless Metrics, Inc.
"""compat-harness.py — SwiftMTP ↔ libmtp compatibility harness.

Runs both toolchains against an attached MTP device, normalises their
output into a comparable structure (with configurable timestamp tolerance),
diffs the results, applies an optional per-device expectation overlay to
classify each difference, and writes structured evidence to disk.

Evidence layout
---------------
  evidence/<date>/<vidpid>/<run-id>/
    meta.json          run metadata (tool versions, flags, timestamp)
    swiftmtp.json      raw + normalised SwiftMTP output
    libmtp.json        raw + normalised libmtp output
    diff.json          structured diff with classification labels
    diff.md            human-readable diff report
    logs/
      swiftmtp.log     full SwiftMTP stdout+stderr
      libmtp.log       full libmtp stdout+stderr

Diff labels
-----------
  bug_swiftmtp  — SwiftMTP returns wrong data
  bug_libmtp    — libmtp returns wrong data
  intentional   — known, documented difference (e.g. privacy redaction)
  quirk_needed  — SwiftMTP needs a device-quirk entry to match
  unknown       — unclassified; needs investigation

Usage examples
--------------
  # Read-only run (auto-detect device):
  ./scripts/compat-harness.py

  # Target a specific device:
  ./scripts/compat-harness.py --vidpid 18d1:4ee1

  # Include controlled write tests:
  ./scripts/compat-harness.py --vidpid 04e8:6860 --allow-write

  # Override evidence root and increase timeouts:
  ./scripts/compat-harness.py --evidence-dir /tmp/compat --timeout 240

Expectation overlays
--------------------
  Place a YAML file at  compat/expectations/<vid>_<pid>.yml  (e.g.
  compat/expectations/18d1_4ee1.yml) to pre-classify known differences.
  See compat/expectations/README.md for the full format specification.
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import textwrap
import uuid
from typing import Any, Dict, Generator, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Optional YAML support (PyYAML).  stdlib has no YAML parser; fall back
# gracefully so the harness still works without it installed.
# ---------------------------------------------------------------------------
try:
    import yaml as _yaml_mod

    def _load_yaml(path: pathlib.Path) -> Dict[str, Any]:
        with path.open(encoding="utf-8") as fh:
            return _yaml_mod.safe_load(fh) or {}

except ImportError:
    _yaml_mod = None  # type: ignore[assignment]

    def _load_yaml(path: pathlib.Path) -> Dict[str, Any]:  # type: ignore[misc]
        _log().warning(
            "PyYAML not installed — expectation overlay %s will be skipped. "
            "Install with: pip install pyyaml",
            path,
        )
        return {}


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

def _log() -> logging.Logger:
    return logging.getLogger("compat-harness")


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%H:%M:%S",
)

# ---------------------------------------------------------------------------
# Repository paths
# ---------------------------------------------------------------------------

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
_SWIFTMTPKIT_DIR = _REPO_ROOT / "SwiftMTPKit"
_COMPAT_DIR = _REPO_ROOT / "compat"
_EVIDENCE_ROOT = _REPO_ROOT / "evidence"
_EXPECTATIONS_DIR = _COMPAT_DIR / "expectations"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_WRITE_TEST_FILENAME = "swiftmtp-compat-test.txt"

# All valid classification labels.
LABEL_BUG_SWIFTMTP: str = "bug_swiftmtp"
LABEL_BUG_LIBMTP: str = "bug_libmtp"
LABEL_INTENTIONAL: str = "intentional"
LABEL_QUIRK_NEEDED: str = "quirk_needed"
LABEL_UNKNOWN: str = "unknown"
_ALL_LABELS: Tuple[str, ...] = (
    LABEL_BUG_SWIFTMTP,
    LABEL_BUG_LIBMTP,
    LABEL_INTENTIONAL,
    LABEL_QUIRK_NEEDED,
    LABEL_UNKNOWN,
)

# ---------------------------------------------------------------------------
# Subprocess helpers
# ---------------------------------------------------------------------------

def _run(
    cmd: List[str],
    *,
    cwd: Optional[pathlib.Path] = None,
    timeout: int = 120,
) -> subprocess.CompletedProcess:
    """Run *cmd* and return CompletedProcess.  Never raises on non-zero exit."""
    _log().debug("exec: %s  (cwd=%s)", " ".join(cmd), cwd or ".")
    try:
        return subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError:
        result = subprocess.CompletedProcess(cmd, returncode=127, stdout="", stderr="")
        result.stderr = f"command not found: {cmd[0]}"
        return result
    except subprocess.TimeoutExpired:
        result = subprocess.CompletedProcess(cmd, returncode=124, stdout="", stderr="")
        result.stderr = f"timed out after {timeout}s: {' '.join(cmd)}"
        return result


def _tool_version(name: str) -> Optional[str]:
    """Return a short version string for *name*, or None if not found."""
    for flag in ("--version", "-V", "version"):
        r = _run([name, flag], timeout=10)
        if r.returncode == 0:
            first = (r.stdout or r.stderr or "").strip().splitlines()
            return first[0] if first else "?"
    return None


def _check_tool(name: str) -> bool:
    r = _run(["which", name], timeout=5)
    return r.returncode == 0


# ---------------------------------------------------------------------------
# libmtp side — runners and text parsers
# ---------------------------------------------------------------------------

class LibmtpRunner:
    """Thin wrapper around mtp-detect / mtp-folders / mtp-files / mtp-sendfile."""

    def __init__(self, vidpid: Optional[str], timeout: int) -> None:
        self.vidpid = vidpid
        self.timeout = timeout

    # --- detect -------------------------------------------------------------

    def detect(self) -> Tuple[Dict[str, Any], str]:
        r = _run(["mtp-detect"], timeout=self.timeout)
        raw = (r.stdout or "") + (r.stderr or "")
        if r.returncode == 127:
            return {"error": "mtp-detect not found"}, raw
        return _parse_mtp_detect(raw, self.vidpid), raw

    # --- folders ------------------------------------------------------------

    def folders(self) -> Tuple[List[Dict[str, Any]], str]:
        r = _run(["mtp-folders"], timeout=self.timeout)
        raw = (r.stdout or "") + (r.stderr or "")
        if r.returncode == 127:
            return [], raw
        return _parse_mtp_folders(raw), raw

    # --- files --------------------------------------------------------------

    def files(self) -> Tuple[List[Dict[str, Any]], str]:
        r = _run(["mtp-files"], timeout=self.timeout)
        raw = (r.stdout or "") + (r.stderr or "")
        if r.returncode == 127:
            return [], raw
        return _parse_mtp_files(raw), raw

    # --- sendfile -----------------------------------------------------------

    def sendfile(self, local_path: str, remote_name: str) -> Tuple[bool, str]:
        r = _run(["mtp-sendfile", local_path, remote_name], timeout=self.timeout)
        return r.returncode == 0, (r.stdout or "") + (r.stderr or "")


# --- mtp-detect parser ------------------------------------------------------

def _parse_mtp_detect(raw: str, vidpid: Optional[str]) -> Dict[str, Any]:
    """Best-effort parser for mtp-detect text output (tolerates version variation)."""
    devices: List[Dict[str, Any]] = []
    cur: Optional[Dict[str, Any]] = None

    for line in raw.splitlines():
        # "Device 0 (VID=18d1 and PID=4ee1) is a Google Inc..."
        m = re.match(
            r"Device\s+(\d+)\s+\(VID=([0-9a-fA-F]+)\s+and\s+PID=([0-9a-fA-F]+)\)",
            line,
        )
        if m:
            cur = {
                "index": int(m.group(1)),
                "vid": m.group(2).lower(),
                "pid": m.group(3).lower(),
                "storages": [],
            }
            devices.append(cur)
            continue

        if cur is None:
            continue

        for attr, pattern in (
            ("manufacturer", r"\s+Manufacturer:\s+(.+)"),
            ("model", r"\s+Model:\s+(.+)"),
            ("serial", r"\s+Serial number:\s+(.+)"),
            ("firmware", r"\s+Device version:\s+(.+)"),
            ("friendly_name", r"\s+Friendly name:\s+(.+)"),
        ):
            m = re.match(pattern, line)
            if m:
                cur[attr] = m.group(1).strip()
                break
        else:
            # Storage blocks
            m = re.match(r"\s+Storage\s+(\d+)\s*:", line)
            if m:
                cur["storages"].append({"id": int(m.group(1))})
                continue
            for storage_attr, storage_pattern in (
                ("description", r"\s+StorageDescription:\s+(.+)"),
                ("volume", r"\s+VolumeIdentifier:\s+(.+)"),
                ("capacity_bytes", r"\s+MaxCapacity:\s+(\d+)"),
                ("free_bytes", r"\s+FreeSpaceInBytes:\s+(\d+)"),
            ):
                m = re.match(storage_pattern, line)
                if m and cur.get("storages"):
                    val: Any = m.group(1).strip()
                    if storage_attr in ("capacity_bytes", "free_bytes"):
                        val = int(val)
                    cur["storages"][-1][storage_attr] = val
                    break

    if vidpid:
        vid, pid = vidpid.lower().split(":")
        devices = [d for d in devices if d.get("vid") == vid and d.get("pid") == pid]

    return {"devices": devices, "_source": "mtp-detect"}


# --- mtp-folders parser -----------------------------------------------------

def _parse_mtp_folders(raw: str) -> List[Dict[str, Any]]:
    """Parse mtp-folders text output into a list of folder dicts."""
    folders: List[Dict[str, Any]] = []
    for line in raw.splitlines():
        # "Folder: 65537 (parent: 0)  Name: DCIM"
        m = re.match(
            r"\s*Folder[:\s]+(\d+)\s+\(parent:\s*(\d+)\)[,\s]+Name:\s+(.+)",
            line,
            re.IGNORECASE,
        )
        if m:
            folders.append(
                {
                    "id": int(m.group(1)),
                    "parent_id": int(m.group(2)),
                    "name": m.group(3).strip(),
                }
            )
    return folders


# --- mtp-files parser -------------------------------------------------------

def _parse_mtp_files(raw: str) -> List[Dict[str, Any]]:
    """Parse mtp-files text output into a list of file dicts."""
    files: List[Dict[str, Any]] = []
    cur: Optional[Dict[str, Any]] = None

    for line in raw.splitlines():
        # "File: 65538 (parent: 65537, storage: 65537)"
        m = re.match(r"\s*File[:\s]+(\d+)\s+\(parent:\s*(\d+)", line, re.IGNORECASE)
        if m:
            cur = {"id": int(m.group(1)), "parent_id": int(m.group(2))}
            files.append(cur)
            continue

        if cur is None:
            continue

        m = re.match(r"\s*Filename:\s+(.+)", line, re.IGNORECASE)
        if m:
            cur["name"] = m.group(1).strip()
            continue

        m = re.match(r"\s*File size\s+(\d+)", line, re.IGNORECASE)
        if m:
            cur["size_bytes"] = int(m.group(1))
            continue

        m = re.match(r"\s*Modified date:\s+(.+)", line, re.IGNORECASE)
        if m:
            ts = _parse_iso_or_ctime(m.group(1).strip())
            if ts is not None:
                cur["mtime"] = ts

    return files


# ---------------------------------------------------------------------------
# SwiftMTP side — runner
# ---------------------------------------------------------------------------

class SwiftMTPRunner:
    """Thin wrapper around `swift run swiftmtp` sub-commands."""

    def __init__(
        self,
        vidpid: Optional[str],
        swiftmtpkit_dir: pathlib.Path,
        timeout: int,
    ) -> None:
        self.vidpid = vidpid
        self.dir = swiftmtpkit_dir
        self.timeout = timeout

    def _base(self) -> List[str]:
        cmd = ["swift", "run", "swiftmtp"]
        if self.vidpid:
            cmd += ["--device", self.vidpid]
        return cmd

    def probe(self) -> Tuple[Dict[str, Any], str]:
        r = _run(self._base() + ["probe", "--json"], cwd=self.dir, timeout=self.timeout)
        raw = r.stdout or ""
        err = r.stderr or ""
        if r.returncode == 127:
            return {"error": "swift not found"}, err
        try:
            return json.loads(raw), raw + err
        except json.JSONDecodeError as exc:
            return {"error": f"JSON parse error: {exc}", "raw": raw[:500]}, raw + err

    def ls(self) -> Tuple[Any, str]:
        r = _run(self._base() + ["ls", "--json"], cwd=self.dir, timeout=self.timeout)
        raw = r.stdout or ""
        err = r.stderr or ""
        if r.returncode == 127:
            return [], err
        try:
            return json.loads(raw), raw + err
        except json.JSONDecodeError as exc:
            return {"error": f"JSON parse error: {exc}", "raw": raw[:500]}, raw + err

    def push(self, local_path: str, remote_path: str) -> Tuple[bool, str]:
        r = _run(
            self._base() + ["push", local_path, remote_path],
            cwd=self.dir,
            timeout=self.timeout,
        )
        return r.returncode == 0, (r.stdout or "") + (r.stderr or "")


# ---------------------------------------------------------------------------
# Timestamp helper
# ---------------------------------------------------------------------------

def _parse_iso_or_ctime(s: str) -> Optional[int]:
    """Parse a date/time string into a UTC Unix timestamp, or return None."""
    formats = [
        "%Y%m%dT%H%M%S",       # 20230101T120000  (MTP compact ISO)
        "%Y-%m-%dT%H:%M:%S",   # 2023-01-01T12:00:00
        "%Y-%m-%d %H:%M:%S",   # 2023-01-01 12:00:00
        "%a %b %d %H:%M:%S %Y",  # Mon Jan 01 12:00:00 2023  (ctime)
    ]
    for fmt in formats:
        try:
            dt = datetime.datetime.strptime(s, fmt)
            return int(dt.replace(tzinfo=datetime.timezone.utc).timestamp())
        except ValueError:
            pass
    # Last resort: fromisoformat (handles timezone offsets on Python 3.7+)
    try:
        dt = datetime.datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return int(dt.timestamp())
    except (ValueError, AttributeError):
        pass
    return None


# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------

def _normalise_device(
    libmtp_detect: Dict[str, Any],
    swiftmtp_probe: Dict[str, Any],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """Return comparable normalised device dicts for each side."""

    def _norm_lib(d: Dict[str, Any]) -> Dict[str, Any]:
        devices = d.get("devices", [])
        dev = devices[0] if devices else {}
        storages = sorted(
            [
                {
                    "description": s.get("description", ""),
                    "capacity_bytes": s.get("capacity_bytes", 0),
                    # free_bytes intentionally excluded — too volatile to compare
                }
                for s in dev.get("storages", [])
            ],
            key=lambda s: s.get("description", ""),
        )
        return {
            "manufacturer": dev.get("manufacturer", ""),
            "model": dev.get("model", ""),
            "firmware": dev.get("firmware", ""),
            "friendly_name": dev.get("friendly_name", ""),
            # serial omitted — SwiftMTP may privacy-redact it
            "storages": storages,
        }

    def _norm_swift(d: Dict[str, Any]) -> Dict[str, Any]:
        dev = d.get("device", d)  # tolerate both top-level and {"device": {...}}
        storages = sorted(
            [
                {
                    "description": s.get("description", s.get("name", "")),
                    "capacity_bytes": s.get(
                        "capacityBytes", s.get("capacity_bytes", 0)
                    ),
                }
                for s in dev.get("storages", [])
            ],
            key=lambda s: s.get("description", ""),
        )
        return {
            "manufacturer": dev.get("manufacturer", ""),
            "model": dev.get("model", dev.get("friendlyName", "")),
            "firmware": dev.get("firmwareVersion", dev.get("firmware", "")),
            "friendly_name": dev.get("friendlyName", dev.get("friendly_name", "")),
            "storages": storages,
        }

    return _norm_lib(libmtp_detect), _norm_swift(swiftmtp_probe)


def _normalise_files(
    libmtp_files: List[Dict[str, Any]],
    libmtp_folders: List[Dict[str, Any]],
    swiftmtp_ls: Any,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Return sorted, path-resolved file lists for each side."""

    # Build an id→absolute-path map from the libmtp folder list.
    folder_map: Dict[int, str] = {0: ""}
    for folder in sorted(libmtp_folders, key=lambda f: f.get("id", 0)):
        fid = folder.get("id", 0)
        parent = folder_map.get(folder.get("parent_id", 0), "")
        name = folder.get("name", str(fid))
        folder_map[fid] = f"{parent}/{name}" if parent else name

    def _lib_files() -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        for f in libmtp_files:
            parent_path = folder_map.get(f.get("parent_id", 0), "")
            name = f.get("name", "")
            path = f"{parent_path}/{name}" if parent_path else name
            entry: Dict[str, Any] = {"path": path, "size_bytes": f.get("size_bytes", 0)}
            if "mtime" in f:
                entry["mtime"] = f["mtime"]
            out.append(entry)
        return sorted(out, key=lambda x: x["path"])

    def _swift_files() -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        items = (
            swiftmtp_ls
            if isinstance(swiftmtp_ls, list)
            else swiftmtp_ls.get("items", [])
            if isinstance(swiftmtp_ls, dict)
            else []
        )
        for item in _flatten_tree(items, prefix=""):
            entry: Dict[str, Any] = {
                "path": item.get("path", item.get("name", "")),
                "size_bytes": item.get("sizeBytes", item.get("size_bytes", 0)),
            }
            raw_mtime = item.get("modificationDate", item.get("mtime"))
            if isinstance(raw_mtime, (int, float)):
                entry["mtime"] = int(raw_mtime)
            elif isinstance(raw_mtime, str):
                ts = _parse_iso_or_ctime(raw_mtime)
                if ts is not None:
                    entry["mtime"] = ts
            out.append(entry)
        return sorted(out, key=lambda x: x["path"])

    return _lib_files(), _swift_files()


def _flatten_tree(
    items: Any, prefix: str = ""
) -> Generator[Dict[str, Any], None, None]:
    """Recursively flatten a (possibly nested) SwiftMTP ls tree into a flat
    stream of file-entry dicts, each with a 'path' key set to the full path."""
    if not isinstance(items, list):
        return
    for item in items:
        name = item.get("name", "")
        path = f"{prefix}/{name}" if prefix else name
        if item.get("type") == "folder":
            yield from _flatten_tree(item.get("children", []), path)
        else:
            yield {**item, "path": path}


# ---------------------------------------------------------------------------
# Diff engine
# ---------------------------------------------------------------------------

class DiffEntry:
    """A single normalised difference between the two toolchains."""

    __slots__ = ("key", "libmtp_val", "swiftmtp_val", "label", "reason")

    def __init__(
        self,
        key: str,
        libmtp_val: Any,
        swiftmtp_val: Any,
        label: str = LABEL_UNKNOWN,
        reason: str = "",
    ) -> None:
        self.key = key
        self.libmtp_val = libmtp_val
        self.swiftmtp_val = swiftmtp_val
        self.label = label
        self.reason = reason

    def to_dict(self) -> Dict[str, Any]:
        return {
            "key": self.key,
            "libmtp": self.libmtp_val,
            "swiftmtp": self.swiftmtp_val,
            "label": self.label,
            "reason": self.reason,
        }


def _diff_device(
    norm_lib: Dict[str, Any],
    norm_swift: Dict[str, Any],
) -> List[DiffEntry]:
    diffs: List[DiffEntry] = []
    for key in sorted(set(norm_lib) | set(norm_swift)):
        a, b = norm_lib.get(key), norm_swift.get(key)
        if a != b:
            diffs.append(DiffEntry(f"device.{key}", a, b))
    return diffs


def _diff_files(
    lib_files: List[Dict[str, Any]],
    swift_files: List[Dict[str, Any]],
    ts_tol: int,
) -> List[DiffEntry]:
    diffs: List[DiffEntry] = []
    lib_map = {f["path"]: f for f in lib_files}
    swift_map = {f["path"]: f for f in swift_files}

    for path in sorted(set(lib_map) | set(swift_map)):
        a = lib_map.get(path)
        b = swift_map.get(path)

        if a is None:
            diffs.append(DiffEntry(f"file.{path}", None, b))
            continue
        if b is None:
            diffs.append(DiffEntry(f"file.{path}", a, None))
            continue

        if a.get("size_bytes") != b.get("size_bytes"):
            diffs.append(
                DiffEntry(
                    f"file.{path}.size_bytes",
                    a.get("size_bytes"),
                    b.get("size_bytes"),
                )
            )

        a_mt, b_mt = a.get("mtime"), b.get("mtime")
        if a_mt is not None and b_mt is not None and abs(a_mt - b_mt) > ts_tol:
            diffs.append(DiffEntry(f"file.{path}.mtime", a_mt, b_mt))

    return diffs


# ---------------------------------------------------------------------------
# Expectation overlay — classification
# ---------------------------------------------------------------------------

def _load_expectations(vidpid: Optional[str]) -> Dict[str, Any]:
    if not vidpid:
        return {}
    # Accept both "18d1:4ee1" and "18d1_4ee1" naming.
    candidates = [
        _EXPECTATIONS_DIR / f"{vidpid.replace(':', '_')}.yml",
        _EXPECTATIONS_DIR / f"{vidpid}.yml",
    ]
    for path in candidates:
        if path.exists():
            _log().info("Loading expectation overlay: %s", path)
            return _load_yaml(path)
    _log().debug("No expectation overlay found for %s", vidpid)
    return {}


def _classify_diffs(
    diffs: List[DiffEntry], expectations: Dict[str, Any]
) -> List[DiffEntry]:
    """Apply the expectation overlay to label each DiffEntry in-place."""

    def _build_map(section: str) -> Dict[str, Tuple[str, str]]:
        """Return {key_pattern: (label, reason)} for a named section.

        Sections 'intentional_differences', 'quirk_needed' carry an implied
        label.  'known_bugs' must have an explicit 'label' field.
        """
        section_label_map = {
            "intentional_differences": LABEL_INTENTIONAL,
            "quirk_needed": LABEL_QUIRK_NEEDED,
            "known_bugs": None,  # label comes from entry itself
        }
        implied = section_label_map.get(section)
        result: Dict[str, Tuple[str, str]] = {}
        for entry in expectations.get(section, []):
            key = entry.get("key", "")
            reason = entry.get("reason", "")
            lbl = entry.get("label", implied) or LABEL_UNKNOWN
            if key:
                result[key] = (lbl, reason)
        return result

    intentional = _build_map("intentional_differences")
    quirk = _build_map("quirk_needed")
    bugs = _build_map("known_bugs")
    # 'expected_failures' maps operation names, not diff keys directly.
    # We record them for completeness in meta but don't match against diffs.

    all_patterns = {**intentional, **quirk, **bugs}

    for diff in diffs:
        for pattern, (lbl, reason) in all_patterns.items():
            if diff.key == pattern or diff.key.startswith(pattern + "."):
                diff.label = lbl
                diff.reason = reason
                break
        # If still UNKNOWN, leave it — no else branch needed.

    return diffs


# ---------------------------------------------------------------------------
# Write tests
# ---------------------------------------------------------------------------

def _run_write_tests(
    libmtp: LibmtpRunner,
    swiftmtp: SwiftMTPRunner,
) -> Dict[str, Any]:
    """Upload a small sentinel file via both toolchains; return results dict."""
    results: Dict[str, Any] = {}
    content = (
        "SwiftMTP compat-harness write-test sentinel\n"
        f"Timestamp: {datetime.datetime.now(datetime.timezone.utc).isoformat()}Z\n"
    )

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".txt",
        prefix="swiftmtp-compat-",
        delete=False,
    ) as tf:
        tf.write(content)
        tmp_path = tf.name

    try:
        _log().info("[write-test] SwiftMTP push: %s → %s", tmp_path, _WRITE_TEST_FILENAME)
        ok, out = swiftmtp.push(tmp_path, _WRITE_TEST_FILENAME)
        results["swiftmtp_push"] = {"success": ok, "output": out}
        _progress(f"  swiftmtp push: {'OK' if ok else 'FAILED'}")

        libmtp_name = _WRITE_TEST_FILENAME.replace(".txt", "-libmtp.txt")
        _log().info("[write-test] mtp-sendfile: %s → %s", tmp_path, libmtp_name)
        ok2, out2 = libmtp.sendfile(tmp_path, libmtp_name)
        results["libmtp_sendfile"] = {"success": ok2, "output": out2}
        _progress(f"  mtp-sendfile:  {'OK' if ok2 else 'FAILED'}")
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    return results


# ---------------------------------------------------------------------------
# Evidence I/O
# ---------------------------------------------------------------------------

def _make_run_dir(
    evidence_root: pathlib.Path,
    vidpid: Optional[str],
    run_id: str,
) -> pathlib.Path:
    today = datetime.date.today().isoformat()
    safe_vid = (vidpid or "unknown").replace(":", "_")
    run_dir = evidence_root / today / safe_vid / run_id
    (run_dir / "logs").mkdir(parents=True, exist_ok=True)
    return run_dir


def _write_json(path: pathlib.Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, default=str), encoding="utf-8")


def _summary_counts(diffs: List[DiffEntry]) -> Dict[str, int]:
    counts: Dict[str, int] = {lbl: 0 for lbl in _ALL_LABELS}
    for d in diffs:
        counts[d.label] = counts.get(d.label, 0) + 1
    return counts


def _write_diff_md(
    path: pathlib.Path,
    meta: Dict[str, Any],
    diffs: List[DiffEntry],
    write_results: Optional[Dict[str, Any]],
) -> None:
    counts = _summary_counts(diffs)
    lines: List[str] = [
        "# SwiftMTP ↔ libmtp Compatibility Report",
        "",
        f"**Run ID:** `{meta['run_id']}`  ",
        f"**Date:** {meta['timestamp']}  ",
        f"**Device:** `{meta.get('vidpid') or 'auto-detect'}`  ",
        f"**Timestamp tolerance:** {meta['ts_tolerance_seconds']}s  ",
        f"**Total diffs:** {len(diffs)}",
        "",
        "## Summary",
        "",
        "| Label | Count |",
        "|-------|------:|",
    ]
    for lbl in _ALL_LABELS:
        lines.append(f"| `{lbl}` | {counts.get(lbl, 0)} |")
    lines.append("")

    if diffs:
        lines += [
            "## Differences",
            "",
            "| Key | libmtp value | SwiftMTP value | Label | Reason |",
            "|-----|-------------|----------------|-------|--------|",
        ]

        def _cell(v: Any) -> str:
            s = json.dumps(v) if not isinstance(v, str) else v
            return s.replace("|", "\\|")[:120]

        for d in sorted(diffs, key=lambda x: x.key):
            lines.append(
                f"| `{d.key}` | {_cell(d.libmtp_val)} | {_cell(d.swiftmtp_val)}"
                f" | `{d.label}` | {d.reason} |"
            )
        lines.append("")

    if write_results:
        lines += ["## Write Tests", ""]
        for name, res in write_results.items():
            status = "✅ PASS" if res.get("success") else "❌ FAIL"
            lines.append(f"- **{name}**: {status}")
        lines.append("")

    lines += [
        "---",
        f"*Generated by compat-harness.py — SwiftMTP project*",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _write_evidence(
    run_dir: pathlib.Path,
    *,
    meta: Dict[str, Any],
    libmtp_raw: Dict[str, Any],
    swiftmtp_raw: Dict[str, Any],
    diffs: List[DiffEntry],
    write_results: Optional[Dict[str, Any]],
    swiftmtp_log: str,
    libmtp_log: str,
) -> None:
    _write_json(run_dir / "meta.json", meta)
    _write_json(run_dir / "libmtp.json", libmtp_raw)
    _write_json(run_dir / "swiftmtp.json", swiftmtp_raw)

    diff_payload: Dict[str, Any] = {
        "run_id": meta["run_id"],
        "diffs": [d.to_dict() for d in diffs],
        "summary": {
            "total_diffs": len(diffs),
            "by_label": _summary_counts(diffs),
        },
    }
    if write_results:
        diff_payload["write_tests"] = write_results
    _write_json(run_dir / "diff.json", diff_payload)

    _write_diff_md(run_dir / "diff.md", meta, diffs, write_results)

    (run_dir / "logs" / "swiftmtp.log").write_text(swiftmtp_log, encoding="utf-8")
    (run_dir / "logs" / "libmtp.log").write_text(libmtp_log, encoding="utf-8")


# ---------------------------------------------------------------------------
# stdout progress helpers
# ---------------------------------------------------------------------------

def _banner() -> None:
    print("=" * 68)
    print("  SwiftMTP ↔ libmtp Compatibility Harness")
    print("=" * 68)


def _progress(msg: str) -> None:
    print(f"  ▶  {msg}")


def _result(label: str, ok: bool, extra: str = "") -> None:
    icon = "✓" if ok else "✗"
    suffix = f"  ({extra})" if extra else ""
    print(f"  {icon}  {label}{suffix}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="compat-harness.py",
        description=textwrap.dedent(
            """\
            SwiftMTP ↔ libmtp compatibility harness.

            Runs both toolchains against a connected MTP device, normalises
            their output, diffs the results (with configurable timestamp
            tolerance), optionally classifies diffs using a per-device
            expectation overlay, and writes structured evidence to disk.
            """
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            f"""\
            Expectation overlays
            --------------------
              compat/expectations/<vid>_<pid>.yml  (e.g. 18d1_4ee1.yml)
              See compat/expectations/README.md for the full format.

            Evidence output
            ---------------
              evidence/<date>/<vidpid>/<run-id>/
                meta.json, swiftmtp.json, libmtp.json
                diff.json, diff.md
                logs/swiftmtp.log, logs/libmtp.log

            Diff labels
            -----------
              bug_swiftmtp  SwiftMTP returns wrong data
              bug_libmtp    libmtp returns wrong data
              intentional   documented difference (e.g. privacy redaction)
              quirk_needed  SwiftMTP needs a device-quirk entry
              unknown       unclassified — needs investigation

            Examples
            --------
              # Read-only, auto-detect device:
              ./scripts/compat-harness.py

              # Target a specific device:
              ./scripts/compat-harness.py --vidpid 18d1:4ee1

              # Controlled write tests:
              ./scripts/compat-harness.py --vidpid 04e8:6860 --allow-write

              # Custom evidence root + verbose logging:
              ./scripts/compat-harness.py --evidence-dir /tmp/compat -v

            Exit codes
            ----------
              0  No unresolved diffs (unknown or bug_swiftmtp count is zero)
              1  Unresolved diffs present — investigation required
              2  Argument or configuration error
            """
        ),
    )

    parser.add_argument(
        "--vidpid",
        metavar="XXXX:YYYY",
        help="Target a specific device by VID:PID (e.g. 18d1:4ee1). "
        "Without this flag the first detected device is used.",
    )
    parser.add_argument(
        "--allow-write",
        action="store_true",
        help="Enable controlled write tests: upload a small sentinel file "
        "via both SwiftMTP (push) and libmtp (mtp-sendfile).",
    )
    parser.add_argument(
        "--evidence-dir",
        metavar="DIR",
        default=str(_EVIDENCE_ROOT),
        help=f"Root directory for evidence output. "
        f"(default: {_EVIDENCE_ROOT})",
    )
    parser.add_argument(
        "--swiftmtpkit-dir",
        metavar="DIR",
        default=str(_SWIFTMTPKIT_DIR),
        help=f"Path to the SwiftMTPKit package directory used for "
        f"`swift run`. (default: {_SWIFTMTPKIT_DIR})",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=120,
        metavar="SECS",
        help="Per-command timeout in seconds. The SwiftMTP side gets an "
        "additional 60 s to allow for `swift build`. (default: 120)",
    )
    parser.add_argument(
        "--ts-tolerance",
        type=int,
        default=120,
        metavar="SECS",
        help="Acceptable mtime difference in seconds before a file timestamp "
        "is flagged as a diff. Overridden by overlay tolerances.timestamp_seconds. "
        "(default: 120)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable DEBUG-level logging.",
    )
    return parser


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    evidence_root = pathlib.Path(args.evidence_dir)
    swiftmtpkit_dir = pathlib.Path(args.swiftmtpkit_dir)
    run_id = str(uuid.uuid4())[:8]

    # Validate SwiftMTPKit directory
    if not swiftmtpkit_dir.is_dir():
        parser.error(f"SwiftMTPKit directory not found: {swiftmtpkit_dir}")

    # ------------------------------------------------------------------
    # Banner
    # ------------------------------------------------------------------
    _banner()
    print(f"  Run ID     : {run_id}")
    print(f"  Device     : {args.vidpid or '(auto-detect first found)'}")
    print(f"  Write tests: {'enabled' if args.allow_write else 'disabled'}")
    print(f"  Evidence   : {evidence_root}")
    print()

    # ------------------------------------------------------------------
    # Tool availability
    # ------------------------------------------------------------------
    _progress("Checking tool availability …")
    swift_ok = _check_tool("swift")
    mtp_detect_ok = _check_tool("mtp-detect")
    mtp_folders_ok = _check_tool("mtp-folders")
    mtp_files_ok = _check_tool("mtp-files")

    _result("swift", swift_ok)
    _result("mtp-detect", mtp_detect_ok)
    _result("mtp-folders", mtp_folders_ok)
    _result("mtp-files", mtp_files_ok)

    if not swift_ok:
        _log().warning("swift not found — SwiftMTP results will be empty.")
    if not (mtp_detect_ok and mtp_folders_ok and mtp_files_ok):
        _log().warning("One or more mtp-tools not found — libmtp results may be empty.")
    print()

    # ------------------------------------------------------------------
    # Collect tool version metadata
    # ------------------------------------------------------------------
    tool_versions = {
        "swift": _tool_version("swift") if swift_ok else None,
        "mtp-detect": _tool_version("mtp-detect") if mtp_detect_ok else None,
    }

    # ------------------------------------------------------------------
    # libmtp side
    # ------------------------------------------------------------------
    libmtp = LibmtpRunner(vidpid=args.vidpid, timeout=args.timeout)

    _progress("Running mtp-detect …")
    libmtp_detect, libmtp_detect_log = libmtp.detect()
    device_count = len(libmtp_detect.get("devices", []))
    _result("mtp-detect", "error" not in libmtp_detect, f"{device_count} device(s)")

    _progress("Running mtp-folders …")
    libmtp_folders, libmtp_folders_log = libmtp.folders()
    _result("mtp-folders", True, f"{len(libmtp_folders)} folder(s)")

    _progress("Running mtp-files …")
    libmtp_files, libmtp_files_log = libmtp.files()
    _result("mtp-files", True, f"{len(libmtp_files)} file(s)")

    libmtp_log = (
        "\n=== mtp-detect ===\n"
        + libmtp_detect_log
        + "\n=== mtp-folders ===\n"
        + libmtp_folders_log
        + "\n=== mtp-files ===\n"
        + libmtp_files_log
    )
    print()

    # ------------------------------------------------------------------
    # SwiftMTP side
    # ------------------------------------------------------------------
    swiftmtp = SwiftMTPRunner(
        vidpid=args.vidpid,
        swiftmtpkit_dir=swiftmtpkit_dir,
        timeout=args.timeout + 60,  # allow for incremental swift build
    )

    _progress("Running swiftmtp probe --json (first run may trigger build) …")
    swiftmtp_probe, swiftmtp_probe_log = swiftmtp.probe()
    _result("swiftmtp probe", "error" not in swiftmtp_probe)

    _progress("Running swiftmtp ls --json …")
    swiftmtp_ls, swiftmtp_ls_log = swiftmtp.ls()
    ls_count = len(swiftmtp_ls) if isinstance(swiftmtp_ls, list) else "?"
    _result("swiftmtp ls", not isinstance(swiftmtp_ls, dict) or "error" not in swiftmtp_ls, f"{ls_count} item(s)")

    swiftmtp_log = (
        "\n=== swiftmtp probe ===\n"
        + swiftmtp_probe_log
        + "\n=== swiftmtp ls ===\n"
        + swiftmtp_ls_log
    )
    print()

    # ------------------------------------------------------------------
    # Optional write tests
    # ------------------------------------------------------------------
    write_results: Optional[Dict[str, Any]] = None
    if args.allow_write:
        _progress("Running write tests …")
        write_results = _run_write_tests(libmtp, swiftmtp)
        print()

    # ------------------------------------------------------------------
    # Load expectation overlay
    # ------------------------------------------------------------------
    expectations = _load_expectations(args.vidpid)
    ts_tol = args.ts_tolerance
    overlay_tol = expectations.get("tolerances", {}).get("timestamp_seconds")
    if overlay_tol is not None:
        ts_tol = int(overlay_tol)
        _log().info("Timestamp tolerance overridden by overlay: %ds", ts_tol)

    # ------------------------------------------------------------------
    # Normalise
    # ------------------------------------------------------------------
    _progress("Normalising outputs …")
    norm_lib_dev, norm_swift_dev = _normalise_device(libmtp_detect, swiftmtp_probe)
    norm_lib_files, norm_swift_files = _normalise_files(
        libmtp_files, libmtp_folders, swiftmtp_ls
    )

    # ------------------------------------------------------------------
    # Diff
    # ------------------------------------------------------------------
    _progress("Computing diffs …")
    diffs: List[DiffEntry] = []
    diffs += _diff_device(norm_lib_dev, norm_swift_dev)
    diffs += _diff_files(norm_lib_files, norm_swift_files, ts_tol)

    _progress(f"Classifying {len(diffs)} diff(s) …")
    diffs = _classify_diffs(diffs, expectations)

    # ------------------------------------------------------------------
    # Write evidence
    # ------------------------------------------------------------------
    run_dir = _make_run_dir(evidence_root, args.vidpid, run_id)
    _progress(f"Writing evidence → {run_dir}")

    meta: Dict[str, Any] = {
        "run_id": run_id,
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "vidpid": args.vidpid,
        "ts_tolerance_seconds": ts_tol,
        "allow_write": args.allow_write,
        "swiftmtpkit_dir": str(swiftmtpkit_dir),
        "tool_versions": tool_versions,
    }

    libmtp_payload: Dict[str, Any] = {
        "detect": libmtp_detect,
        "folders": libmtp_folders,
        "files": libmtp_files,
        "normalized_device": norm_lib_dev,
        "normalized_files": norm_lib_files,
    }
    swiftmtp_payload: Dict[str, Any] = {
        "probe": swiftmtp_probe,
        "ls": swiftmtp_ls,
        "normalized_device": norm_swift_dev,
        "normalized_files": norm_swift_files,
    }

    _write_evidence(
        run_dir,
        meta=meta,
        libmtp_raw=libmtp_payload,
        swiftmtp_raw=swiftmtp_payload,
        diffs=diffs,
        write_results=write_results,
        swiftmtp_log=swiftmtp_log,
        libmtp_log=libmtp_log,
    )
    print()

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    counts = _summary_counts(diffs)
    print("=" * 68)
    print("  Results")
    print("=" * 68)
    print(f"  Total diffs      : {len(diffs)}")
    for lbl in _ALL_LABELS:
        n = counts.get(lbl, 0)
        if n:
            print(f"    {lbl:<20}: {n}")
    if write_results:
        all_passed = all(v.get("success") for v in write_results.values())
        print(f"  Write tests      : {'PASS' if all_passed else 'FAIL'}")
    print()
    print(f"  Evidence dir     : {run_dir}")
    print(f"  Diff report      : {run_dir / 'diff.md'}")
    print()

    # Exit non-zero when there are unresolved diffs that need investigation.
    unresolved = counts.get(LABEL_UNKNOWN, 0) + counts.get(LABEL_BUG_SWIFTMTP, 0)
    return 1 if unresolved > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
