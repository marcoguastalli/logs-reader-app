#!/usr/bin/env bash
# tests/test_helper.bash — Shared helpers loaded by every .bats file.
#
# Usage in a .bats file:
#   load 'test_helper'
#
# Provides:
#   SCRIPT_PATH   — absolute path to read-logs.sh
#   FIXTURES_DIR  — absolute path to tests/fixtures/
#   copy_fixture  — copies a fixture into the active TEST_LOGS_DIR

# Resolve paths relative to the .bats file that loaded this helper.
SCRIPT_PATH="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/read-logs.sh"
FIXTURES_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/fixtures"

# Copy a named fixture file into TEST_LOGS_DIR.
# Must be called after TEST_LOGS_DIR is created (inside setup()).
copy_fixture() {
  local name="$1"
  cp "$FIXTURES_DIR/$name" "$TEST_LOGS_DIR/$name"
}
