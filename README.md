# logs-reader-app

A single-file Bash tool for reading and filtering large AEM log files. It streams
each file through one embedded `awk` engine, so it handles 300 MB+ logs in O(n)
time and O(1) memory — without loading them into RAM. No login or authentication
required.

## Requirements

- **bash** 3.2+ (macOS system bash is fine)
- **awk** (POSIX / BSD nawk; no gawk extensions needed)

Both ship with macOS and every Linux distro, so there is nothing to install and
no build step.

## Quick start

```bash
# 1. Drop log files into the logs/ folder (it's gitignored)
cp /path/to/app.log logs/

# 2. Search
./read-logs.sh --level=error
./read-logs.sh --level=error --find='Cannot persist'
```

By default the script searches every file in `logs/`. Use `--file=FILE` to
restrict it to one file anywhere on disk.

## Usage

```
./read-logs.sh [OPTIONS]
```

At least one of `--level` or `--find` is required.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--level=LEVEL` | Filter by log level: `trace`, `debug`, `info`, `warn`, `error` (`warning` is an alias for `warn`) | — |
| `--find=STRING` | Search for a specific string | — |
| `--file=FILE` | Restrict search to a specific file | all files in `logs/` |
| `--context=N` | Total lines shown per match (the match line + N−1 more) | `1` |
| `--ignore-case` | Case-insensitive search | case-sensitive |
| `--output=FILE` | Write results to a file instead of the terminal | terminal |
| `--help` | Show usage | — |

Run `./read-logs.sh --help` for the built-in reference.

## Examples

```bash
# All ERROR-level entries across every file in logs/
./read-logs.sh --level=error

# ERROR entries containing a phrase, with 20 lines of context per match
./read-logs.sh --level=error --find='PersistenceException' --context=20

# Search a specific file for WARN entries mentioning "timeout"
./read-logs.sh --file=logs/app.log --level=warn --find='timeout'

# Case-insensitive search, written to a file
./read-logs.sh --level=error --ignore-case --output=errors.log

# Find a string regardless of level (e.g. in an Apache access log)
./read-logs.sh --find='user@example.com' --ignore-case
```

## Supported log formats

| Name | Pattern |
|------|---------|
| Format 1 (ecommerce) | `YYYY-MM-DD HH:MM:SS.mmm LEVEL [class] message` |
| Format 2 (error log) | `DD.MM.YYYY HH:MM:SS.mmm *LEVEL* [thread] class message` |

## Behaviour notes

- **`--level` applies only to lines with a detectable level header.** Stacktrace
  continuation lines (starting with `\t` or `at `) and Apache-style logs with no
  level field are excluded from level filtering — search those with `--find`.
- **`--find` searches every individual line,** including stacktrace continuation
  lines. It does not perform multi-line entry matching.
- **`--context=N` counts the match line itself.** `--context=1` (the default)
  shows only the match; `--context=5` shows the match plus 4 following lines.
  Context lines beyond the match are printed without the `[file | line]` prefix.

## Output format

```
[file: filename.log | line: 42] 2026-02-16 00:01:00.045 ERROR [com.example.Service] message
```

When `--output=FILE` is used, results go to that file and a confirmation is
printed to the terminal. If a search finds nothing, no stale output file is left
behind.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Results found |
| `1` | No matches |
| `2` | Error (bad arguments, file/directory not found, etc.) |

## Configuration

`LOGS_DIR` overrides the default search directory (`<script dir>/logs`):

```bash
LOGS_DIR=/var/log/aem ./read-logs.sh --level=error
```

## Development

```bash
bats tests/                  # run the full test suite
bats tests/unit.bats         # run a single test file
bats -f 'context' tests/     # run tests whose name matches a filter
shellcheck read-logs.sh      # static analysis (the script is written to pass clean)
```

Install BATS if missing: `brew install bats-core`. There is no build step.
