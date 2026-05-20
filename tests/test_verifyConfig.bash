#!/bin/bash

# Define where the main script is
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Extract verifyConfig function
temp_file="$SCRIPT_DIR/tests/temp_verifyConfig.bash"
trap 'rm -f "$temp_file"' EXIT

sed -n '/verifyConfig () {/,/^}/p' "$SCRIPT_DIR/Radarr-UnmappedFolderCleaner.bash" > "$temp_file"

source "$temp_file"

# Mock log and sleep to capture output
log() {
  echo "LOG: $1"
}

sleep() {
  echo "SLEEP: $1"
}

# Counters for test results
passed=0
failed=0

# Helper to check output
check_output() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$expected" == "$actual" ]; then
    echo "✅ $test_name passed"
    passed=$((passed + 1))
  else
    echo "❌ $test_name failed"
    echo "Expected:"
    echo "$expected"
    echo "Actual:"
    echo "$actual"
    failed=$((failed + 1))
  fi
}

echo "Testing verifyConfig..."

# Test 1: enableUnmappedFolderCleaner = true
enableUnmappedFolderCleaner="true"
output=$(verifyConfig)
expected_output=""

check_output "enableUnmappedFolderCleaner='true'" "$expected_output" "$output"

# Test 2: enableUnmappedFolderCleaner = false
enableUnmappedFolderCleaner="false"
output=$(verifyConfig)
expected_output="LOG: Script is not enabled, enable by setting enableUnmappedFolderCleaner to \"true\" by modifying the \"/config/extended.conf\" config file...
LOG: Sleeping (infinity)
SLEEP: infinity"

check_output "enableUnmappedFolderCleaner='false'" "$expected_output" "$output"

# Test 3: enableUnmappedFolderCleaner is empty
enableUnmappedFolderCleaner=""
output=$(verifyConfig)
check_output "enableUnmappedFolderCleaner is empty" "$expected_output" "$output"

echo "Tests passed: $passed"
echo "Tests failed: $failed"

if [ "$failed" -gt 0 ]; then
  echo "Failures occurred"
  false
else
  echo "All tests passed successfully"
  true
fi
