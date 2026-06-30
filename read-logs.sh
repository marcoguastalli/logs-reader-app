#!/usr/bin/env bash
# read-logs.sh — Log file reader with level and pattern filtering.
#
# Supports two AEM log formats:
#   Format 1: YYYY-MM-DD HH:MM:SS.mmm LEVEL [class] message
#   Format 2: DD.MM.YYYY HH:MM:SS.mmm *LEVEL* [thread] class message
#
# Exit codes: 0=results found, 1=no matches, 2=error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="${LOGS_DIR:-$SCRIPT_DIR/logs}"

# Defaults
LEVEL=""
FIND_STR=""
TARGET_FILE=""
CONTEXT=1
IGNORE_CASE=false
OUTPUT_FILE=""

# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: read-logs.sh [OPTIONS]

Read and filter log files from the logs/ directory.

OPTIONS:
  --level=LEVEL       Filter by log level: trace, debug, info, warn, error
                      (warning is accepted as an alias for warn)
  --find=STRING       Search for a specific string
  --file=FILE         Restrict search to a specific file
  --context=N         Show N lines from match (default: 1, match line only)
  --ignore-case       Case-insensitive search (default: case-sensitive)
  --output=FILE       Write results to FILE instead of terminal
  --help              Show this help message

SUPPORTED LOG FORMATS:
  Format 1  YYYY-MM-DD HH:MM:SS.mmm LEVEL [class] message
  Format 2  DD.MM.YYYY HH:MM:SS.mmm *LEVEL* [thread] class message

NOTES:
  - Level filtering applies only to log entries with a detectable level.
  - Lines without a level (stacktrace continuations, Apache-style logs) are
    not affected by --level; they are searchable via --find only.
  - Context lines beyond the matching line are printed without the
    [file | line] prefix.

EXIT CODES:
  0  Results found
  1  No matches
  2  Error (bad arguments, file/directory not found, etc.)

EXAMPLES:
  ./read-logs.sh --level=error
  ./read-logs.sh --find='NullPointerException'
  ./read-logs.sh --level=error --find='Unable to create node' --context=20
  ./read-logs.sh --file=logs/app.log --level=warn --find='timeout'
  ./read-logs.sh --level=error --ignore-case --output=errors.log
  ./read-logs.sh --level=debug --find='user@example.com' --ignore-case
EOF
}

die() {
  echo "ERROR: $1" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --level=*)     LEVEL="${arg#*=}" ;;
    --find=*)      FIND_STR="${arg#*=}" ;;
    --file=*)      TARGET_FILE="${arg#*=}" ;;
    --context=*)   CONTEXT="${arg#*=}" ;;
    --ignore-case) IGNORE_CASE=true ;;
    --output=*)    OUTPUT_FILE="${arg#*=}" ;;
    --help)        usage; exit 0 ;;
    *)             die "Unknown parameter: '$arg'. Run with --help for usage." ;;
  esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if ! [[ "$CONTEXT" =~ ^[1-9][0-9]*$ ]]; then
  die "--context must be a positive integer (got: '$CONTEXT')"
fi

if [ -z "$LEVEL" ] && [ -z "$FIND_STR" ]; then
  die "At least one of --level or --find is required. Use --help for usage."
fi

if [ -n "$LEVEL" ]; then
  case "$(printf '%s' "$LEVEL" | tr '[:upper:]' '[:lower:]')" in
    trace|debug|info|warn|warning|error)
      LEVEL="$(printf '%s' "$LEVEL" | tr '[:lower:]' '[:upper:]')"
      [ "$LEVEL" = "WARNING" ] && LEVEL="WARN"
      ;;
    *)
      die "Invalid log level: '$LEVEL'. Accepted: trace, debug, info, warn, error"
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Resolve files
# ---------------------------------------------------------------------------
declare -a FILES=()

if [ -n "$TARGET_FILE" ]; then
  [ -f "$TARGET_FILE" ] || die "File not found: '$TARGET_FILE'"
  FILES=("$TARGET_FILE")
else
  [ -d "$LOGS_DIR" ] || die "Logs directory not found: '$LOGS_DIR'"

  while IFS= read -r f; do
    [ -n "$f" ] && FILES+=("$f")
  done < <(find "$LOGS_DIR" -maxdepth 1 -type f | LC_ALL=C sort)

  if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No log files found in '$LOGS_DIR'"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# AWK search engine — single streaming pass per file (O(n) time, O(1) memory)
#
# Passed variables:
#   fname        — display name shown in output prefix
#   filter_level — normalised uppercase level (e.g. "ERROR") or ""
#   filter_find  — search string or ""
#   ctx_lines    — total lines per match including the match line (default 1)
#   icase        — "true" for case-insensitive matching
# ---------------------------------------------------------------------------
AWK_SCRIPT='
BEGIN { remaining = 0; found = 0 }
{
  line = $0

  # ── Level detection ────────────────────────────────────────────────────
  is_log_entry = 0
  this_level   = ""

  # Format 1: YYYY-MM-DD HH:MM:SS.mmm LEVEL [class] ...
  if (line ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9]* [A-Z]/) {
    tmp = line
    sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9]* /, "", tmp)
    sp = index(tmp, " ")
    this_level   = toupper((sp > 1) ? substr(tmp, 1, sp - 1) : tmp)
    is_log_entry = 1
  }
  # Format 2: DD.MM.YYYY HH:MM:SS.mmm *LEVEL* [thread] ...
  else if (line ~ /^[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9][0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9]* \*[A-Z]/) {
    tmp = line
    sub(/^[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9][0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9]* \*/, "", tmp)
    ast          = index(tmp, "*")
    this_level   = toupper((ast > 1) ? substr(tmp, 1, ast - 1) : "")
    is_log_entry = 1
  }

  # ── Level filter ───────────────────────────────────────────────────────
  # Applies only to lines with a detectable level; non-log lines fail.
  level_pass = 1
  if (filter_level != "") {
    if (is_log_entry) {
      if (filter_level == "WARN")
        level_pass = (this_level == "WARN" || this_level == "WARNING") ? 1 : 0
      else
        level_pass = (this_level == filter_level) ? 1 : 0
    } else {
      level_pass = 0
    }
  }

  # ── Find filter ────────────────────────────────────────────────────────
  find_pass = 1
  if (filter_find != "") {
    haystack  = (icase == "true") ? tolower(line)       : line
    needle    = (icase == "true") ? tolower(filter_find) : filter_find
    find_pass = (index(haystack, needle) > 0) ? 1 : 0
  }

  # ── Emit ───────────────────────────────────────────────────────────────
  if (level_pass && find_pass) {
    print "[file: " fname " | line: " NR "] " line
    remaining = ctx_lines - 1
    found++
  } else if (remaining > 0) {
    print line
    remaining--
  }
}
END { if (found == 0) exit 1 }
'

# ---------------------------------------------------------------------------
# Output target setup
# ---------------------------------------------------------------------------
TEMP_OUT=""
if [ -z "$OUTPUT_FILE" ]; then
  TEMP_OUT="$(mktemp)"
  trap 'rm -f "$TEMP_OUT"' EXIT
  OUTPUT_TARGET="$TEMP_OUT"
else
  OUTPUT_TARGET="$OUTPUT_FILE"
  > "$OUTPUT_TARGET"
fi

# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------
MATCH_FOUND=false

for file in "${FILES[@]}"; do
  fname="$(basename "$file")"
  if awk \
      -v fname="$fname" \
      -v filter_level="$LEVEL" \
      -v filter_find="$FIND_STR" \
      -v ctx_lines="$CONTEXT" \
      -v icase="$IGNORE_CASE" \
      "$AWK_SCRIPT" \
      "$file" >> "$OUTPUT_TARGET"
  then
    MATCH_FOUND=true
  fi
done

# ---------------------------------------------------------------------------
# Output results
# ---------------------------------------------------------------------------
if [ "$MATCH_FOUND" = false ]; then
  [ -n "$OUTPUT_FILE" ] && rm -f "$OUTPUT_FILE"
  echo "No matches found"
  exit 1
fi

if [ -n "$OUTPUT_FILE" ]; then
  echo "Output written to '$OUTPUT_FILE'"
else
  cat "$OUTPUT_TARGET"
fi

exit 0
