#!/usr/bin/env bash

# Determine the directory of the script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_PATH="$DIR/../Lidarr-MusicVideoAutomator.bash"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "❌ FAIL: Script not found at $SCRIPT_PATH"
    exit 1
fi

# Mock log and sleep to capture output
log_output=""
log() {
    log_output+="$1"$'\n'
}

sleep_output=""
sleep() {
    sleep_output+="$1"$'\n'
}

# Extract verifyConfig function from the script to avoid running the whole script
# This gets the lines starting from `verifyConfig () {` until the first `}`
source <(sed -n '/^verifyConfig () {/,/^}/p' "$SCRIPT_PATH")

test_failed=0
export lidarrMusicVideoTempDownloadPath="/downloads/temp"
export tidalToken="mock_token"

echo "Running tests for verifyConfig..."

# Test 1: lidarrMusicVideoAutomator is true
export lidarrMusicVideoAutomator="true"
log_output=""
sleep_output=""
verifyConfig
if [ -n "$log_output" ] || [ -n "$sleep_output" ]; then
    echo "❌ FAIL: verifyConfig outputted something when true"
    echo "Log output: $log_output"
    echo "Sleep output: $sleep_output"
    test_failed=1
else
    echo "✅ PASS: verifyConfig with lidarrMusicVideoAutomator=true"
fi

# Test 2: lidarrMusicVideoAutomator is false
export lidarrMusicVideoAutomator="false"
log_output=""
sleep_output=""
verifyConfig
if [[ "$log_output" == *"Script is not enabled"* ]] && [[ "$sleep_output" == *"infinity"* ]]; then
    echo "✅ PASS: verifyConfig with lidarrMusicVideoAutomator=false"
else
    echo "❌ FAIL: verifyConfig did not output expected messages when false"
    echo "Log output: $log_output"
    echo "Sleep output: $sleep_output"
    test_failed=1
fi

# Test 3: lidarrMusicVideoAutomator is empty
export lidarrMusicVideoAutomator=""
log_output=""
sleep_output=""
verifyConfig
if [[ "$log_output" == *"Script is not enabled"* ]] && [[ "$sleep_output" == *"infinity"* ]]; then
    echo "✅ PASS: verifyConfig with lidarrMusicVideoAutomator=\"\""
else
    echo "❌ FAIL: verifyConfig did not output expected messages when empty"
    echo "Log output: $log_output"
    echo "Sleep output: $sleep_output"
    test_failed=1
fi

if [ $test_failed -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
