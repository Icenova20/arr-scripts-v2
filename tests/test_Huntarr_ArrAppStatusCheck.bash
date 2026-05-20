#!/bin/bash

# Define where the main script is
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Extract ArrAppStatusCheck function
temp_file="$SCRIPT_DIR/tests/temp_ArrAppStatusCheck.bash"
trap 'rm -f "$temp_file"' EXIT

sed -n '/ArrAppStatusCheck () {/,/^}/p' "$SCRIPT_DIR/Huntarr.bash" > "$temp_file"

source "$temp_file"

# Mock variables
export arrUrl="http://mock-arr"
export arrApiVersion="v3"
export arrApiKey="mock-key"

# Mock touch to capture output
touch() {
  echo "TOUCH: $1"
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

echo "Testing ArrAppStatusCheck..."

# Test 1: Queue < 3 and Tasks < 3 (No touch)
curl() {
  local url="$2"
  if [[ "$url" == *"queue"* ]]; then
    echo '{"records": [{"status": "queued", "id": 1}, {"status": "completed", "id": 2}]}'
  elif [[ "$url" == *"command"* ]]; then
    echo '[{"status": "started", "name": "Task1"}, {"status": "finished", "name": "Task2"}]'
  fi
}
export -f curl

output=$(ArrAppStatusCheck)
expected_output=""
check_output "Both < 3" "$expected_output" "$output"

# Test 2: Queue >= 3 (Touch)
curl() {
  local url="$2"
  if [[ "$url" == *"queue"* ]]; then
    echo '{"records": [{"status": "queued", "id": 1}, {"status": "queued", "id": 2}, {"status": "queued", "id": 3}]}'
  elif [[ "$url" == *"command"* ]]; then
    echo '[]'
  fi
}
export -f curl

output=$(ArrAppStatusCheck)
expected_output="TOUCH: /config/huntarr-break"
check_output "Queue >= 3" "$expected_output" "$output"

# Test 3: Tasks >= 3 (Touch)
curl() {
  local url="$2"
  if [[ "$url" == *"queue"* ]]; then
    echo '{"records": []}'
  elif [[ "$url" == *"command"* ]]; then
    echo '[{"status": "started", "name": "Task1"}, {"status": "started", "name": "Task2"}, {"status": "started", "name": "Task3"}]'
  fi
}
export -f curl

output=$(ArrAppStatusCheck)
expected_output="TOUCH: /config/huntarr-break"
check_output "Tasks >= 3" "$expected_output" "$output"

echo "Tests passed: $passed"
echo "Tests failed: $failed"

if [ "$failed" -gt 0 ]; then
  echo "Failures occurred"
  exit 1
else
  echo "All tests passed successfully"
  exit 0
fi
