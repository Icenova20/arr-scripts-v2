#!/bin/bash

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Extract the VerifyApiAccess function from the actual script
sed -n '/VerifyApiAccess () {/,/^}/p' "${SCRIPT_DIR}/../Lidarr-MusicAutomator.bash" > /tmp/func.bash

test_v3_success() {
  echo "Running test_v3_success..."
  timeout 5 bash -c '
    source /tmp/func.bash
    arrApp="Lidarr"; arrUrl="http://localhost:8686"; arrApiKey="12345"
    log() { echo "$1"; }
    sleep() { :; }
    curl() { echo "{\"instanceName\": \"Lidarr-v3\"}"; }
    VerifyApiAccess
  ' > /tmp/out1
  if grep -q "Done" /tmp/out1; then echo "  Passed"; else echo "  Failed"; cat /tmp/out1; return 1; fi
}

test_v1_success() {
  echo "Running test_v1_success..."
  timeout 5 bash -c '
    source /tmp/func.bash
    arrApp="Lidarr"; arrUrl="http://localhost:8686"; arrApiKey="12345"
    log() { echo "$1"; }
    sleep() { :; }
    curl() {
      if [[ "$*" == *"/v3/"* ]]; then
        echo ""
      else
        echo "{\"instanceName\": \"Lidarr-v1\"}"
      fi
    }
    VerifyApiAccess
  ' > /tmp/out2
  if grep -q "Done" /tmp/out2; then echo "  Passed"; else echo "  Failed"; cat /tmp/out2; return 1; fi
}

test_retry_empty() {
  echo "Running test_retry_empty..."
  cat << 'INNER_EOF' > /tmp/test3_inner.bash
source /tmp/func.bash
arrApp="Lidarr"; arrUrl="http://localhost:8686"; arrApiKey="12345"
log() { echo "$1"; }
sleep() { :; }

echo 0 > /tmp/curl_counter
curl() {
  local count=$(cat /tmp/curl_counter)
  count=$((count + 1))
  echo "$count" > /tmp/curl_counter

  if [ "$count" -le 2 ]; then
    echo ""
  else
    echo '{"instanceName": "Lidarr-v3"}'
  fi
}
VerifyApiAccess
INNER_EOF
  timeout 5 bash /tmp/test3_inner.bash > /tmp/out3
  if grep -q "sleeping until valid response" /tmp/out3 && grep -q "Done" /tmp/out3; then
    echo "  Passed"
  else
    echo "  Failed"
    cat /tmp/out3
    return 1
  fi
}

test_retry_null() {
  echo "Running test_retry_null..."
  cat << 'INNER_EOF' > /tmp/test4_inner.bash
source /tmp/func.bash
arrApp="Lidarr"; arrUrl="http://localhost:8686"; arrApiKey="12345"
log() { echo "$1"; }
sleep() { :; }

echo 0 > /tmp/curl_counter
curl() {
  local count=$(cat /tmp/curl_counter)
  count=$((count + 1))
  echo "$count" > /tmp/curl_counter

  if [ "$count" -le 2 ]; then
    echo '{"error": "Unauthorized"}'
  else
    echo '{"instanceName": "Lidarr-v3"}'
  fi
}
VerifyApiAccess
INNER_EOF
  timeout 5 bash /tmp/test4_inner.bash > /tmp/out4
  if grep -q "sleeping until valid response" /tmp/out4 && grep -q "Done" /tmp/out4; then
    echo "  Passed"
  else
    echo "  Failed (likely because of bug - did not sleep)"
    cat /tmp/out4
    return 1
  fi
}

failed=0
test_v3_success || failed=1
test_v1_success || failed=1
test_retry_empty || failed=1
test_retry_null || failed=1

if [ "$failed" -eq 1 ]; then
    echo "Some tests failed!"
    bash -c 'exit 1'
else
    echo "All tests passed!"
fi
