#!/bin/bash

# Define missing variables needed by mocked logs
scriptName="Huntarr"
scriptVersion="2.2"
logFileName="test_log.txt"

# Mock dependencies
log_output=""
exit_called=false
sleep_called=false

# Override log function entirely to prevent writing to /config/logs
log() {
  log_output+="$1 "
}

sleep() {
  sleep_called=true
}

# Override exit to not kill the test script, but just record that it was called
exit() {
  exit_called=true
}

# Source the main file directly, as it now protects execution on being sourced
source Huntarr.bash

# Ensure our mock overrode the one from the script
log() {
  log_output+="$1 "
}

fails=0

test_enableHuntarr_true() {
  enableHuntarr="true"
  exit_called=false
  log_output=""
  sleep_called=false

  verifyConfig "test.conf"

  if [ "$exit_called" = true ]; then
    echo "FAIL: test_enableHuntarr_true: exit should not be called"
    fails=$((fails+1))
  else
    echo "PASS: test_enableHuntarr_true"
  fi
}

test_enableHuntarr_false() {
  enableHuntarr="false"
  huntarrScriptInterval="10"
  exit_called=false
  log_output=""
  sleep_called=false

  verifyConfig "test.conf"

  if [ "$exit_called" = false ]; then
    echo "FAIL: test_enableHuntarr_false: exit should be called"
    fails=$((fails+1))
  elif [ "$sleep_called" = false ]; then
    echo "FAIL: test_enableHuntarr_false: sleep should be called"
    fails=$((fails+1))
  else
    echo "PASS: test_enableHuntarr_false"
  fi
}

test_enableHuntarr_empty() {
  enableHuntarr=""
  huntarrScriptInterval="10"
  exit_called=false
  log_output=""
  sleep_called=false

  verifyConfig "test.conf"

  if [ "$exit_called" = false ]; then
    echo "FAIL: test_enableHuntarr_empty: exit should be called"
    fails=$((fails+1))
  else
    echo "PASS: test_enableHuntarr_empty"
  fi
}

echo "Running tests for verifyConfig..."
test_enableHuntarr_true
test_enableHuntarr_false
test_enableHuntarr_empty

if [ $fails -gt 0 ]; then
  echo "Tests failed: $fails"
  command exit 1
else
  echo "All tests passed!"
  command exit 0
fi
