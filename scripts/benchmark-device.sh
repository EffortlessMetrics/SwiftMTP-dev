#!/usr/bin/env bash
# SwiftMTP Device Benchmark Script (v2)
# Usage: ./benchmark-device.sh <device-name>

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/benches"
PROBES_DIR="$PROJECT_ROOT/probes"
LOGS_DIR="$PROJECT_ROOT/logs"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Default values
DEVICE_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -*)
      echo "Unknown option: $1"
      echo "Usage: $0 <device-name>"
      echo "Note: This script now uses real devices only (--real-only)"
      exit 1
      ;;
    *)
      if [[ -z "$DEVICE_NAME" ]]; then
        DEVICE_NAME="$1"
      else
        echo "Too many arguments. Expected device name only."
        echo "Usage: $0 <device-name>"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$DEVICE_NAME" ]]; then
  echo "Device name is required."
  echo "Usage: $0 <device-name>"
  echo "Note: This script uses real devices only (--real-only)"
  exit 1
fi

# Create output directories
mkdir -p "$OUTPUT_DIR/$DEVICE_NAME" "$PROBES_DIR" "$LOGS_DIR"

echo "== $DEVICE_NAME =="
echo "📁 Output: $OUTPUT_DIR/$DEVICE_NAME/"
echo "📁 Probes: $PROBES_DIR/"
echo "📁 Logs: $LOGS_DIR/"

# Build CLI
cd "$PROJECT_ROOT/SwiftMTPKit"
echo "🔨 Building SwiftMTP CLI..."
swift build --configuration release

# Function to run benchmark with p50/p95 calculation
run_bench() {
  local size="$1"
  local csv_file="$OUTPUT_DIR/$DEVICE_NAME/bench-${size}.csv"
  local desc="${size} transfer benchmark"

  echo "🏃 $desc..."

  # Run benchmark with CSV output
  if swift run swiftmtp --real-only bench "$size" --repeat 3 --out "$csv_file"; then
    echo "✅ $desc completed"

    # Calculate p50/p95 from passes 2-3 (ignore first pass warmup)
    awk -F, 'NR==1{next} {print $0}' "$csv_file" \
      | tail -n +2 \
      | awk -F, 'NR>=2 && NR<=3 {sum+=$NF; cnt++; if(min==""||$NF<min)min=$NF; if($NF>max)max=$NF} END {if(cnt>0) printf("  %s: p50≈%.2f MB/s  p95≈%.2f MB/s\n", "'"$size"'", sum/cnt, max)}'
  else
    echo "❌ $desc failed"
    return 1
  fi
}

# Run probe
echo "🔍 Running device probe..."
if swift run swiftmtp --real-only probe | tee "$PROBES_DIR/${DEVICE_NAME}-probe.txt"; then
  echo "✅ Device probe completed"
else
  echo "❌ Device probe failed"
  exit 1
fi

# Run benchmark suite
echo "📊 Running transfer benchmarks..."

run_bench 100M
run_bench 500M
run_bench 1G

# Test mirror functionality (optional)
echo "🔄 Testing mirror functionality..."
if swift run swiftmtp --real-only mirror ~/PhoneBackup --include "DCIM/**" --out "$LOGS_DIR/${DEVICE_NAME}-mirror.log" 2>&1; then
  echo "✅ Mirror test completed"
else
  echo "⚠️  Mirror test failed (may be expected if no DCIM or PhoneBackup)"
fi

# Generate summary report
echo "📋 Generating summary report..."
{
  echo "# SwiftMTP Benchmark Report"
  echo "Device: $DEVICE_NAME"
  echo "Timestamp: $(date)"
  echo "Mode: Real Hardware (--real-only)"
  echo "SwiftMTP Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  echo ""

  if [[ -f "$PROBES_DIR/${DEVICE_NAME}-probe.txt" ]]; then
    echo "## Device Information"
    echo '```'
    cat "$PROBES_DIR/${DEVICE_NAME}-probe.txt"
    echo '```'
    echo ""
  fi

  echo "## Benchmark Results (p50/p95 from passes 2-3)"
  for csv_file in "$OUTPUT_DIR/$DEVICE_NAME"/bench-*.csv; do
    if [[ -f "$csv_file" ]]; then
      bench_size=$(basename "$csv_file" | sed 's/bench-\(.*\)\.csv/\1/')
      echo "### $bench_size Transfer"
      echo '```csv'
      cat "$csv_file"
      echo '```'
      echo ""

      # Show p50/p95 summary
      awk -F, 'NR==1{next} {print $0}' "$csv_file" \
        | tail -n +2 \
        | awk -F, 'NR>=2 && NR<=3 {sum+=$NF; cnt++; if(min==""||$NF<min)min=$NF; if($NF>max)max=$NF} END {if(cnt>0) printf("- **p50**: %.2f MB/s\n- **p95**: %.2f MB/s\n", sum/cnt, max)}'
      echo ""
    fi
  done

  if [[ -f "$LOGS_DIR/${DEVICE_NAME}-mirror.log" ]]; then
    echo "## Mirror Test"
    echo '```'
    tail -20 "$LOGS_DIR/${DEVICE_NAME}-mirror.log"
    echo '```'
  fi

} > "$OUTPUT_DIR/$DEVICE_NAME/benchmark-report.md"

echo "✅ Benchmark complete!"
echo "📊 Results saved to: $OUTPUT_DIR/$DEVICE_NAME/"
echo "📁 Probes: $PROBES_DIR/"
echo "📁 Logs: $LOGS_DIR/"
echo "📄 Summary report: $OUTPUT_DIR/$DEVICE_NAME/benchmark-report.md"

echo ""
echo "🎯 Next steps:"
echo "1. Review the benchmark report: $OUTPUT_DIR/$DEVICE_NAME/benchmark-report.md"
echo "2. Add p50/p95 results to Docs/benchmarks.md"
echo "3. Test resume scenarios manually if needed"
echo "4. Commit artifacts: probes/, benches/, logs/"
