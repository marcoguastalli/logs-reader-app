#!/usr/bin/env bats
# tests/regression.bats — Regression tests: edge cases and boundary conditions.

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
# Level filter does NOT apply to lines without a detectable level
# ---------------------------------------------------------------------------
@test "--level filter does not match Apache-style log lines" {
  copy_fixture "apache-access.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/apache-access.log" \
    --level=error
  [ "$status" -eq 1 ]
  [[ "$output" == *"No matches found"* ]]
}

@test "--level filter does not match stacktrace continuation lines" {
  copy_fixture "java-format1.log"
  # Only lines that are actual log entries with ERROR should appear;
  # stacktrace lines (starting with tab) must NOT get their own match.
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error
  [ "$status" -eq 0 ]
  for line in "${lines[@]}"; do
    # Every output line must start with the [file:] prefix (match line)
    # because default context=1 produces no context lines.
    [[ "$line" == "[file:"* ]]
  done
}

# ---------------------------------------------------------------------------
# --find works on non-level lines
# ---------------------------------------------------------------------------
@test "--find finds string in Apache-style log" {
  copy_fixture "apache-access.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/apache-access.log" \
    --find='unauthorized'
  [ "$status" -eq 0 ]
  [[ "$output" == *"unauthorized"* ]]
}

@test "--find finds string in stacktrace continuation line" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --find='java.lang.NullPointerException'
  [ "$status" -eq 0 ]
  [[ "$output" == *"NullPointerException"* ]]
}

@test "--find finds string in Format 2 stacktrace line" {
  copy_fixture "java-format2.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format2.log" \
    --find='IllegalArgumentException'
  [ "$status" -eq 0 ]
  [[ "$output" == *"IllegalArgumentException"* ]]
}

# ---------------------------------------------------------------------------
# Level specificity — WARN does not match ERROR, INFO, DEBUG
# ---------------------------------------------------------------------------
@test "--level=warn does not return ERROR lines" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=warn
  [ "$status" -eq 0 ]
  [[ "$output" != *"ERROR"* ]]
}

@test "--level=error does not return WARN lines" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error
  [ "$status" -eq 0 ]
  [[ "$output" != *" WARN "* ]]
}

@test "--level=info does not return DEBUG or ERROR lines" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=info
  [ "$status" -eq 0 ]
  [[ "$output" != *"ERROR"* ]]
  [[ "$output" != *"DEBUG"* ]]
}

# ---------------------------------------------------------------------------
# Case sensitivity
# ---------------------------------------------------------------------------
@test "find is case-sensitive by default — mismatched case returns exit 1" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --find='cannot persist fairs'
  [ "$status" -eq 1 ]
}

@test "--ignore-case finds the exact same content regardless of query case" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --find='cannot persist fairs' \
    --ignore-case
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cannot persist fairs"* ]]
}

# ---------------------------------------------------------------------------
# Context line formatting
# ---------------------------------------------------------------------------
@test "context lines have no [file | line] prefix" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error \
    --context=2
  [ "$status" -eq 0 ]
  # Collect context lines (lines without [file: prefix)
  context_lines=0
  for line in "${lines[@]}"; do
    if [[ "$line" != "[file:"* ]]; then
      context_lines=$((context_lines + 1))
    fi
  done
  # There must be at least one context line (ERROR at line 1 has stacktrace)
  [ "$context_lines" -gt 0 ]
}

@test "second match resets context counter and gets its own prefix" {
  copy_fixture "java-format1.log"
  # --find matches line 2 (stacktrace) and line 10 (NullPointerException)
  # --context=2 means match + 1 more line
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --find='at com.example' \
    --context=2
  [ "$status" -eq 0 ]
  # Every match starts with [file: prefix
  match_count=0
  for line in "${lines[@]}"; do
    [[ "$line" == "[file:"* ]] && match_count=$((match_count + 1))
  done
  [ "$match_count" -gt 1 ]
}

# ---------------------------------------------------------------------------
# Multiple matches in the same file
# ---------------------------------------------------------------------------
@test "multiple ERROR lines all appear in output" {
  copy_fixture "java-format1.log"
  # java-format1.log has ERROR on lines 1, 4, 8
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "correct line numbers are reported for multiple matches" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "[file: java-format1.log | line: 1] "* ]]
  [[ "${lines[1]}" == "[file: java-format1.log | line: 4] "* ]]
  [[ "${lines[2]}" == "[file: java-format1.log | line: 8] "* ]]
}

# ---------------------------------------------------------------------------
# No matches
# ---------------------------------------------------------------------------
@test "no matches prints 'No matches found' message" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --find='XYZZY_THIS_DOES_NOT_EXIST'
  [ "$status" -eq 1 ]
  [[ "$output" == *"No matches found"* ]]
}

@test "no matches with --level and --find returns exit 1" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error \
    --find='XYZZY_NOT_IN_ERRORS'
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Both log formats in the same LOGS_DIR
# ---------------------------------------------------------------------------
@test "mixed LOGS_DIR returns matches from both file formats" {
  copy_fixture "java-format1.log"
  copy_fixture "java-format2.log"
  run bash "$SCRIPT_PATH" --level=info
  [ "$status" -eq 0 ]
  [[ "$output" == *"java-format1.log"* ]]
  [[ "$output" == *"java-format2.log"* ]]
}

@test "--find across mixed formats finds matches in all files" {
  copy_fixture "java-format1.log"
  copy_fixture "java-format2.log"
  # 'test@example.com' appears in both fixture files
  run bash "$SCRIPT_PATH" --find='test@example.com'
  [ "$status" -eq 0 ]
  [[ "$output" == *"java-format1.log"* ]]
  [[ "$output" == *"java-format2.log"* ]]
}

# ---------------------------------------------------------------------------
# --context=1 (default) never shows extra lines
# ---------------------------------------------------------------------------
@test "--context=1 never outputs lines beyond the match" {
  copy_fixture "java-format1.log"
  run bash "$SCRIPT_PATH" \
    --file="$TEST_LOGS_DIR/java-format1.log" \
    --level=error \
    --context=1
  [ "$status" -eq 0 ]
  # All output lines must have the prefix (no unlabelled context lines)
  for line in "${lines[@]}"; do
    [[ "$line" == "[file:"* ]]
  done
}
