#!/usr/bin/env python3
"""
SwiftMTP Coverage Report Generator

This script parses Swift's LLVM coverage output and generates:
1. HTML report with color-coded coverage visualization
2. JSON output for CI integration
3. Per-file and per-function coverage breakdown
4. Highlights uncovered lines

Usage:
    python coverage-report.py [--profdata PATH] [--output DIR] [--format FORMAT]

Requirements:
    - Python 3.7+
    - Swift's llvm-cov output or JSON coverage data
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from enum import Enum


class CoverageStatus(Enum):
    COVERED = "covered"
    UNCOVERED = "uncovered"
    PARTIAL = "partial"
    IGNORED = "ignored"


@dataclass
class FunctionCoverage:
    name: str
    line_start: int
    line_end: int
    covered_lines: List[int] = field(default_factory=list)
    uncovered_lines: List[int] = field(default_factory=list)
    
    @property
    def coverage_percentage(self) -> float:
        total = len(self.covered_lines) + len(self.uncovered_lines)
        if total == 0:
            return 100.0
        return (len(self.covered_lines) / total) * 100


@dataclass
class FileCoverage:
    path: str
    functions: List[FunctionCoverage] = field(default_factory=list)
    covered_lines: List[int] = field(default_factory=list)
    uncovered_lines: List[int] = field(default_factory=list)
    ignored_lines: List[int] = field(default_factory=list)
    
    @property
    def total_lines(self) -> int:
        return len(self.covered_lines) + len(self.uncovered_lines)
    
    @property
    def coverage_percentage(self) -> float:
        total = self.total_lines
        if total == 0:
            return 100.0
        return (len(self.covered_lines) / total) * 100


class SwiftCoverageParser:
    """Parser for Swift LLVM coverage output formats."""
    
    # Regex patterns for llvm-cov text output
    LINE_PATTERN = re.compile(
        r'^\s*(\d+)\s+\|?\s*([^\n]*)$'
    )
    
    FUNCTION_PATTERN = re.compile(
        r'^Function: (\w+)\s+\((\d+)\.\.(\d+)\)$'
    )
    
    BRANCH_PATTERN = re.compile(
        r'^Branch\s+(\d+):\s+(Taken|Not Taken)$'
    )
    
    @staticmethod
    def parse_llvm_cov_text(output: str) -> Dict[str, FileCoverage]:
        """Parse llvm-cov text output into FileCoverage objects."""
        files: Dict[str, FileCoverage] = {}
        current_file: Optional[FileCoverage] = None
        current_function: Optional[FunctionCoverage] = None
        
        lines = output.split('\n')
        i = 0
        
        while i < len(lines):
            line = lines[i]
            
            # Check for file header
            if line.startswith('Source Files in'):
                # Skip source files list
                i += 1
                continue
            
            # Check for function marker
            if line.startswith('Function: '):
                match = re.match(r'Function: (\w+)\s+\((\d+)\.\.(\d+)\)', line)
                if match and current_file:
                    current_function = FunctionCoverage(
                        name=match.group(1),
                        line_start=int(match.group(2)),
                        line_end=int(match.group(3))
                    )
                    current_file.functions.append(current_function)
                i += 1
                continue
            
            # Check for file path header
            if line.startswith('/') or line.startswith('./'):
                file_path = line.strip()
                if file_path not in files:
                    files[file_path] = FileCoverage(path=file_path)
                current_file = files[file_path]
                i += 1
                continue
            
            # Parse line coverage data
            match = re.match(r'^\s*(\d+)\s+\|?\s*([^\n]*)$', line)
            if match and current_file:
                line_num = int(match.group(1))
                code = match.group(2).strip()
                
                # Skip empty lines and markers
                if not code or code.startswith('//') or 'swiftcoverage:ignore' in code:
                    if code and 'swiftcoverage:ignore' in code:
                        current_file.ignored_lines.append(line_num)
                    continue
                
                # Check coverage indicator (typically at start of line)
                if line.startswith('     ') or line.startswith('      '):
                    # Uncovered line
                    current_file.uncovered_lines.append(line_num)
                    if current_function:
                        current_function.uncovered_lines.append(line_num)
                else:
                    # Covered line
                    current_file.covered_lines.append(line_num)
                    if current_function:
                        current_function.covered_lines.append(line_num)
            
            i += 1
        
        return files


class CoverageReportGenerator:
    """Generates coverage reports in various formats."""
    
    def __init__(self, files: Dict[str, FileCoverage]):
        self.files = files
        self.timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    def generate_html_report(self, output_path: str) -> None:
        """Generate an HTML coverage report with color-coded visualization."""
        
        html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SwiftMTP Coverage Report</title>
    <style>
        :root {{
            --covered-color: #28a745;
            --uncovered-color: #dc3545;
            --partial-color: #ffc107;
            --ignored-color: #6c757d;
            --bg-color: #f8f9fa;
            --card-bg: #ffffff;
            --text-color: #212529;
            --border-color: #dee2e6;
        }}
        
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-color);
            color: var(--text-color);
            margin: 0;
            padding: 20px;
        }}
        
        .container {{
            max-width: 1400px;
            margin: 0 auto;
        }}
        
        header {{
            background: var(--card-bg);
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }}
        
        h1 {{
            margin: 0 0 10px 0;
            color: var(--text-color);
        }}
        
        .meta {{
            color: #6c757d;
            font-size: 0.9em;
        }}
        
        .summary-cards {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }}
        
        .card {{
            background: var(--card-bg);
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }}
        
        .card-title {{
            font-size: 0.85em;
            text-transform: uppercase;
            color: #6c757d;
            margin-bottom: 5px;
        }}
        
        .card-value {{
            font-size: 2em;
            font-weight: bold;
        }}
        
        .card-value.good {{ color: var(--covered-color); }}
        .card-value.warning {{ color: var(--partial-color); }}
        .card-value.bad {{ color: var(--uncovered-color); }}
        
        table {{
            width: 100%;
            border-collapse: collapse;
            background: var(--card-bg);
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }}
        
        th, td {{
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }}
        
        th {{
            background: #f8f9fa;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.8em;
            letter-spacing: 0.5px;
        }}
        
        tr:hover {{ background: #f8f9fa; }}
        
        .coverage-bar {{
            width: 100%;
            height: 20px;
            background: #e9ecef;
            border-radius: 10px;
            overflow: hidden;
        }}
        
        .coverage-fill {{
            height: 100%;
            border-radius: 10px;
            transition: width 0.3s ease;
        }}
        
        .coverage-fill.good {{ background: var(--covered-color); }}
        .coverage-fill.warning {{ background: var(--partial-color); }}
        .coverage-fill.bad {{ background: var(--uncovered-color); }}
        
        .file-section {{
            background: var(--card-bg);
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            overflow: hidden;
        }}
        
        .file-header {{
            padding: 15px 20px;
            background: #f8f9fa;
            border-bottom: 1px solid var(--border-color);
            cursor: pointer;
        }}
        
        .file-header:hover {{ background: #e9ecef; }}
        
        .file-content {{
            display: none;
            padding: 20px;
        }}
        
        .file-content.expanded {{ display: block; }}
        
        .line-numbers {{
            font-family: 'SF Mono', Monaco, 'Courier New', monospace;
            font-size: 13px;
            line-height: 1.6;
            white-space: pre;
            overflow-x: auto;
        }}
        
        .line-covered {{
            background: rgba(40, 167, 69, 0.15);
            display: inline-block;
            width: 100%;
        }}
        
        .line-uncovered {{
            background: rgba(220, 53, 69, 0.15);
            display: inline-block;
            width: 100%;
        }}
        
        .line-number {{
            display: inline-block;
            width: 50px;
            color: #6c757d;
            user-select: none;
        }}
        
        .line-code {{
            color: var(--text-color);
        }}
        
        .legend {{
            display: flex;
            gap: 20px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }}
        
        .legend-item {{
            display: flex;
            align-items: center;
            gap: 8px;
        }}
        
        .legend-color {{
            width: 16px;
            height: 16px;
            border-radius: 4px;
        }}
        
        .search-box {{
            padding: 10px 15px;
            border: 1px solid var(--border-color);
            border-radius: 6px;
            font-size: 14px;
            width: 300px;
            margin-bottom: 20px;
        }}
        
        .badge {{
            display: inline-block;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 0.75em;
            font-weight: 600;
        }}
        
        .badge-good {{ background: rgba(40, 167, 69, 0.15); color: var(--covered-color); }}
        .badge-bad {{ background: rgba(220, 53, 69, 0.15); color: var(--uncovered-color); }}
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>📊 SwiftMTP Code Coverage Report</h1>
            <div class="meta">Generated: {self.timestamp}</div>
        </header>
        
        <div class="summary-cards">
            <div class="card">
                <div class="card-title">Files Analyzed</div>
                <div class="card-value">{len(self.files)}</div>
            </div>
            <div class="card">
                <div class="card-title">Total Lines</div>
                <div class="card-value">{sum(f.total_lines for f in self.files.values())}</div>
            </div>
            <div class="card">
                <div class="card-title">Coverage</div>
                <div class="card-value {self._get_coverage_class(self.overall_coverage)}">{self.overall_coverage:.1f}%</div>
            </div>
            <div class="card">
                <div class="card-title">Uncovered Lines</div>
                <div class="card-value warning">{sum(len(f.uncovered_lines) for f in self.files.values())}</div>
            </div>
        </div>
        
        <div class="legend">
            <div class="legend-item">
                <div class="legend-color" style="background: var(--covered-color);"></div>
                <span>Covered</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: var(--uncovered-color);"></div>
                <span>Uncovered</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: var(--ignored-color);"></div>
                <span>Ignored</span>
            </div>
        </div>
        
        <input type="text" class="search-box" placeholder="Search files..." id="searchBox">
        
        <table>
            <thead>
                <tr>
                    <th>File</th>
                    <th>Coverage</th>
                    <th>Lines</th>
                    <th>Functions</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
                {self._generate_file_table_rows()}
            </tbody>
        </table>
        
        {self._generate_file_details()}
        
    </div>
    
    <script>
        function toggleFile(id) {{
            const content = document.getElementById(id);
            content.classList.toggle('expanded');
        }}
        
        document.getElementById('searchBox').addEventListener('input', function(e) {{
            const query = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('tbody tr');
            rows.forEach(row => {{
                const fileName = row.querySelector('td:first-child').textContent.toLowerCase();
                row.style.display = fileName.includes(query) ? '' : 'none';
            }});
        }});
    </script>
</body>
</html>"""
        
        with open(output_path, 'w') as f:
            f.write(html_content)
        
        print(f"HTML report generated: {output_path}")
    
    def generate_json_report(self, output_path: str, threshold_overall: float = 75.0) -> None:
        """Generate JSON report for CI integration."""
        
        report = {
            "project": "SwiftMTPKit",
            "timestamp": self.timestamp,
            "version": os.environ.get("GITHUB_SHA", "unknown"),
            "summary": {
                "total_files": len(self.files),
                "total_lines": sum(f.total_lines for f in self.files.values()),
                "covered_lines": sum(len(f.covered_lines) for f in self.files.values()),
                "uncovered_lines": sum(len(f.uncovered_lines) for f in self.files.values()),
                "ignored_lines": sum(len(f.ignored_lines) for f in self.files.values()),
                "overall_coverage": self.overall_coverage,
                "threshold": threshold_overall,
                "status": "pass" if self.overall_coverage >= threshold_overall else "fail"
            },
            "files": [
                {
                    "path": path,
                    "coverage_percentage": file.coverage_percentage,
                    "total_lines": file.total_lines,
                    "covered_lines": len(file.covered_lines),
                    "uncovered_lines": len(file.uncovered_lines),
                    "ignored_lines": len(file.ignored_lines),
                    "functions": [
                        {
                            "name": func.name,
                            "coverage_percentage": func.coverage_percentage,
                            "line_start": func.line_start,
                            "line_end": func.line_end
                        }
                        for func in file.functions
                    ]
                }
                for path, file in self.files.items()
            ],
            "thresholds": {
                "overall": threshold_overall,
                "per_file": 60.0,
                "function_coverage": 70.0
            }
        }
        
        with open(output_path, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"JSON report generated: {output_path}")
    
    def generate_text_summary(self, output_path: Optional[str] = None) -> str:
        """Generate human-readable text summary."""
        
        lines = [
            "=" * 60,
            "SwiftMTP Code Coverage Summary",
            "=" * 60,
            f"Generated: {self.timestamp}",
            "",
            f"Overall Coverage: {self.overall_coverage:.1f}%",
            f"Total Files: {len(self.files)}",
            f"Total Lines: {sum(f.total_lines for f in self.files.values())}",
            f"Covered Lines: {sum(len(f.covered_lines) for f in self.files.values())}",
            f"Uncovered Lines: {sum(len(f.uncovered_lines) for f in self.files.values())}",
            "",
            "-" * 60,
            "Per-File Coverage:",
            "-" * 60,
        ]
        
        # Sort files by coverage percentage
        sorted_files = sorted(
            self.files.values(),
            key=lambda f: f.coverage_percentage,
            reverse=True
        )
        
        for file in sorted_files:
            coverage_class = self._get_coverage_class(file.coverage_percentage)
            status_icon = "✓" if file.coverage_percentage >= 60 else "✗"
            
            lines.append(
                f"{status_icon} {file.path}: {file.coverage_percentage:.1f}% "
                f"({len(file.covered_lines)}/{file.total_lines} lines)"
            )
        
        lines.extend([
            "",
            "-" * 60,
            "Uncovered Files (Coverage < 60%):",
            "-" * 60,
        ])
        
        low_coverage_files = [f for f in sorted_files if f.coverage_percentage < 60]
        if low_coverage_files:
            for file in low_coverage_files:
                lines.append(f"  ⚠ {file.path}")
        else:
            lines.append("  (none - all files meet minimum threshold)")
        
        lines.extend([
            "",
            "=" * 60,
        ])
        
        summary = "\n".join(lines)
        
        if output_path:
            with open(output_path, 'w') as f:
                f.write(summary)
            print(f"Text summary generated: {output_path}")
        
        return summary
    
    @property
    def overall_coverage(self) -> float:
        """Calculate overall coverage percentage across all files."""
        total_covered = sum(len(f.covered_lines) for f in self.files.values())
        total_lines = sum(f.total_lines for f in self.files.values())
        
        if total_lines == 0:
            return 100.0
        
        return (total_covered / total_lines) * 100
    
    def _get_coverage_class(self, coverage: float) -> str:
        """Get CSS class based on coverage percentage."""
        if coverage >= 80:
            return "good"
        elif coverage >= 60:
            return "warning"
        else:
            return "bad"
    
    def _generate_file_table_rows(self) -> str:
        """Generate HTML table rows for files."""
        rows = []
        
        sorted_files = sorted(
            self.files.values(),
            key=lambda f: f.coverage_percentage,
            reverse=True
        )
        
        for file in sorted_files:
            coverage_class = self._get_coverage_class(file.coverage_percentage)
            coverage_width = min(100, file.coverage_percentage)
            
            status = "✓" if file.coverage_percentage >= 60 else "⚠"
            badge_class = "badge-good" if file.coverage_percentage >= 60 else "badge-bad"
            badge_text = "PASS" if file.coverage_percentage >= 60 else "LOW"
            
            rows.append(f"""
                <tr>
                    <td><a href="#file-{hash(file.path)}">{file.path}</a></td>
                    <td>
                        <div style="display: flex; align-items: center; gap: 10px;">
                            <div style="width: 100px;">
                                <div class="coverage-bar">
                                    <div class="coverage-fill {coverage_class}" style="width: {coverage_width}%"></div>
                                </div>
                            </div>
                            <span>{file.coverage_percentage:.1f}%</span>
                        </div>
                    </td>
                    <td>{len(file.covered_lines)}/{file.total_lines}</td>
                    <td>{len(file.functions)}</td>
                    <td><span class="badge {badge_class}">{badge_text}</span></td>
                </tr>
            """)
        
        return "\n".join(rows)
    
    def _generate_file_details(self) -> str:
        """Generate detailed sections for each file with line-by-line coverage."""
        sections = []
        
        for path, file in self.files.items():
            file_id = f"file-{hash(path)}"
            
            lines_html = []
            for i, line_num in enumerate(sorted(file.covered_lines + file.uncovered_lines)):
                if line_num in file.covered_lines:
                    lines_html.append(
                        f'<div class="line-covered">'
                        f'<span class="line-number">{line_num}</span>'
                        f'<span class="line-code">// covered line</span>'
                        f'</div>'
                    )
                else:
                    lines_html.append(
                        f'<div class="line-uncovered">'
                        f'<span class="line-number">{line_num}</span>'
                        f'<span class="line-code">// UNCOVERED</span>'
                        f'</div>'
                    )
            
            sections.append(f"""
                <div class="file-section" id="{file_id}">
                    <div class="file-header" onclick="toggleFile('content-{file_id}')">
                        <strong>{path}</strong> - {file.coverage_percentage:.1f}% coverage
                        ({len(file.covered_lines)}/{file.total_lines} lines)
                    </div>
                    <div class="file-content" id="content-{file_id}">
                        <div class="line-numbers">
                            {''.join(lines_html)}
                        </div>
                    </div>
                </div>
            """)
        
        return "\n".join(sections)


def main():
    parser = argparse.ArgumentParser(
        description="Generate coverage reports from Swift LLVM coverage data"
    )
    parser.add_argument(
        "--input", "-i",
        help="Input file containing llvm-cov output (or use --profdata)"
    )
    parser.add_argument(
        "--profdata", "-p",
        help="Path to .profdata coverage file"
    )
    parser.add_argument(
        "--sources", "-s",
        help="Source files/directories to analyze"
    )
    parser.add_argument(
        "--output", "-o",
        default="coverage",
        help="Output directory for reports"
    )
    parser.add_argument(
        "--format", "-f",
        choices=["html", "json", "text", "all"],
        default="all",
        help="Output format (default: all)"
    )
    parser.add_argument(
        "--threshold", "-t",
        type=float,
        default=75.0,
        help="Coverage threshold percentage (default: 75)"
    )
    
    args = parser.parse_args()
    
    # Determine input source
    if args.input:
        with open(args.input, 'r') as f:
            input_data = f.read()
        
        parser = SwiftCoverageParser()
        files = parser.parse_llvm_cov_text(input_data)
    elif args.profdata and args.sources:
        print("Note: Direct .profdata parsing requires llvm-cov tool")
        print("Please run: swift test --enable-code-coverage")
        print("Then use: llvm cov show -instr-profile=<profdata> -sources=<sources>")
        sys.exit(1)
    else:
        print("Error: Either --input or --profdata/--sources required")
        print("Example: swift test --enable-code-coverage")
        print("Then run: llvm-cov show ... > coverage.txt")
        print("Finally: python coverage-report.py -i coverage.txt")
        sys.exit(1)
    
    # Create output directory
    Path(args.output).mkdir(parents=True, exist_ok=True)
    
    # Generate reports
    generator = CoverageReportGenerator(files)
    
    if args.format in ["html", "all"]:
        generator.generate_html_report(f"{args.output}/report.html")
    
    if args.format in ["json", "all"]:
        generator.generate_json_report(f"{args.output}/coverage.json", args.threshold)
    
    if args.format in ["text", "all"]:
        generator.generate_text_summary(f"{args.output}/summary.txt")
    
    # Print summary
    print()
    print(generator.generate_text_summary())
    
    # Exit with appropriate code
    if generator.overall_coverage >= args.threshold:
        print(f"\n✅ Coverage {generator.overall_coverage:.1f}% meets threshold {args.threshold}%")
        sys.exit(0)
    else:
        print(f"\n❌ Coverage {generator.overall_coverage:.1f}% below threshold {args.threshold}%")
        sys.exit(1)


if __name__ == "__main__":
    main()
