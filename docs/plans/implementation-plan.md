# CCSnapshot Implementation Plan

## Overview

CCSnapshot collects and restores Claude Code personalizations across machines. Two scripts per platform (Bash for Mac/Linux, PowerShell for Windows) plus one Claude prompt file.

**Scripts:**
- `scripts/collect.sh` / `scripts/collect.ps1` — Deterministic collection (no LLM). Scans known locations, copies artifacts into `snapshot/`, generates manifest.
- `scripts/propagate.sh` / `scripts/propagate.ps1` — Copies snapshot to target locations, then invokes Claude CLI with `prompts/propagate.md` for intelligent adaptation.
- `prompts/propagate.md` — Claude agent prompt for environment evaluation, shell merging, secrets guidance.

**Testing:** bats-core (git submodule, no install required). All tests use a fake `$HOME` with fixture data.

**Key env vars for testability:**
- `CCSNAPSHOT_OUTPUT_DIR` — overrides where collect writes (default: `./snapshot`)
- `CCSNAPSHOT_INPUT_DIR` — overrides where propagate reads from (default: `./snapshot`)

---

## Claude Code File Layout Reference

For anyone unfamiliar with Claude Code's file structure:

```
~/.claude/                     # Global Claude Code config directory
  CLAUDE.md                    # User's global instructions for all projects
  settings.json                # Hooks, plugin refs, status line config
  commands/                    # Custom slash commands (*.md files)
    bootstrap.md
    checkwork.md
  skills/                      # Custom skills (subdirectories)
    writeli/
  plugins/                     # Plugin ecosystem
    installed_plugins.json     # Plugin manifest
    cache/                     # Cached plugin code
    marketplaces/              # Marketplace definitions

~/.claude.json                 # State file (usage stats, feature flags, tips)

<project>/CLAUDE.md            # Project-level instructions
<project>/AGENTS.md            # Agent configuration
<project>/.claude/             # Project-level Claude config
  settings.local.json          # Project-specific settings
  commands/                    # Project-specific slash commands

# Shell configs that may contain Claude-related exports/aliases:
~/.zshrc, ~/.bashrc, ~/.bash_profile, ~/.profile

# Windows equivalents:
%USERPROFILE%\.claude\         # Global config
$PROFILE                       # PowerShell profile
```

---

## Snapshot Directory Structure

```
snapshot/
  manifest.json                # Machine metadata, artifact index, secrets manifest
  global/                      # ~/.claude/ contents
    CLAUDE.md
    settings.json
    claude.json                # ~/.claude.json (renamed, no leading dot)
  commands/                    # ~/.claude/commands/
  skills/                      # ~/.claude/skills/
  plugins/                     # ~/.claude/plugins/
    installed_plugins.json
    cache/
    marketplaces/
  projects/                    # Per-project configs (via --project flag)
    <project-name>/
      CLAUDE.md
      .claude/
  shell-fragments/             # Extracted Claude-related shell config lines
    zshrc.fragment
    bashrc.fragment
    ...
```

---

## Phase 0: Scaffolding

### Task 0.1: Create directory structure and .gitignore

**Files:** `.gitignore`, directory tree

**Do:**
1. Create directories: `scripts/`, `prompts/`, `tests/`, `tests/fixtures/`
2. Create/update `.gitignore` with: `snapshot/`, `.DS_Store`, `session_stats.md`, `tests/bats/` (submodule tracked separately), `*.bak`

**Test:** `ls` confirms directories exist.
**Commit:** `Phase 0.1: Create project directory structure and .gitignore`

### Task 0.2: Add bats-core as git submodule

**Files:** `tests/bats/` (submodule)

**Do:**
1. `git submodule add https://github.com/bats-core/bats-core.git tests/bats`
2. Verify `tests/bats/bin/bats` is executable

**Test:** `./tests/bats/bin/bats --version` prints a version string.
**Commit:** `Phase 0.2: Add bats-core as git submodule for bash testing`

### Task 0.3: Create test helper and fixture structure

**Files:** `tests/test_helper.bash`, `tests/fixtures/`

**Do:**
1. Create `tests/test_helper.bash` with:
   - `setup()` that creates a temp dir, sets `HOME` to it, sets `CCSNAPSHOT_OUTPUT_DIR` to a temp dir
   - `teardown()` that removes both temp dirs
   - Helper function `populate_fixture` that copies from `tests/fixtures/` into fake HOME
2. Create fixture files mimicking a real Claude Code installation:
   - `tests/fixtures/dot-claude/CLAUDE.md` (sample global instructions)
   - `tests/fixtures/dot-claude/settings.json` (sample settings with hooks)
   - `tests/fixtures/dot-claude/commands/bootstrap.md` (sample command)
   - `tests/fixtures/dot-claude/skills/sample-skill/skill.md` (sample skill)
   - `tests/fixtures/dot-claude/plugins/installed_plugins.json` (sample plugin manifest)
   - `tests/fixtures/dot-claude/plugins/cache/sample-plugin/` (sample cached plugin)
   - `tests/fixtures/dot-claude-json` (sample ~/.claude.json, named without dot for git)
   - `tests/fixtures/zshrc` (sample .zshrc with Claude-related lines mixed in)
   - `tests/fixtures/bashrc` (sample .bashrc with anthropic exports)
   - `tests/fixtures/netrc` (sample .netrc with anthropic.com entry)
   - `tests/fixtures/project-alpha/CLAUDE.md` (sample project CLAUDE.md)
   - `tests/fixtures/project-alpha/.claude/settings.local.json`
   - `tests/fixtures/project-alpha/.claude/commands/deploy.md`

**Test:** Source `test_helper.bash`, call `setup`, verify `$HOME` is a temp dir, call `populate_fixture`, verify files exist in fake HOME.
**Commit:** `Phase 0.3: Create test helper, fixtures, and mock Claude environment`

### Task 0.4: Create test file stubs

**Files:** `tests/test_collect.bats`, `tests/test_propagate.bats`

**Do:**
1. Create `tests/test_collect.bats` with `load test_helper` and one placeholder test
2. Create `tests/test_propagate.bats` with `load test_helper` and one placeholder test
3. Run both to verify bats-core works with the helper

**Test:** `./tests/bats/bin/bats tests/test_collect.bats tests/test_propagate.bats` — both pass.
**Commit:** `Phase 0.4: Create test file stubs and verify bats-core integration`

---

## Phase 1: Collect Global Config

### Task 1.1: Write failing tests for global config collection

**Files:** `tests/test_collect.bats`

**Do:** Add tests that:
1. Run `collect.sh` in a populated fake HOME
2. Assert `$CCSNAPSHOT_OUTPUT_DIR/global/CLAUDE.md` exists and matches source
3. Assert `$CCSNAPSHOT_OUTPUT_DIR/global/settings.json` exists and matches source
4. Assert `$CCSNAPSHOT_OUTPUT_DIR/global/claude.json` exists (copied from `~/.claude.json`)
5. Assert collect exits 0

**Test:** Run bats — all new tests FAIL (collect.sh doesn't exist yet).
**Commit:** `Phase 1.1: Write failing tests for global config collection`

### Task 1.2: Implement global config collection

**Files:** `scripts/collect.sh`

**Do:**
1. Create `scripts/collect.sh` with shebang, ABOUTME comment, `set -euo pipefail`
2. Check for `jq` dependency at startup (exit with message if missing)
3. Set `OUTPUT_DIR` from `$CCSNAPSHOT_OUTPUT_DIR` or default to `./snapshot`
4. Create `$OUTPUT_DIR/global/`
5. Copy `~/.claude/CLAUDE.md` → `$OUTPUT_DIR/global/CLAUDE.md` (if exists)
6. Copy `~/.claude/settings.json` → `$OUTPUT_DIR/global/settings.json` (if exists)
7. Copy `~/.claude.json` → `$OUTPUT_DIR/global/claude.json` (if exists)
8. Handle missing files gracefully (skip, don't error)
9. `chmod +x scripts/collect.sh`

**Test:** Run bats — all Phase 1.1 tests PASS.
**Commit:** `Phase 1.2: Implement global config collection in collect.sh`

---

## Phase 2: Collect Commands, Skills

### Task 2.1: Write failing tests for commands and skills collection

**Files:** `tests/test_collect.bats`

**Do:** Add tests that:
1. Assert `$CCSNAPSHOT_OUTPUT_DIR/commands/bootstrap.md` exists after collect
2. Assert command files match source content
3. Assert `$CCSNAPSHOT_OUTPUT_DIR/skills/sample-skill/` directory exists
4. Assert skill contents match source
5. Assert empty commands/skills dirs are skipped (no empty dirs in snapshot)

**Test:** Run bats — new tests FAIL.
**Commit:** `Phase 2.1: Write failing tests for commands and skills collection`

### Task 2.2: Implement commands and skills collection

**Files:** `scripts/collect.sh`

**Do:**
1. If `~/.claude/commands/` exists and is non-empty, copy to `$OUTPUT_DIR/commands/` using `rsync --exclude '.DS_Store'`
2. If `~/.claude/skills/` exists and is non-empty, copy to `$OUTPUT_DIR/skills/` using `rsync --exclude '.DS_Store'`
3. Skip creating dirs if source is empty or missing

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 2.2: Implement commands and skills collection`

---

## Phase 3: Collect Plugins

### Task 3.1: Write failing tests for plugin collection

**Files:** `tests/test_collect.bats`

**Do:** Add tests that:
1. Assert `$CCSNAPSHOT_OUTPUT_DIR/plugins/installed_plugins.json` exists
2. Assert `$CCSNAPSHOT_OUTPUT_DIR/plugins/cache/sample-plugin/` exists
3. Assert `$CCSNAPSHOT_OUTPUT_DIR/plugins/marketplaces/` is copied if present
4. Assert plugin files match source content

**Test:** Run bats — new tests FAIL.
**Commit:** `Phase 3.1: Write failing tests for plugin collection`

### Task 3.2: Implement plugin collection

**Files:** `scripts/collect.sh`

**Do:**
1. If `~/.claude/plugins/` exists, copy entire directory tree to `$OUTPUT_DIR/plugins/` using `rsync --exclude '.DS_Store'`
2. Skip if plugins directory doesn't exist

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 3.2: Implement plugin collection`

---

## Phase 4: Collect Shell Fragments

### Task 4.1: Write failing tests for shell fragment extraction

**Files:** `tests/test_collect.bats`

**Do:** Add tests that:
1. Assert `$CCSNAPSHOT_OUTPUT_DIR/shell-fragments/zshrc.fragment` exists
2. Assert it contains lines with `claude`/`CLAUDE`/`anthropic` from the fixture
3. Assert non-matching lines are NOT included
4. Assert each fragment line is annotated with source file and line number
5. Assert missing shell configs (e.g., no .bashrc) don't cause errors
6. Assert a .bashrc fragment is created when the fixture has one

**Test:** Run bats — new tests FAIL.
**Commit:** `Phase 4.1: Write failing tests for shell fragment extraction`

### Task 4.2: Implement shell fragment extraction

**Files:** `scripts/collect.sh`

**Do:**
1. Define list of shell config files to scan: `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`, `~/.profile`
2. For each file that exists, grep for lines matching `claude|anthropic|CLAUDE|ANTHROPIC` (case-insensitive)
3. Write matching lines to `$OUTPUT_DIR/shell-fragments/<filename>.fragment`
4. Prefix each line with `# source: <filepath>:<lineno>`
5. Skip files that don't exist or have no matches (don't create empty fragments)

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 4.2: Implement shell fragment extraction`

---

## Phase 5: Secrets Detection + Manifest Generation

### Task 5.1: Write failing tests for secrets detection

**Files:** `tests/test_collect.bats`

**Do:** Add tests that:
1. Assert `$CCSNAPSHOT_OUTPUT_DIR/manifest.json` exists and is valid JSON
2. Assert manifest contains `"version": "1.0"`
3. Assert manifest `sourceOS` is populated
4. Assert manifest `sourceShell` is populated
5. Assert manifest `collectedAt` is an ISO-8601 timestamp
6. Assert manifest `artifacts` object lists what was collected
7. Assert manifest `secretsNeeded` array detects ANTHROPIC_API_KEY from shell fragment fixtures
8. Assert manifest `secretsNeeded` detects entries from `.netrc` fixture
9. Assert secret VALUES are never present in the manifest or snapshot

**Test:** Run bats — new tests FAIL.
**Commit:** `Phase 5.1: Write failing tests for secrets detection and manifest`

### Task 5.2: Implement secrets detection and manifest generation

**Files:** `scripts/collect.sh`

**Do:**
1. Add secrets scanning function:
   - Scan shell fragments for patterns: `ANTHROPIC_API_KEY`, `CLAUDE_API_KEY`, `GITHUB_TOKEN`, `export.*API.*KEY`, `export.*TOKEN`
   - Scan `~/.netrc` for `machine.*anthropic` entries
   - Record name + location type (never values)
2. Add manifest generation (requires `jq`):
   - `version`: `"1.0"`
   - `sourceOS`: output of `uname -s | tr '[:upper:]' '[:lower:]'`
   - `sourceShell`: `basename "$SHELL"`
   - `claudeInstallPath`: output of `command -v claude || echo "not found"`
   - `collectedAt`: `date -u +"%Y-%m-%dT%H:%M:%SZ"`
   - `artifacts`: object listing what directories/files were collected with original paths
   - `secretsNeeded`: array of `{name, location}` objects
3. Write manifest as last step of collect (so it reflects everything collected)

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 5.2: Implement secrets detection and manifest generation`

---

## Phase 6: --project Flag

### Task 6.1: Write failing tests for project collection

**Files:** `tests/test_collect.bats`

**Do:** Add tests that:
1. Run `collect.sh --project /path/to/fixture/project-alpha`
2. Assert `$CCSNAPSHOT_OUTPUT_DIR/projects/project-alpha/CLAUDE.md` exists
3. Assert `$CCSNAPSHOT_OUTPUT_DIR/projects/project-alpha/.claude/settings.local.json` exists
4. Assert `$CCSNAPSHOT_OUTPUT_DIR/projects/project-alpha/.claude/commands/deploy.md` exists
5. Assert manifest includes the project in `artifacts.projects`
6. Assert multiple `--project` flags work
7. Assert invalid project path prints warning and continues

**Test:** Run bats — new tests FAIL.
**Commit:** `Phase 6.1: Write failing tests for --project flag`

### Task 6.2: Implement --project flag

**Files:** `scripts/collect.sh`

**Do:**
1. Add argument parsing at top of script: loop over `$@`, collect `--project` values into an array
2. For each project path:
   - Validate directory exists (warn and skip if not)
   - Extract basename for snapshot subdir name
   - Copy `CLAUDE.md` if present
   - Copy `.claude/` directory if present (rsync, exclude .DS_Store)
3. Record projects in manifest artifacts

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 6.2: Implement --project flag for project-level configs`

---

## Phase 7: Idempotency + Summary Output

### Task 7.1: Write failing tests for idempotency and summary

**Files:** `tests/test_collect.bats`

**Do:** Add tests that:
1. Run collect twice, assert output dirs are identical (diff -r)
2. Assert running collect cleans previous snapshot before writing
3. Assert collect prints a summary listing collected items to stdout
4. Assert summary includes counts (e.g., "2 commands", "1 skill")

**Test:** Run bats — new tests FAIL.
**Commit:** `Phase 7.1: Write failing tests for idempotency and summary`

### Task 7.2: Implement idempotency and summary

**Files:** `scripts/collect.sh`

**Do:**
1. At start of collect: if `$OUTPUT_DIR` exists, remove it (`rm -rf`)
2. Track counts of collected items in variables
3. At end: print summary to stdout listing what was collected
4. Summary format:
   ```
   CCSnapshot: Collection complete
     Global config:  ✓ (3 files)
     Commands:       ✓ (2 files)
     Skills:         ✓ (1 directory)
     Plugins:        ✓
     Shell fragments: ✓ (2 files)
     Projects:       ✓ (1 project)
     Secrets found:  2 (recorded in manifest, values NOT collected)
     Manifest:       snapshot/manifest.json
   ```

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 7.2: Implement idempotency and summary output`

---

## Phase 8: Propagate Mechanical Phase

### Task 8.1: Write failing tests for mechanical propagation

**Files:** `tests/test_propagate.bats`

**Do:** Add tests that:
1. Set up a snapshot in `$CCSNAPSHOT_INPUT_DIR` (copy from fixtures)
2. Run `propagate.sh --mechanical-only` with fake HOME
3. Assert `~/.claude/CLAUDE.md` exists and matches snapshot source
4. Assert `~/.claude/settings.json` exists and matches
5. Assert `~/.claude.json` exists (restored from `global/claude.json`)
6. Assert `~/.claude/commands/bootstrap.md` exists
7. Assert `~/.claude/skills/sample-skill/` exists
8. Assert `~/.claude/plugins/installed_plugins.json` exists
9. Assert `--mechanical-only` flag is respected (no Claude CLI invocation)

**Test:** Run bats — all new tests FAIL.
**Commit:** `Phase 8.1: Write failing tests for mechanical propagation`

### Task 8.2: Implement mechanical propagation

**Files:** `scripts/propagate.sh`

**Do:**
1. Create `scripts/propagate.sh` with shebang, ABOUTME comment, `set -euo pipefail`
2. Parse args: `--mechanical-only` flag
3. Set `INPUT_DIR` from `$CCSNAPSHOT_INPUT_DIR` or default to `./snapshot`
4. Validate `$INPUT_DIR/manifest.json` exists (exit with error if not)
5. Restore global config:
   - `$INPUT_DIR/global/CLAUDE.md` → `~/.claude/CLAUDE.md`
   - `$INPUT_DIR/global/settings.json` → `~/.claude/settings.json`
   - `$INPUT_DIR/global/claude.json` → `~/.claude.json`
6. Restore commands: rsync `$INPUT_DIR/commands/` → `~/.claude/commands/`
7. Restore skills: rsync `$INPUT_DIR/skills/` → `~/.claude/skills/`
8. Restore plugins: rsync `$INPUT_DIR/plugins/` → `~/.claude/plugins/`
9. Create directories as needed (`mkdir -p`)
10. `chmod +x scripts/propagate.sh`

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 8.2: Implement mechanical propagation`

### Task 8.3: Write failing tests for backup creation

**Files:** `tests/test_propagate.bats`

**Do:** Add tests that:
1. Pre-populate fake HOME with existing `.claude/CLAUDE.md` (different content)
2. Run propagate
3. Assert `.claude/CLAUDE.md.bak` exists with the old content
4. Assert `.claude/CLAUDE.md` has the new (snapshot) content
5. Assert backup is NOT created when target file doesn't already exist

**Test:** Run bats — new tests FAIL.
**Commit:** `Phase 8.3: Write failing tests for backup creation during propagation`

### Task 8.4: Implement backup creation

**Files:** `scripts/propagate.sh`

**Do:**
1. Before each file copy, check if target exists
2. If it does, copy it to `<target>.bak`
3. Then overwrite with snapshot version

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 8.4: Implement backup creation during propagation`

---

## Phase 9: Propagate Shell Fragments Display + Summary

### Task 9.1: Write failing tests for shell fragment display and summary

**Files:** `tests/test_propagate.bats`

**Do:** Add tests that:
1. Put shell fragments in the snapshot input dir
2. Run propagate with `--mechanical-only`
3. Assert stdout contains the shell fragment content (displayed, not auto-merged)
4. Assert stdout contains a header like "Shell fragments to merge manually:"
5. Assert stdout contains a summary of what was propagated
6. Assert summary includes backup information

**Test:** Run bats — new tests FAIL.
**Commit:** `Phase 9.1: Write failing tests for shell fragment display and summary`

### Task 9.2: Implement shell fragment display and summary

**Files:** `scripts/propagate.sh`

**Do:**
1. After mechanical copy, if `$INPUT_DIR/shell-fragments/` has files:
   - Print header: "Shell fragments to merge (review before adding to your shell config):"
   - For each fragment file, print filename and contents
2. Print propagation summary:
   ```
   CCSnapshot: Propagation complete (mechanical)
     Global config:  ✓ restored
     Commands:       ✓ restored (2 files)
     Skills:         ✓ restored (1 directory)
     Plugins:        ✓ restored
     Backups:        3 files backed up (.bak)
     Shell fragments: displayed above (manual merge needed)
   ```

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 9.2: Implement shell fragment display and propagation summary`

---

## Phase 10: Claude Agent Prompt + CLI Invocation

### Task 10.1: Create Claude agent prompt

**Files:** `prompts/propagate.md`

**Do:** Write the prompt file that instructs Claude to:
1. **Detect environment:** OS, shell, Claude install location, existing shell configs
2. **Read manifest:** Parse `snapshot/manifest.json` to understand source machine
3. **Reconcile:** Compare source vs destination, flag differences
4. **Merge shell fragments:** Read fragments, detect active shell config, merge avoiding duplicates
5. **Guide secrets setup:** For each entry in `secretsNeeded`, explain what it is, where to get it, exact command to set it
6. **Health check:** Run `claude --version`, verify MCP connectivity, report status

The prompt should reference the snapshot directory and manifest.json by path.

**Test:** Manual review — the prompt is a markdown document, not executable code. Verify it references the correct paths and covers all 5 responsibilities.
**Commit:** `Phase 10.1: Create Claude agent prompt for intelligent propagation`

### Task 10.2: Write failing tests for Claude CLI invocation flag

**Files:** `tests/test_propagate.bats`

**Do:** Add tests that:
1. Assert `--mechanical-only` skips Claude invocation (already tested, but verify no "claude" command is attempted)
2. Assert without `--mechanical-only`, the script attempts to invoke `claude` (mock or check exit behavior when claude isn't available)
3. Assert graceful error if `claude` command is not found

**Test:** Run bats — new tests FAIL.
**Commit:** `Phase 10.2: Write failing tests for Claude CLI invocation`

### Task 10.3: Implement Claude CLI invocation

**Files:** `scripts/propagate.sh`

**Do:**
1. After mechanical phase, if `--mechanical-only` is NOT set:
   - Check if `claude` is available (`command -v claude`)
   - If yes: invoke `claude --print "$(cat prompts/propagate.md)"` (or appropriate CLI flag for prompt files)
   - If no: print message telling user to install Claude Code and run the agent manually
2. The exact invocation will depend on Claude CLI's interface for passing prompt files

**Test:** Run bats — all tests PASS.
**Commit:** `Phase 10.3: Implement Claude CLI invocation in propagate script`

---

## Phase 11: PowerShell Ports

### Task 11.1: Port collect.sh to collect.ps1

**Files:** `scripts/collect.ps1`

**Do:**
1. Translate all collect.sh logic to PowerShell
2. Use `$env:USERPROFILE\.claude\` instead of `~/.claude/`
3. Use `$env:CCSNAPSHOT_OUTPUT_DIR` for testability
4. Use `Copy-Item -Recurse` instead of rsync
5. Use `ConvertTo-Json` instead of jq for manifest generation
6. PowerShell profile path: `$PROFILE` variable
7. Scan PowerShell profile for Claude-related lines

**Test:** Manual testing on Windows (or document testing instructions). Logic should mirror collect.sh.
**Commit:** `Phase 11.1: Port collect script to PowerShell`

### Task 11.2: Port propagate.sh to propagate.ps1

**Files:** `scripts/propagate.ps1`

**Do:**
1. Translate all propagate.sh logic to PowerShell
2. Same path adaptations as collect.ps1
3. Support `-MechanicalOnly` switch parameter
4. Use `Copy-Item` with backup logic
5. Claude CLI invocation via `& claude` syntax

**Test:** Manual testing on Windows (or document testing instructions).
**Commit:** `Phase 11.2: Port propagate script to PowerShell`

---

## Phase 12: Final Verification and Cleanup

### Task 12.1: Run full test suite and verify

**Do:**
1. Run `./tests/bats/bin/bats tests/test_collect.bats tests/test_propagate.bats`
2. All tests must pass
3. Manual smoke test: run collect on real machine, inspect snapshot
4. Manual smoke test: propagate to temp location with `--mechanical-only`

**Verification commands:**
```bash
# Full test suite
./tests/bats/bin/bats tests/test_collect.bats tests/test_propagate.bats

# Smoke test collect
./scripts/collect.sh
cat snapshot/manifest.json | jq .

# Smoke test propagate
CCSNAPSHOT_INPUT_DIR=snapshot HOME=/tmp/ccsnapshot-test ./scripts/propagate.sh --mechanical-only
ls -la /tmp/ccsnapshot-test/.claude/
```

**Commit:** `Phase 12.1: Final verification — all tests passing`

---

## Post-Launch Ideas (not in scope for V1)

These are documented for future reference:

- **[Keith's idea]** Selective collect — `--only commands,skills` flag
- **[Keith's idea]** Diff mode — show what changed since last snapshot
- **[Claude's idea]** Plugin marketplace reinstall — propagate records plugin names, auto-reinstalls from marketplace
- **[Claude's idea]** Encrypted secrets vault — optional encrypted section for API keys with passphrase
- **[Keith's idea]** Project auto-discovery — scan for CLAUDE.md files under a root dir
- **[Claude's idea]** Snapshot validation — `--validate` flag to check snapshot integrity
- **[Claude's idea]** Cross-platform path mapping — automatic path translation in configs
- **[Claude's idea]** Linux CI testing — GitHub Actions with bats-core
- **[Keith's idea]** Watch mode — re-collect on file changes
