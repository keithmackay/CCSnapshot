# CCSnapshot — Phases Summary

## Tech Stack

- **Bash** (macOS/Linux scripts)
- **PowerShell** (Windows scripts)
- **bats-core** (Bash testing framework, git submodule)
- **jq** (JSON processing, required dependency)
- **rsync** (directory copying with exclusions)
- **Claude Code CLI** (intelligent propagation agent)

## Principles

1. **TDD everywhere** — failing test first, then implementation
2. **Deterministic collect** — no LLM, no network, runs in seconds
3. **Intelligent propagate** — mechanical copy + Claude agent for adaptation
4. **Never collect secrets** — record names only, guide setup on destination
5. **Testable by default** — env var overrides for all paths

## Phases

| Phase | Title | Tasks | Key Deliverables |
|-------|-------|-------|------------------|
| 0 | Scaffolding | 0.1–0.4 | Dirs, bats-core submodule, fixtures, test stubs |
| 1 | Global Config Collection | 1.1–1.2 | collect.sh collects CLAUDE.md, settings.json, claude.json |
| 2 | Commands & Skills | 2.1–2.2 | collect.sh gathers commands/ and skills/ |
| 3 | Plugins | 3.1–3.2 | collect.sh gathers plugins/ tree |
| 4 | Shell Fragments | 4.1–4.2 | Extract Claude-related lines from shell configs |
| 5 | Secrets & Manifest | 5.1–5.2 | Secrets detection, manifest.json generation |
| 6 | Project Flag | 6.1–6.2 | --project flag for project-level configs |
| 7 | Idempotency & Summary | 7.1–7.2 | Clean re-collect, user-facing summary |
| 8 | Propagate Mechanical | 8.1–8.4 | propagate.sh file copy + backups |
| 9 | Propagate Display | 9.1–9.2 | Shell fragment display, propagation summary |
| 10 | Claude Agent | 10.1–10.3 | prompts/propagate.md, CLI invocation |
| 11 | PowerShell Ports | 11.1–11.2 | collect.ps1, propagate.ps1 |
| 12 | Verification | 12.1 | Full test suite, smoke tests |

## Task List

### Phase 0: Scaffolding
- 0.1: Create directory structure and .gitignore
- 0.2: Add bats-core as git submodule
- 0.3: Create test helper and fixture structure
- 0.4: Create test file stubs

### Phase 1: Collect Global Config
- 1.1: Write failing tests for global config collection
- 1.2: Implement global config collection

### Phase 2: Collect Commands & Skills
- 2.1: Write failing tests for commands and skills collection
- 2.2: Implement commands and skills collection

### Phase 3: Collect Plugins
- 3.1: Write failing tests for plugin collection
- 3.2: Implement plugin collection

### Phase 4: Collect Shell Fragments
- 4.1: Write failing tests for shell fragment extraction
- 4.2: Implement shell fragment extraction

### Phase 5: Secrets Detection + Manifest
- 5.1: Write failing tests for secrets detection and manifest
- 5.2: Implement secrets detection and manifest generation

### Phase 6: Project Flag
- 6.1: Write failing tests for --project flag
- 6.2: Implement --project flag

### Phase 7: Idempotency + Summary
- 7.1: Write failing tests for idempotency and summary
- 7.2: Implement idempotency and summary

### Phase 8: Propagate Mechanical Phase
- 8.1: Write failing tests for mechanical propagation
- 8.2: Implement mechanical propagation
- 8.3: Write failing tests for backup creation
- 8.4: Implement backup creation

### Phase 9: Propagate Display + Summary
- 9.1: Write failing tests for shell fragment display and summary
- 9.2: Implement shell fragment display and summary

### Phase 10: Claude Agent Prompt
- 10.1: Create Claude agent prompt
- 10.2: Write failing tests for CLI invocation
- 10.3: Implement Claude CLI invocation

### Phase 11: PowerShell Ports
- 11.1: Port collect.sh to collect.ps1
- 11.2: Port propagate.sh to propagate.ps1

### Phase 12: Final Verification
- 12.1: Run full test suite and smoke tests

## Success Criteria

- [ ] `./tests/bats/bin/bats tests/test_collect.bats` — all pass
- [ ] `./tests/bats/bin/bats tests/test_propagate.bats` — all pass
- [ ] `./scripts/collect.sh` produces valid snapshot on real machine
- [ ] `./scripts/propagate.sh --mechanical-only` restores to clean HOME
- [ ] `snapshot/manifest.json` is valid JSON with correct schema
- [ ] No secret values appear anywhere in snapshot
- [ ] Running collect twice produces identical output
- [ ] Existing files are backed up before overwrite

## Post-Launch Ideas

- Selective collect (`--only commands,skills`)
- Diff mode (show changes since last snapshot)
- Plugin marketplace auto-reinstall
- Encrypted secrets vault
- Project auto-discovery
- Snapshot validation (`--validate`)
- Cross-platform path mapping
- Linux CI testing (GitHub Actions)
- Watch mode (re-collect on changes)
