# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `collect.sh` — deterministic collection of Claude Code personalizations
- `propagate.sh` — mechanical restoration with optional Claude agent adaptation
- `collect.ps1` / `propagate.ps1` — Windows PowerShell ports
- `prompts/propagate.md` — Claude agent prompt for intelligent propagation
- `--project` flag for collecting project-level configs
- `--mechanical-only` flag for propagation without Claude agent
- Secrets detection (names only, never values)
- Manifest generation with machine metadata and artifact index
- Shell fragment extraction from zshrc, bashrc, bash_profile, profile
- Backup creation (`.bak`) before overwriting existing files
- Idempotent collection (re-running produces identical output)
- bats-core test suite
