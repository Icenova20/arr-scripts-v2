#!/bin/bash

# Source the script, avoiding the infinite loop at the end
source <(awk '/^for \(\( ; ; \)\)/ {exit} {print}' Radarr-Invalid-Movie-Auto-Cleaner.bash)

# Mock variables and functions
LOG_OUTPUT=""
SLEEP_CALLED=false

log() {
  LOG_OUTPUT+="$1\n"
}

sleep() {
  SLEEP_CALLED=true
  if [ "$1" != "infinity" ]; then
    echo "Error: sleep called with $1 instead of infinity"
    exit 1
  fi
}

# Test 1: enableInvalidMoviesAutoCleaner is true
run_test_enabled() {
  echo "Running test: enableInvalidMoviesAutoCleaner=true"
  LOG_OUTPUT=""
  SLEEP_CALLED=false

  enableInvalidMoviesAutoCleaner="true"
  verifyConfig

  if [ "$SLEEP_CALLED" = true ]; then
    echo "FAIL: sleep was called unexpectedly when script is enabled."
    return 1
  fi

  if [ -n "$LOG_OUTPUT" ]; then
    echo "FAIL: log output was generated unexpectedly when script is enabled."
    return 1
  fi

  echo "PASS: test_enabled"
  return 0
}

# Test 2: enableInvalidMoviesAutoCleaner is false
run_test_disabled() {
  echo "Running test: enableInvalidMoviesAutoCleaner=false"
  LOG_OUTPUT=""
  SLEEP_CALLED=false

  enableInvalidMoviesAutoCleaner="false"
  verifyConfig

  if [ "$SLEEP_CALLED" = false ]; then
    echo "FAIL: sleep was not called when script is disabled."
    return 1
  fi

  if ! echo "$LOG_OUTPUT" | grep -q "Script is not enabled"; then
    echo "FAIL: log output did not contain 'Script is not enabled'."
    return 1
  fi

  if ! echo "$LOG_OUTPUT" | grep -q "Sleeping (infinity)"; then
    echo "FAIL: log output did not contain 'Sleeping (infinity)'."
    return 1
  fi

  echo "PASS: test_disabled"
  return 0
}

# Test 3: enableInvalidMoviesAutoCleaner is unset
run_test_unset() {
  echo "Running test: enableInvalidMoviesAutoCleaner is unset"
  LOG_OUTPUT=""
  SLEEP_CALLED=false

  unset enableInvalidMoviesAutoCleaner
  verifyConfig

  if [ "$SLEEP_CALLED" = false ]; then
    echo "FAIL: sleep was not called when script is disabled."
    return 1
  fi

  echo "PASS: test_unset"
  return 0
}

# Run tests
fails=0

run_test_enabled || fails=$((fails+1))
run_test_disabled || fails=$((fails+1))
run_test_unset || fails=$((fails+1))

if [ $fails -eq 0 ]; then
  echo "All tests passed successfully!"
  exit 0
else
  echo "$fails tests failed."
  exit 1
fi
