#!/bin/bash
set -e

# Build the fuzzer
echo "Building SwiftMTPFuzz..."
swift build -c release --product SwiftMTPFuzz

# Location of the binary
BIN=$(swift build -c release --show-bin-path)/SwiftMTPFuzz

# Create a dummy input if none provided
INPUT=$1
if [ -z "$INPUT" ]; then
    echo "No input file provided, creating a random test input..."
    INPUT="fuzz_input.bin"
    head -c 100 /dev/urandom > $INPUT
fi

echo "Running Fuzzer on $INPUT..."
$BIN "$INPUT"

echo "Fuzzing run completed (no crash)."
