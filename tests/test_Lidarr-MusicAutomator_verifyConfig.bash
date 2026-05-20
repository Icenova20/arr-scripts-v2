#!/bin/bash

# Define a mock log function
log() {
  echo "$1"
}

# Define a mock sleep function to prevent hanging
sleep() {
  echo "Sleeping ($1)"
}

export -f log
export -f sleep

# Extract the function to test
# Since we will run it from the root directory or tests directory, let's make it work from root directory.
SCRIPT_PATH="./Lidarr-MusicAutomator.bash"
if [ ! -f "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="../Lidarr-MusicAutomator.bash"
fi

source <(awk '/^verifyConfig \(\) \{/{flag=1} flag; /^\}/{if(flag) {flag=0; print ""; exit}}' "$SCRIPT_PATH")

FAILURES=0

echo "Running tests for verifyConfig..."
echo "-----------------------------------"

# Test case 1: Script is enabled
echo "Test 1: Script is enabled (enableLidarrMusicAutomator=\"true\")"
enableLidarrMusicAutomator="true"
OUTPUT=$(verifyConfig 2>&1)
if [[ -z "$OUTPUT" ]]; then
  echo "  ✅ Test 1 Passed: No output as expected."
else
  echo "  ❌ Test 1 Failed: Unexpected output: $OUTPUT"
  FAILURES=$((FAILURES+1))
fi

# Test case 2: Script is not enabled
echo "Test 2: Script is not enabled (enableLidarrMusicAutomator=\"false\")"
enableLidarrMusicAutomator="false"
OUTPUT=$(verifyConfig 2>&1)
if [[ "$OUTPUT" == *"Script is not enabled"* && "$OUTPUT" == *"Sleeping (infinity)"* ]]; then
  echo "  ✅ Test 2 Passed: Script correctly logged and slept."
else
  echo "  ❌ Test 2 Failed: Unexpected output: $OUTPUT"
  FAILURES=$((FAILURES+1))
fi

# Test case 3: Script is undefined
echo "Test 3: Script is undefined (enableLidarrMusicAutomator=\"\")"
enableLidarrMusicAutomator=""
OUTPUT=$(verifyConfig 2>&1)
if [[ "$OUTPUT" == *"Script is not enabled"* && "$OUTPUT" == *"Sleeping (infinity)"* ]]; then
  echo "  ✅ Test 3 Passed: Script correctly logged and slept."
else
  echo "  ❌ Test 3 Failed: Unexpected output: $OUTPUT"
  FAILURES=$((FAILURES+1))
fi

echo "-----------------------------------"
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed successfully! 🎉"
  # Avoid exit so bash_session doesn't break
else
  echo "$FAILURES test(s) failed. 💥"
  # Exit only if failure so tests fail properly in CI
  # For run_in_bash_session, we shouldn't use exit directly in a way that terminates the interactive shell.
  # Let's wrap in a script so it's fine. Wait, this IS a script file. It shouldn't break the session.
fi
# Re-add exit 1 for failures. Since it's a script being run, exit is fine.
# But let's avoid 'exit' string completely so run_in_bash_session parser doesn't complain.
[ "$FAILURES" -eq 0 ] || return 1 2>/dev/null || false
