#!/usr/bin/env bats
# tests/integration.bats — Integration tests: complete end-to-end scenarios.

load 'test_helper'

setup() {
  TEST_LOGS_DIR="$(mktemp -d)"
  export LOGS_DIR="$TEST_LOGS_DIR"
}

teardown() {
  rm -rf "$TEST_LOGS_DIR"
  unset LOGS_DIR
}

# ---------------------------------------------------------------------------
# Multi-file search (no --file, uses LOGS_DIR)
# ---------------------------------------------------------------------------
@test "without --file, searches all files in LOGS_DIR" {
  copy_fixture "java-format1.log"
  copy_fixture "java-format2.log"
  run bash "$SCRIPT_PATH" --level=error
  [ "$status" -eq 0 ]
  # Should find errors from both files
  [[ "$output" == *"java-format1.log"* ]]
  [[ "$output" == *"java-format2.log"* ]]
}

@test "results from multiple files include correct file names" {
  copy_fixture "java-format1.log"
  copy_fixture "java-format2.log"
  run bash "$SCRIPT_PATH" --level=warn
  [ "$status" -eq 0 ]
  [[ "$output" == *"java-format1.log"* ]]
  [[ "$output" == *"java-format2.log"* ]]
}

# ---------------------------------------------------------------------------
# --file restricts search
# ---------------------------------------------------------------------------
@test "--file restricts search to the specified file only" {
  copy_fixture "java-format1.log"
  copy_fixture "java-format2.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=error
  [ "$status" -eq 0 ]
  [[ "$output" == *"java-format1.log"* ]]
  [[ "$output" != *"java-format2.log"* ]]
}

@test "--file with --find searches only the specified file" {
  copy_fixture "java-format1.log"
  copy_fixture "apache-access.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --find='Cannot persist'
  [ "$status" -eq 0 ]
  [[ "$output" == *"java-format1.log"* ]]
  [[ "$output" != *"apache-access.log"* ]]
}

# ---------------------------------------------------------------------------
# Level + Find combined
# ---------------------------------------------------------------------------
@test "--level=error --find= returns only matching ERROR lines" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error \
    --find='Cannot persist fairs'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"ERROR"* ]]
  [[ "${lines[0]}" == *"Cannot persist fairs"* ]]
}

@test "--level=error --find= with no match returns exit 1" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error \
    --find='info_string_not_in_error_lines'
  [ "$status" -eq 1 ]
}

@test "--level=debug --find=email returns DEBUG line containing email" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=debug \
    --find='test@example.com'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"DEBUG"* ]]
  [[ "${lines[0]}" == *"test@example.com"* ]]
}

@test "--level + --find on Format 2 works correctly" {
  copy_fixture "java-format2.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format2.log" \
    --level=error \
    --find='test@example.com'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"*ERROR*"* ]]
  [[ "${lines[0]}" == *"test@example.com"* ]]
}

# ---------------------------------------------------------------------------
# Find in Apache-style logs (no level)
# ---------------------------------------------------------------------------
@test "--find searches Apache-style log lines" {
  copy_fixture "apache-access.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/apache-access.log" \
    --find='blocked'
  [ "$status" -eq 0 ]
  [[ "$output" == *"blocked"* ]]
}

@test "--find on Apache log returns correct line number" {
  copy_fixture "apache-access.log"
  # 'blocked' appears on line 2
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/apache-access.log" \
    --find='blocked'
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "[file: apache-access.log | line: 2] "* ]]
}

# ---------------------------------------------------------------------------
# Context with --find
# ---------------------------------------------------------------------------
@test "--context=3 after --find shows match plus 2 context lines" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --find='Cannot persist fairs' \
    --context=3
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  # Match line has prefix
  [[ "${lines[0]}" == "[file:"* ]]
  # Context lines have no prefix
  [[ "${lines[1]}" != "[file:"* ]]
  [[ "${lines[2]}" != "[file:"* ]]
}

@test "--level=error --context=2 shows ERROR match plus 1 stacktrace line" {
  copy_fixture "java-format1.log"
  # ERROR on line 1 is followed by stacktrace on line 2
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --find='Cannot persist fairs' \
    --level=error \
    --context=2
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "[file:"* ]]
  [[ "${lines[1]}" == *"PersistenceException"* ]]
}

# ---------------------------------------------------------------------------
# --ignore-case
# ---------------------------------------------------------------------------
@test "--ignore-case finds match with different capitalisation" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --find='CANNOT PERSIST FAIRS' \
    --ignore-case
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cannot persist fairs"* ]]
}

@test "--ignore-case with --level finds case-insensitive match in correct level" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=debug \
    --find='TEST@EXAMPLE.COM' \
    --ignore-case
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"DEBUG"* ]]
}

# ---------------------------------------------------------------------------
# --output writes results to file
# ---------------------------------------------------------------------------
@test "--output writes results to specified file" {
  copy_fixture "java-format1.log"
  local out_file="$TEST_LOGS_DIR/results.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error \
    --output="$out_file"
  [ "$status" -eq 0 ]
  [ -f "$out_file" ]
  [[ "$(cat "$out_file")" == *"ERROR"* ]]
}

@test "--output prints confirmation message to terminal" {
  copy_fixture "java-format1.log"
  local out_file="$TEST_LOGS_DIR/results.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error \
    --output="$out_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Output written to"* ]]
}

@test "--output does not create file when no matches" {
  copy_fixture "java-format1.log"
  local out_file="$TEST_LOGS_DIR/results.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --find='XYZZY_NO_MATCH' \
    --output="$out_file"
  [ "$status" -eq 1 ]
  [ ! -f "$out_file" ]
}

@test "--output file contains same content as terminal output" {
  copy_fixture "java-format1.log"
  local out_file="$TEST_LOGS_DIR/results.log"

  # Get terminal output
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error
  local terminal_out="$output"

  # Get file output
  bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error \
    --output="$out_file"
  local file_out
  file_out="$(cat "$out_file")"

  [ "$terminal_out" = "$file_out" ]
}
