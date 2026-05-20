#!/usr/bin/env bash

# Source the script functions without the main loop
source <(sed '/# Loop Script/,$d' Sonarr-UnmappedFolderCleaner.bash)

# Mock log and sleep functions AFTER sourcing to override them
log() {
  echo "LOG: $1"
}

sleep() {
  echo "SLEEP: $1"
}

EXIT_CODE=0

# Test 1: enableUnmappedFolderCleaner="true"
enableUnmappedFolderCleaner="true"
OUTPUT=$(verifyConfig 2>&1)
if [ -z "$OUTPUT" ]; then
    echo "Test 1 Passed: verifyConfig did nothing when enableUnmappedFolderCleaner is true"
else
    echo "Test 1 Failed: Expected no output, got $OUTPUT"
    EXIT_CODE=1
fi

# Test 2: enableUnmappedFolderCleaner is empty
enableUnmappedFolderCleaner=""
OUTPUT=$(verifyConfig 2>&1)
if echo "$OUTPUT" | grep -q 'LOG: Script is not enabled' && \
   echo "$OUTPUT" | grep -q 'LOG: Sleeping (infinity)' && \
   echo "$OUTPUT" | grep -q 'SLEEP: infinity'; then
    echo "Test 2 Passed: verifyConfig logs and sleeps when enableUnmappedFolderCleaner is not true"
else
    echo "Test 2 Failed: Output was: $OUTPUT"
    EXIT_CODE=1
fi

# Test 3: enableUnmappedFolderCleaner="false"
enableUnmappedFolderCleaner="false"
OUTPUT=$(verifyConfig 2>&1)
if echo "$OUTPUT" | grep -q 'LOG: Script is not enabled' && \
   echo "$OUTPUT" | grep -q 'LOG: Sleeping (infinity)' && \
   echo "$OUTPUT" | grep -q 'SLEEP: infinity'; then
    echo "Test 3 Passed: verifyConfig logs and sleeps when enableUnmappedFolderCleaner is false"
else
    echo "Test 3 Failed: Output was: $OUTPUT"
    EXIT_CODE=1
fi

if [ $EXIT_CODE -eq 0 ]; then
  echo "All tests completed successfully!"
else
  echo "Some tests failed!"
fi

exit $EXIT_CODE
