#!/usr/bin/env bats
# tests/unit.bats — Unit tests: one behaviour per test, isolated fixture.

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
# --help
# ---------------------------------------------------------------------------
@test "--help exits 0 and prints usage" {
  run bash "$SCRIPT_PATH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--level"* ]]
  [[ "$output" == *"--find"* ]]
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
@test "unknown parameter exits 2" {
  run bash "$SCRIPT_PATH" --unknown-flag
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown parameter"* ]]
}

@test "--context=0 exits 2" {
  run bash "$SCRIPT_PATH" --context=0
  [ "$status" -eq 2 ]
  [[ "$output" == *"--context"* ]]
}

@test "--context=abc exits 2" {
  run bash "$SCRIPT_PATH" --context=abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--context"* ]]
}

@test "invalid --level exits 2" {
  run bash "$SCRIPT_PATH" --level=critical
  [ "$status" -eq 2 ]
  [[ "$output" == *"Invalid log level"* ]]
}

@test "--level accepts warn (lowercase)" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=warn
  [ "$status" -eq 0 ]
}

@test "--level accepts WARNING (alias)" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=warning
  [ "$status" -eq 0 ]
}

@test "no arguments exits 2 with helpful message" {
  run bash "$SCRIPT_PATH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--level"* ]]
  [[ "$output" == *"--find"* ]]
}

@test "--file alone without --level or --find exits 2" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--level"* ]]
  [[ "$output" == *"--find"* ]]
}

@test "non-existent --file exits 2" {
  run bash "$SCRIPT_PATH" --file="/tmp/does-not-exist.log" --find='x'
  [ "$status" -eq 2 ]
  [[ "$output" == *"File not found"* ]]
}

# ---------------------------------------------------------------------------
# Empty / missing logs directory
# ---------------------------------------------------------------------------
@test "non-existent LOGS_DIR exits 2" {
  export LOGS_DIR="/tmp/no-such-dir-$$"
  run bash "$SCRIPT_PATH" --level=error
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "empty LOGS_DIR exits 1 with message" {
  run bash "$SCRIPT_PATH" --level=error
  [ "$status" -eq 1 ]
  [[ "$output" == *"No log files found"* ]]
}

# ---------------------------------------------------------------------------
# Level filtering — Format 1 (YYYY-MM-DD LEVEL)
# ---------------------------------------------------------------------------
@test "--level=error shows ERROR lines in Format 1" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=error
  [ "$status" -eq 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"INFO"* ]]
  [[ "$output" != *"WARN"* ]]
  [[ "$output" != *"DEBUG"* ]]
}

@test "--level=warn shows WARN lines in Format 1" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=warn
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" != *"ERROR"* ]]
  [[ "$output" != *"INFO"* ]]
}

@test "--level=info shows INFO lines in Format 1" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=info
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO"* ]]
  [[ "$output" != *"ERROR"* ]]
  [[ "$output" != *"WARN"* ]]
}

@test "--level=debug shows DEBUG lines in Format 1" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=debug
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEBUG"* ]]
  [[ "$output" != *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# Level filtering — Format 2 (DD.MM.YYYY *LEVEL*)
# ---------------------------------------------------------------------------
@test "--level=error shows *ERROR* lines in Format 2" {
  copy_fixture "java-format2.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format2.log" --level=error
  [ "$status" -eq 0 ]
  [[ "$output" == *"*ERROR*"* ]]
  [[ "$output" != *"*INFO*"* ]]
  [[ "$output" != *"*WARN*"* ]]
}

@test "--level=warn shows *WARN* lines in Format 2" {
  copy_fixture "java-format2.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format2.log" --level=warn
  [ "$status" -eq 0 ]
  [[ "$output" == *"*WARN*"* ]]
  [[ "$output" != *"*ERROR*"* ]]
}

@test "--level=debug shows *DEBUG* lines in Format 2" {
  copy_fixture "java-format2.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format2.log" --level=debug
  [ "$status" -eq 0 ]
  [[ "$output" == *"*DEBUG*"* ]]
  [[ "$output" != *"*ERROR*"* ]]
}

# ---------------------------------------------------------------------------
# Find filter
# ---------------------------------------------------------------------------
@test "--find matches a string in a log line" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --find='Cannot persist fairs'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cannot persist fairs"* ]]
}

@test "--find matches inside stacktrace continuation lines" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --find='NullPointerException'
  [ "$status" -eq 0 ]
  [[ "$output" == *"NullPointerException"* ]]
}

@test "--find is case-sensitive by default" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --find='NULLPOINTEREXCEPTION'
  [ "$status" -eq 1 ]
}

@test "--ignore-case makes find case-insensitive" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --find='NULLPOINTEREXCEPTION' --ignore-case
  [ "$status" -eq 0 ]
  [[ "$output" == *"NullPointerException"* ]]
}

# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------
@test "default --context=1 shows only the matching line" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --find='Cannot persist fairs'
  [ "$status" -eq 0 ]
  # Only one match line, no extra context
  [ "${#lines[@]}" -eq 1 ]
}

@test "--context=3 shows match line plus 2 additional lines" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --find='Cannot persist fairs' --context=3
  [ "$status" -eq 0 ]
  # 1 match + 2 context = 3 lines
  [ "${#lines[@]}" -eq 3 ]
}

@test "context lines are printed without the [file | line] prefix" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --find='Cannot persist fairs' --context=2
  [ "$status" -eq 0 ]
  # First line has prefix
  [[ "${lines[0]}" == "[file:"* ]]
  # Second line (context) has no prefix
  [[ "${lines[1]}" != "[file:"* ]]
}

# ---------------------------------------------------------------------------
# Output format
# ---------------------------------------------------------------------------
@test "output format is [file: NAME | line: N] content" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=error
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "[file: java-format1.log | line: 1] "* ]]
}

@test "line number in output matches actual file position" {
  copy_fixture "java-format1.log"
  # WARN is on line 7 of java-format1.log
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=warn
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "[file: java-format1.log | line: 7] "* ]]
}

# ---------------------------------------------------------------------------
# Exit codes
# ---------------------------------------------------------------------------
@test "exit code 0 when matches are found" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --level=error
  [ "$status" -eq 0 ]
}

@test "exit code 1 when no matches are found" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" --file="$TEST_LOGS_DIR/java-format1.log" --find='XYZZY_NO_MATCH_$$'
  [ "$status" -eq 1 ]
}

@test "exit code 2 on argument error" {
  run bash "$SCRIPT_PATH" --level=bad_level
  [ "$status" -eq 2 ]
}
