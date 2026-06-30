# logs-reader-app — CLAUDE.md

## Project overview

Bash script that reads and filters large AEM log files dropped into a `logs/` folder.
No login or authentication required.

## Project structure

```
logs-reader-app/
├── read-logs.sh                   ← main script
├── logs/                          ← drop log files here (gitignored)
└── tests/
    ├── test_helper.bash           ← shared BATS helpers
    ├── unit.bats                  ← unit tests
    ├── integration.bats           ← integration tests
    ├── regression.bats            ← regression tests
    └── fixtures/
        ├── java-format1.log       ← YYYY-MM-DD LEVEL format fixture
        ├── java-format2.log       ← DD.MM.YYYY *LEVEL* format fixture
        └── apache-access.log      ← no-level format fixture
```

## Running the script

```bash
./read-logs.sh --help
./read-logs.sh --level=error
./read-logs.sh --level=error --find='Cannot persist'
./read-logs.sh --level=error --find='PersistenceException' --context=20
./read-logs.sh --file=logs/app.log --level=warn --find='timeout'
./read-logs.sh --level=debug --find='user@example.com' --ignore-case
./read-logs.sh --level=error --output=errors.log
```

## Running tests

```bash
bats tests/                  # full suite
bats tests/unit.bats         # a single test file
bats -f 'context' tests/     # tests whose name matches a filter
shellcheck read-logs.sh      # static analysis (the script is written to pass clean)
```

There is no build step. Install BATS if missing: `brew install bats-core`

## Supported log formats

| Name | Pattern |
|------|---------|
| Format 1 (ecommerce) | `YYYY-MM-DD HH:MM:SS.mmm LEVEL [class] message` |
| Format 2 (error log) | `DD.MM.YYYY HH:MM:SS.mmm *LEVEL* [thread] class message` |

Stacktrace continuation lines (starting with `\t` or `at `) are not log-entry headers
and are treated accordingly (see behaviour notes below).

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--level=LEVEL` | Filter by log level: `trace`, `debug`, `info`, `warn`, `error` (`warning` is an alias for `warn`) | — |
| `--find=STRING` | Search for a specific string | — |
| `--file=FILE` | Restrict search to a specific file | all files in `logs/` |
| `--context=N` | Total lines shown per match (match + N−1 more) | `1` |
| `--ignore-case` | Case-insensitive search | case-sensitive |
| `--output=FILE` | Write results to file instead of terminal | terminal |
| `--help` | Show usage | — |

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Results found |
| `1` | No matches |
| `2` | Error (bad arguments, file/directory not found, etc.) |

## Output format

```
[file: filename.log | line: 42] 2026-02-16 00:01:00.045 ERROR [com.example.Service] message
```

Context lines beyond the first are printed without the `[file | line]` prefix.

## Architecture

The whole tool is one bash file. The big-picture pieces that span the file:

- **Single embedded awk engine** (`AWK_SCRIPT`, see `read-logs.sh`): the entire
  matching pipeline — level detection, level filtering, `--find` filtering, and
  context emission — lives in this one awk string, invoked once per file. Behaviour
  changes happen inside that string, not in the surrounding bash.
- **Exit-code propagation is structural**: the awk `END` block does `exit 1` when a
  file produces zero matches; the bash search loop OR-reduces the per-file results
  into `MATCH_FOUND`. This is the mechanism behind the no-match exit code and the
  `--output` cleanup-on-empty behaviour.
- **Output buffering**: terminal output is written to a `mktemp` buffer that a trap
  removes on exit; `--output=FILE` truncates the target up front and deletes it again
  if no matches were found — so a failed search never leaves a stale output file.

## Key design decisions

- **`--level` scope**: applies only to lines with a detectable level header. Stacktrace
  continuation lines and Apache-style logs (no level field) are excluded from level
  filtering and are searchable via `--find` only.
- **`--find` scope**: searches every individual line, including continuation/stacktrace
  lines. It does NOT perform multi-line entry matching.
- **`--context=N`**: N is the total number of lines shown per match (including the
  match line). Default is 1 (match line only). Example: `--context=5` shows the match
  line plus 4 additional lines.
- **Performance**: single-pass `awk` engine per file — O(n) time, O(1) memory.
  Handles files of 300 MB or more without loading them into memory.
- **`LOGS_DIR` env var**: overrides the default `$SCRIPT_DIR/logs`. Used by the test
  suite to point at isolated temporary directories.

## Test suite conventions

- Framework: **BATS 1.13.0** (`brew install bats-core`)
- All tests load `tests/test_helper.bash` via `load 'test_helper'`
- Each test creates an isolated `TEST_LOGS_DIR` in `setup()` and removes it in `teardown()`
- Fixtures are copied into `TEST_LOGS_DIR` with `copy_fixture <filename>`
- `LOGS_DIR` is exported so the script under test uses the temporary directory
- `SCRIPT_PATH` and `FIXTURES_DIR` are resolved automatically by the helper

## Compatibility

- **Shell**: bash 3.2+ (macOS system bash compatible; no `mapfile`, no associative arrays)
- **awk**: POSIX awk (macOS system awk / BSD nawk compatible; no gawk extensions)
