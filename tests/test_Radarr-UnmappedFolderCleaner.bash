#!/usr/bin/env bash
set -e

# Extract the function safely
TMP_FUNC_FILE=$(mktemp)
sed -n '/^UnmappedFolderCleanerProcess () {/,/^ *}/p' Radarr-UnmappedFolderCleaner.bash > "$TMP_FUNC_FILE"
source "$TMP_FUNC_FILE"

# Global variables
arrUrl="http://fakeurl"
arrApiKey="fakekey"
log_output=""
curl_output=""

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

failed=0
echo "Running tests for UnmappedFolderCleanerProcess..."

# Test 1: No cleanup required (0 folders)
log_output=""
curl_output='[]'
UnmappedFolderCleanerProcess

if [[ "$log_output" != *"No cleanup required, exiting..."* ]]; then
  echo "❌ Test 1 Failed: Expected 'No cleanup required, exiting...' in log."
  failed=1
else
  echo "✅ Test 1 Passed: No cleanup required."
fi

# Test 2: Successful cleanup (1 unmapped folder)
log_output=""
test_root=$(mktemp -d)
test_folder="$test_root/unmapped_folder"
mkdir -p "$test_folder"
# We need to construct JSON that jq expects
curl_output="[{\"path\": \"$test_root\", \"unmappedFolders\": [{\"path\": \"$test_folder\"}]}]"

UnmappedFolderCleanerProcess

if [ -d "$test_folder" ]; then
  echo "❌ Test 2 Failed: Directory was not deleted."
  failed=1
elif [[ "$log_output" != *"Removing $test_folder"* ]]; then
  echo "❌ Test 2 Failed: Did not log removal of directory."
  failed=1
else
  echo "✅ Test 2 Passed: Directory successfully deleted."
fi
rm -rf "$test_root"

# Test 3: Missing directory
log_output=""
test_root=$(mktemp -d)
test_folder="$test_root/missing_folder"
curl_output="[{\"path\": \"$test_root\", \"unmappedFolders\": [{\"path\": \"$test_folder\"}]}]"

UnmappedFolderCleanerProcess

if [[ "$log_output" != *"Cannot Delete \"$test_folder\", directory not found"* ]]; then
  echo "❌ Test 3 Failed: Did not log missing directory error."
  echo -e "Logs were: $log_output"
  failed=1
else
  echo "✅ Test 3 Passed: Missing directory handled correctly."
fi
rm -rf "$test_root"

# Test 4: Security constraint - directory traversal/invalid subdirectory
log_output=""
test_root=$(mktemp -d)
test_folder=$(mktemp -d) # Outside the root
curl_output="[{\"path\": \"$test_root\", \"unmappedFolders\": [{\"path\": \"$test_folder\"}]}]"

UnmappedFolderCleanerProcess

if [ ! -d "$test_folder" ]; then
  echo "❌ Test 4 Failed: Malicious directory was deleted."
  failed=1
elif [[ "$log_output" != *"SECURITY WARNING: \"$test_folder\" is not a valid sub-directory of \"$test_root\""* ]]; then
  echo "❌ Test 4 Failed: Did not log security warning."
  failed=1
else
  echo "✅ Test 4 Passed: Security constraint prevented deletion."
fi
rm -rf "$test_root"
rm -rf "$test_folder"

rm "$TMP_FUNC_FILE"

if [ $failed -eq 1 ]; then
    echo "💥 Some tests failed!"
    false
else
    echo "🎉 All tests passed!"
fi
