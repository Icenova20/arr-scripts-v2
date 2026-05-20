#!/usr/bin/env bash

set -e

# Extract verifyConfig function from the main script
eval "$(sed -n '/^verifyConfig () {/,/^}/p' Sonarr-DailySeriesEpisodeTrimmer.bash)"

# Mock variables and functions
scriptName="Sonarr-DailySeriesEpisodeTrimmer"
scriptVersion="1.3"

# Mock log function to capture output
log_output=""
log() {
  log_output+="$1"$'\n'
}

# Mock sleep function to capture calls
sleep_called_with=""
sleep() {
  sleep_called_with="$1"
}

# Test 1: enableDailySeriesEpisodeTrimmer="true"
echo "Running Test 1: enableDailySeriesEpisodeTrimmer is true"
enableDailySeriesEpisodeTrimmer="true"
log_output=""
sleep_called_with=""

verifyConfig

if [ -n "$log_output" ]; then
    echo "Test 1 Failed: Expected no log output, got:"
    echo "$log_output"
    exit 1
fi

if [ -n "$sleep_called_with" ]; then
    echo "Test 1 Failed: Expected no sleep call, got sleep $sleep_called_with"
    exit 1
fi
echo "Test 1 Passed"


# Test 2: enableDailySeriesEpisodeTrimmer="false"
echo "Running Test 2: enableDailySeriesEpisodeTrimmer is false"
enableDailySeriesEpisodeTrimmer="false"
log_output=""
sleep_called_with=""

verifyConfig

expected_log1="Script is not enabled, enable by setting enableDailySeriesEpisodeTrimmer to \"true\" by modifying the \"/config/settings.conf\" config file..."
expected_log2="Sleeping (infinity)"

if [[ "$log_output" != *"$expected_log1"* ]]; then
    echo "Test 2 Failed: Did not find expected log 1"
    echo "Actual output:"
    echo "$log_output"
    exit 1
fi

if [[ "$log_output" != *"$expected_log2"* ]]; then
    echo "Test 2 Failed: Did not find expected log 2"
    echo "Actual output:"
    echo "$log_output"
    exit 1
fi

if [ "$sleep_called_with" != "infinity" ]; then
    echo "Test 2 Failed: Expected sleep infinity, got sleep $sleep_called_with"
    exit 1
fi
echo "Test 2 Passed"

# Test 3: enableDailySeriesEpisodeTrimmer="" (empty)
echo "Running Test 3: enableDailySeriesEpisodeTrimmer is empty"
enableDailySeriesEpisodeTrimmer=""
log_output=""
sleep_called_with=""

verifyConfig

if [[ "$log_output" != *"$expected_log1"* ]]; then
    echo "Test 3 Failed: Did not find expected log 1"
    echo "Actual output:"
    echo "$log_output"
    exit 1
fi

if [[ "$log_output" != *"$expected_log2"* ]]; then
    echo "Test 3 Failed: Did not find expected log 2"
    echo "Actual output:"
    echo "$log_output"
    exit 1
fi

if [ "$sleep_called_with" != "infinity" ]; then
    echo "Test 3 Failed: Expected sleep infinity, got sleep $sleep_called_with"
    exit 1
fi
echo "Test 3 Passed"

echo "All tests passed successfully!"
