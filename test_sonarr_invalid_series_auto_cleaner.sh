#!/usr/bin/env bash

# test_sonarr_invalid_series_auto_cleaner.sh

FAILURES=0

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL: $message"
    echo "  Expected: '$expected'"
    echo "  Actual:   '$actual'"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: $message"
  fi
}

# Mock 'log' function
log() {
  LOG_OUTPUT+="$1\n"
}

# Mock 'sleep' function
sleep() {
  SLEEP_OUTPUT="$1"
}

# Reset test variables
reset_env() {
  LOG_OUTPUT=""
  SLEEP_OUTPUT=""
  enableInvalidSeriesAutoCleaner=""
  invalidSeriesAutoCleanerScriptInterval=""
}

# Extract and evaluate the verifyConfig function
eval "$(awk '/^verifyConfig *\(\) *\{/{flag=1; print; next} /^}/{if(flag){print; flag=0; next}} flag' Sonarr-Invalid-Series-Auto-Cleaner.bash)"

echo "Running tests for verifyConfig..."

# Test 1: Script enabled, interval empty
reset_env
enableInvalidSeriesAutoCleaner="true"
verifyConfig
assert_equals "" "$SLEEP_OUTPUT" "Should not sleep when enabled"
assert_equals "1h" "$invalidSeriesAutoCleanerScriptInterval" "Should set default interval if empty"

# Test 2: Script enabled, interval set
reset_env
enableInvalidSeriesAutoCleaner="true"
invalidSeriesAutoCleanerScriptInterval="2h"
verifyConfig
assert_equals "" "$SLEEP_OUTPUT" "Should not sleep when enabled"
assert_equals "2h" "$invalidSeriesAutoCleanerScriptInterval" "Should keep existing interval"

# Test 3: Script disabled
reset_env
enableInvalidSeriesAutoCleaner="false"
verifyConfig
assert_equals "infinity" "$SLEEP_OUTPUT" "Should sleep infinity when disabled"
# The disabled block doesn't exit, it just calls sleep.
# We should still test if interval gets set after, since in our bash script execution continues.
assert_equals "1h" "$invalidSeriesAutoCleanerScriptInterval" "Should set default interval if empty even when disabled"

# Test 4: Script disabled, interval set
reset_env
enableInvalidSeriesAutoCleaner="false"
invalidSeriesAutoCleanerScriptInterval="4h"
verifyConfig
assert_equals "infinity" "$SLEEP_OUTPUT" "Should sleep infinity when disabled"
assert_equals "4h" "$invalidSeriesAutoCleanerScriptInterval" "Should keep existing interval when disabled"

if [ $FAILURES -eq 0 ]; then
  echo "All tests passed successfully!"
  exit 0
else
  echo "$FAILURES test(s) failed."
  exit 1
fi
