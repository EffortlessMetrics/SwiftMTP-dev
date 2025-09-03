#!/bin/bash
# SwiftMTP Device Benchmark Script
# Usage: ./benchmark-device.sh <device-name> [--real|--mock <profile>]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/Docs/benchmarks"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Default values
USE_REAL=false
MOCK_PROFILE=""
DEVICE_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --real)
      USE_REAL=true
      shift
      ;;
    --mock)
      MOCK_PROFILE="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Usage: $0 <device-name> [--real|--mock <profile>]"
      exit 1
      ;;
    *)
      if [[ -z "$DEVICE_NAME" ]]; then
        DEVICE_NAME="$1"
      else
        echo "Too many arguments. Expected device name only."
        echo "Usage: $0 <device-name> [--real|--mock <profile>]"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$DEVICE_NAME" ]]; then
  echo "Device name is required."
  echo "Usage: $0 <device-name> [--real|--mock <profile>]"
  exit 1
fi

if [[ "$USE_REAL" == false && -z "$MOCK_PROFILE" ]]; then
  echo "Must specify either --real or --mock <profile>"
  echo "Usage: $0 <device-name> [--real|--mock <profile>]"
  exit 1
fi

# Create output directory
DEVICE_DIR="$OUTPUT_DIR/$DEVICE_NAME"
RUN_DIR="$DEVICE_DIR/$TIMESTAMP"
mkdir -p "$RUN_DIR"

echo "🧪 Starting SwiftMTP benchmark for: $DEVICE_NAME"
echo "📁 Output directory: $RUN_DIR"

# Build CLI if needed
cd "$PROJECT_ROOT/SwiftMTPKit"
if [[ "$USE_REAL" == true ]]; then
  echo "🔨 Building SwiftMTP CLI..."
  swift build --configuration release
fi

# Function to run command with timing
run_cmd() {
  local cmd="$1"
  local output_file="$2"
  local description="$3"

  echo "🏃 $description..."
  echo "Command: $cmd"

  # Ensure we're in the SwiftMTPKit directory
  cd "$PROJECT_ROOT/SwiftMTPKit"

  if [[ -n "$output_file" ]]; then
    if eval "$cmd" > "$output_file" 2>&1; then
      echo "✅ $description completed"
    else
      echo "❌ $description failed"
      return 1
    fi
  else
    if eval "$cmd"; then
      echo "✅ $description completed"
    else
      echo "❌ $description failed"
      return 1
    fi
  fi
}

# Prepare CLI command prefix
if [[ "$USE_REAL" == true ]]; then
  CLI_CMD="swift run swiftmtp"
else
  CLI_CMD="swift run swiftmtp --mock $MOCK_PROFILE"
fi

# Run probe
run_cmd "$CLI_CMD probe" "$RUN_DIR/probe.txt" "Device capability probe"

# Run benchmark suite
echo "📊 Running transfer benchmarks..."

# Large file benchmark (1GB)
run_cmd "$CLI_CMD bench 1G --repeat 3" "$RUN_DIR/bench-1g.txt" "1GB transfer benchmark"

# Medium file benchmark (500MB)
run_cmd "$CLI_CMD bench 500M --repeat 3" "$RUN_DIR/bench-500m.txt" "500MB transfer benchmark"

# Small file benchmark (100MB)
run_cmd "$CLI_CMD bench 100M --repeat 3" "$RUN_DIR/bench-100m.txt" "100MB transfer benchmark"

# Test mirror functionality (if device has content)
echo "🔄 Testing mirror functionality..."
if [[ "$USE_REAL" == true ]]; then
  # For real devices, mirror a small directory
  run_cmd "$CLI_CMD mirror /tmp/swiftmtp-test-mirror --include \"*.jpg\" --max-files 5" "$RUN_DIR/mirror-test.txt" "Mirror test (first 5 JPG files)"
else
  # For mock devices, mirror everything (it's fast)
  run_cmd "$CLI_CMD mirror /tmp/swiftmtp-test-mirror" "$RUN_DIR/mirror-test.txt" "Mirror test (all files)"
fi

# Generate summary report
echo "📋 Generating summary report..."
{
  echo "# SwiftMTP Benchmark Report"
  echo "Device: $DEVICE_NAME"
  echo "Timestamp: $(date)"
  echo "Mode: $(if [[ "$USE_REAL" == true ]]; then echo "Real Hardware"; else echo "Mock ($MOCK_PROFILE)"; fi)"
  echo ""

  if [[ -f "$RUN_DIR/probe.txt" ]]; then
    echo "## Device Information"
    echo '```'
    cat "$RUN_DIR/probe.txt"
    echo '```'
    echo ""
  fi

  echo "## Benchmark Results"
  for bench_file in "$RUN_DIR"/bench-*.txt; do
    if [[ -f "$bench_file" ]]; then
      bench_size=$(basename "$bench_file" | sed 's/bench-\(.*\)\.txt/\1/')
      echo "### $bench_size Transfer"
      echo '```'
      cat "$bench_file"
      echo '```'
      echo ""
    fi
  done

  if [[ -f "$RUN_DIR/mirror-test.txt" ]]; then
    echo "## Mirror Test"
    echo '```'
    tail -20 "$RUN_DIR/mirror-test.txt"
    echo '```'
  fi

} > "$RUN_DIR/benchmark-report.md"

echo "✅ Benchmark complete!"
echo "📊 Results saved to: $RUN_DIR/"
echo "📄 Summary report: $RUN_DIR/benchmark-report.md"

# Clean up temp files
if [[ -d "/tmp/swiftmtp-test-mirror" ]]; then
  rm -rf "/tmp/swiftmtp-test-mirror"
fi

echo ""
echo "🎯 Next steps:"
echo "1. Review the benchmark report: $RUN_DIR/benchmark-report.md"
echo "2. Add results to Docs/benchmarks.md"
echo "3. Test resume scenarios manually if needed"

# Create symlink to latest run
cd "$DEVICE_DIR"
rm -f latest
ln -s "$TIMESTAMP" latest
echo "🔗 Latest results linked: $DEVICE_DIR/latest"
