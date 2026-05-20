#!/bin/bash
set -e

# Setup: extract functions from Queue-Cleaner.bash to avoid the infinite loop
# We'll just extract the verifyConfig function to test it in isolation
sed -n '/^verifyConfig () {/,/^}/p' Queue-Cleaner.bash > /tmp/Queue-Cleaner-functions.bash
source /tmp/Queue-Cleaner-functions.bash

# Mocking log and sleep
log_output=""
log() {
  log_output="$log_output$1\n"
}

sleep_called=false
sleep() {
  sleep_called=true
  if [ "$1" != "infinity" ]; then
    echo "Expected sleep infinity, got sleep $1"
  fi
}

# Keep track of test failures
failed=0

echo "Running tests for verifyConfig..."

# Test 1: enableQueueCleaner is "true"
enableQueueCleaner="true"
log_output=""
sleep_called=false
verifyConfig

if [ "$sleep_called" = true ]; then
  echo "❌ Test 1 Failed: sleep was called when enableQueueCleaner=true"
  failed=1
else
  echo "✅ Test 1 Passed: enableQueueCleaner=true does not sleep"
fi

# Test 2: enableQueueCleaner is not "true" (e.g. "false")
enableQueueCleaner="false"
log_output=""
sleep_called=false
verifyConfig

if [ "$sleep_called" = false ]; then
  echo "❌ Test 2 Failed: sleep was not called when enableQueueCleaner=false"
  failed=1
else
  echo "✅ Test 2 Passed: enableQueueCleaner=false triggers sleep"
  if [[ "$log_output" != *"Script is not enabled"* ]]; then
    echo "❌ Test 2 Failed: Expected log output not found"
    failed=1
  else
    echo "✅ Test 2 Passed: Expected log output found"
  fi
fi

# Test 3: enableQueueCleaner is empty
enableQueueCleaner=""
log_output=""
sleep_called=false
verifyConfig

if [ "$sleep_called" = false ]; then
  echo "❌ Test 3 Failed: sleep was not called when enableQueueCleaner is empty"
  failed=1
else
  echo "✅ Test 3 Passed: enableQueueCleaner is empty triggers sleep"
fi

rm /tmp/Queue-Cleaner-functions.bash
if [ $failed -eq 1 ]; then
    echo "💥 Some tests failed!"
    # Use false instead of exit to fail script without killing session
    false
else
    echo "🎉 All tests passed!"
fi
