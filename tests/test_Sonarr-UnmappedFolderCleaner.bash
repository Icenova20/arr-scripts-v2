#!/usr/bin/env bash
set -e

# Safely extract functions by removing the top-level loop.
TMP_SCRIPT_FILE=$(mktemp)
# The loop starts with "for (( ; ; )); do" or "# Loop Script"
sed '/^# Loop Script/,$d' Sonarr-UnmappedFolderCleaner.bash > "$TMP_SCRIPT_FILE"
source "$TMP_SCRIPT_FILE"

# Global variables
arrUrl="http://fakeurl"
arrApiKey="fakekey"
log_output=""
curl_output=""
rm_called_with=""

# Mock `log`
log() {
  log_output="$log_output$1"$'\n'
}
export -f log

# Mock `curl`
curl() {
  echo "$curl_output"
}
export -f curl

# Mock `rm` - prevent real file deletion and record calls
rm() {
  rm_called_with="$rm_called_with$@"$'\n'
}
export -f rm

failed=0
echo "Running tests for UnmappedFolderCleanerProcess..."

# Test 1: No cleanup required (0 folders)
log_output=""
curl_output='[]'
rm_called_with=""
UnmappedFolderCleanerProcess

if [[ "$log_output" != *"No cleanup required, exiting..."* ]]; then
  echo "❌ Test 1 Failed: Expected 'No cleanup required, exiting...' in log."
  failed=1
else
  echo "✅ Test 1 Passed: No cleanup required."
fi

# Test 2: Successful cleanup (1 unmapped folder)
log_output=""
rm_called_with=""
test_root=$(mktemp -d)
test_folder="$test_root/unmapped_folder"
mkdir -p "$test_folder"
# We need to construct JSON that jq expects
curl_output="[{\"path\": \"$test_root\", \"unmappedFolders\": [{\"path\": \"$test_folder\"}]}]"

UnmappedFolderCleanerProcess

if [[ "$rm_called_with" != *"-rf $test_folder"* ]]; then
  echo "❌ Test 2 Failed: rm was not called with the correct folder."
  echo "rm was called with: $rm_called_with"
  failed=1
elif [[ "$log_output" != *"Removing $test_folder"* ]]; then
  echo "❌ Test 2 Failed: Did not log removal of directory."
  failed=1
else
  echo "✅ Test 2 Passed: Directory successfully marked for deletion."
fi
# Clean up temp dirs safely with the real rm
command rm -rf "$test_root"

# Test 3: Missing directory
log_output=""
rm_called_with=""
test_root=$(mktemp -d)
test_folder="$test_root/missing_folder"
curl_output="[{\"path\": \"$test_root\", \"unmappedFolders\": [{\"path\": \"$test_folder\"}]}]"

UnmappedFolderCleanerProcess

if [[ "$log_output" != *"Cannot Delete \"$test_folder\", directory not found"* ]]; then
  echo "❌ Test 3 Failed: Did not log missing directory error."
  echo -e "Logs were: $log_output"
  failed=1
elif [[ -n "$rm_called_with" ]]; then
  echo "❌ Test 3 Failed: rm was called when it should not have been."
  failed=1
else
  echo "✅ Test 3 Passed: Missing directory handled correctly."
fi
command rm -rf "$test_root"

# Test 4: Security constraint - directory traversal/invalid subdirectory
log_output=""
rm_called_with=""
test_root=$(mktemp -d)
test_folder=$(mktemp -d) # Outside the root
curl_output="[{\"path\": \"$test_root\", \"unmappedFolders\": [{\"path\": \"$test_folder\"}]}]"

UnmappedFolderCleanerProcess

if [[ -n "$rm_called_with" ]]; then
  echo "❌ Test 4 Failed: Malicious directory was marked for deletion."
  failed=1
elif [[ "$log_output" != *"SECURITY WARNING: \"$test_folder\" is not a valid sub-directory of \"$test_root\""* ]]; then
  echo "❌ Test 4 Failed: Did not log security warning."
  failed=1
else
  echo "✅ Test 4 Passed: Security constraint prevented deletion."
fi
command rm -rf "$test_root"
command rm -rf "$test_folder"

command rm "$TMP_SCRIPT_FILE"

if [ $failed -eq 1 ]; then
    echo "💥 Some tests failed!"
    false
else
    echo "🎉 All tests passed!"
fi
