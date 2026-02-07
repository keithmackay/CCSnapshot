# Contributing to CCSnapshot

Contributions are welcome. This document covers how to report issues, suggest features, and submit changes.

## Reporting Bugs

Open an issue using the [bug report template](https://github.com/keithmackay/CCSnapshot/issues/new?template=bug_report.yml). Include:

- What you ran (exact command)
- What you expected
- What actually happened
- Your OS, shell, and `jq --version` output

## Suggesting Features

Open an issue using the [feature request template](https://github.com/keithmackay/CCSnapshot/issues/new?template=feature_request.yml). Describe the problem you're trying to solve before proposing a solution.

## Development Setup

```bash
git clone git@github.com:keithmackay/CCSnapshot.git
cd CCSnapshot
git submodule update --init
```

### Prerequisites

- Bash (macOS/Linux) or PowerShell (Windows)
- jq — macOS/Linux only (`brew install jq` or `apt-get install jq`)
- rsync — macOS/Linux only (pre-installed on most systems)

### Running Tests

Tests use [bats-core](https://github.com/bats-core/bats-core), included as a git submodule. Each test runs against a temporary fake `$HOME`, so nothing touches your real config.

```bash
# Run all tests
./tests/bats/bin/bats tests/test_collect.bats tests/test_propagate.bats
```

### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `CCSNAPSHOT_OUTPUT_DIR` | Where collect writes the snapshot | `./snapshot` |
| `CCSNAPSHOT_INPUT_DIR` | Where propagate reads the snapshot | `./snapshot` |

## Pull Request Process

1. Fork the repo and create a branch from `main`.
2. Write tests first — this project follows TDD. Every change should have a corresponding bats test.
3. Keep `collect.sh` deterministic — no network calls, no LLM invocations.
4. Run the full test suite and confirm all tests pass.
5. Open a pull request with a clear description of what changed and why.
6. PRs are reviewed and merged at the maintainer's discretion.

## Code Style

- Shell scripts use `set -euo pipefail`.
- Every script file starts with a two-line `ABOUTME:` comment.
- Use `rsync` for directory copies (with `--exclude '.DS_Store'`).
- Use `jq` for JSON generation and manipulation.
- Match the style of surrounding code.

## Code of Conduct

This project follows the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Be respectful and constructive.
