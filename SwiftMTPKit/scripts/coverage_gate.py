#!/usr/bin/env python3
"""Compute filtered SwiftPM line coverage and enforce a threshold."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class FileStat:
    path: str
    module: str
    covered: int
    count: int

    @property
    def percent(self) -> float:
        if self.count == 0:
            return 100.0
        return (self.covered / self.count) * 100.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Enforce filtered SwiftPM coverage threshold")
    parser.add_argument("--coverage-json", required=True, help="Path to SwiftPM codecov JSON")
    parser.add_argument(
        "--modules",
        default="SwiftMTPQuirks,SwiftMTPStore,SwiftMTPSync,SwiftMTPObservability",
        help="Comma-separated source modules to include in coverage math",
    )
    parser.add_argument("--threshold", type=float, default=90.0, help="Minimum overall coverage percent")
    parser.add_argument("--output-json", default="", help="Optional output JSON path")
    parser.add_argument("--output-text", default="", help="Optional output text path")
    parser.add_argument("--worst-files", type=int, default=20, help="Number of low-coverage files to print")
    return parser.parse_args()


def source_module(path: str) -> str | None:
    marker = "/Sources/"
    if marker not in path:
        return None
    after = path.split(marker, 1)[1]
    if "/" not in after:
        return None
    return after.split("/", 1)[0]


def load_file_stats(coverage_json: Path, modules: set[str]) -> list[FileStat]:
    with coverage_json.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    files = payload.get("data", [{}])[0].get("files", [])
    stats: list[FileStat] = []

    for item in files:
        path = item.get("filename", "")
        module = source_module(path)
        if module is None or module not in modules:
            continue

        lines = item.get("summary", {}).get("lines", {})
        count = int(lines.get("count", 0))
        covered = int(lines.get("covered", 0))
        if count <= 0:
            continue

        stats.append(FileStat(path=path, module=module, covered=covered, count=count))

    return stats


def render_report(
    stats: list[FileStat], modules: list[str], threshold: float, worst_files: int
) -> tuple[str, dict]:
    module_totals: dict[str, dict[str, int]] = {module: {"covered": 0, "count": 0} for module in modules}
    overall_covered = 0
    overall_count = 0

    for stat in stats:
        module_totals[stat.module]["covered"] += stat.covered
        module_totals[stat.module]["count"] += stat.count
        overall_covered += stat.covered
        overall_count += stat.count

    overall_percent = (overall_covered / overall_count * 100.0) if overall_count else 0.0
    passed = overall_percent >= threshold

    lines: list[str] = []
    lines.append("SwiftMTP Filtered Coverage")
    lines.append("==========================")
    lines.append(f"Threshold: {threshold:.2f}%")
    lines.append(f"Overall:   {overall_percent:.2f}% ({overall_covered}/{overall_count})")
    lines.append(f"Status:    {'PASS' if passed else 'FAIL'}")
    lines.append("")
    lines.append("Module Coverage:")

    per_module_payload: dict[str, dict[str, float | int]] = {}
    for module in modules:
        covered = module_totals[module]["covered"]
        count = module_totals[module]["count"]
        percent = (covered / count * 100.0) if count else 0.0
        lines.append(f"  - {module}: {percent:.2f}% ({covered}/{count})")
        per_module_payload[module] = {
            "covered": covered,
            "count": count,
            "percent": percent,
        }

    lines.append("")
    lines.append(f"Worst {worst_files} Files:")
    for stat in sorted(stats, key=lambda item: (item.percent, item.count))[:worst_files]:
        lines.append(f"  - {stat.percent:6.2f}%  {stat.path}")

    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "threshold": threshold,
        "status": "pass" if passed else "fail",
        "overall": {
            "covered": overall_covered,
            "count": overall_count,
            "percent": overall_percent,
        },
        "modules": per_module_payload,
        "files": [
            {
                "path": stat.path,
                "module": stat.module,
                "covered": stat.covered,
                "count": stat.count,
                "percent": stat.percent,
            }
            for stat in sorted(stats, key=lambda item: (item.percent, item.count))
        ],
    }

    return "\n".join(lines) + "\n", payload


def main() -> int:
    args = parse_args()
    coverage_json = Path(args.coverage_json)
    if not coverage_json.exists():
        print(f"error: coverage JSON not found: {coverage_json}", file=sys.stderr)
        return 2

    modules = [token.strip() for token in args.modules.split(",") if token.strip()]
    if not modules:
        print("error: at least one module is required", file=sys.stderr)
        return 2

    module_set = set(modules)
    stats = load_file_stats(coverage_json, module_set)
    if not stats:
        print("error: no matching source files found for selected modules", file=sys.stderr)
        return 2

    report, payload = render_report(stats=stats, modules=modules, threshold=args.threshold, worst_files=args.worst_files)
    print(report, end="")

    if args.output_text:
        output_text = Path(args.output_text)
        output_text.parent.mkdir(parents=True, exist_ok=True)
        output_text.write_text(report, encoding="utf-8")

    if args.output_json:
        output_json = Path(args.output_json)
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    return 0 if payload["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
