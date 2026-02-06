# CCSnapshot

## Description

CCSnapshot is a command-line tool for collecting, versioning, and restoring Claude Code personalizations across machines. It captures your CLAUDE.md files (both project-level and global), aliases, Claude configurations, plugins, commands, agents, and skills into a portable repository structure. A companion restore script deploys those settings onto a new machine, using Claude itself to evaluate the destination environment and adapt paths, shell configs, and token requirements accordingly.

## Architecture

CCSnapshot has two scripts per platform (Bash for Mac/Linux, PowerShell for Windows) and one Claude prompt file:

- **`collect.sh` / `collect.ps1`** - Deterministic, no LLM. Scans known locations, copies artifacts into `snapshot/`, generates a manifest of secrets needed, extracts Claude-related shell fragments. Runs in seconds.
- **`propagate.sh` / `propagate.ps1`** - Thin wrapper. Copies files from `snapshot/` to their target locations on the new machine, then invokes Claude Code CLI with a bundled prompt (`prompts/propagate.md`) to handle intelligent adaptation: environment evaluation, path fixups, shell config merging, and token setup instructions.
- **`prompts/propagate.md`** - The Claude agent prompt. Tells Claude to evaluate the destination machine, reconcile differences with the snapshot's source manifest, and walk the user through whatever manual steps remain (token acquisition, etc.).

## Snapshot Structure

```
snapshot/
  manifest.json          # Machine metadata, source paths, secrets manifest
  global/                # ~/.claude/ contents (settings, config)
  commands/              # Custom slash commands
  skills/                # Custom skills
  plugins/               # Installed plugins
  projects/              # Project-level CLAUDE.md and .claude/ dirs (user-specified)
    <project-name>/
  shell-fragments/       # Claude-related lines extracted from shell configs
```

## Collect Script

The collect script walks known locations and copies artifacts into `snapshot/`. It takes no arguments by default (collects global config), and accepts optional flags to include project-level configs.

### Usage

```bash
# Collect global config only
./collect.sh

# Collect global + specific projects
./collect.sh --project ~/Projects/MyApp --project ~/Projects/OtherApp
```

### What It Collects

1. **Global Claude config** (`~/.claude/`) - settings files, `CLAUDE.md` if present. Copied to `snapshot/global/`.
2. **Commands** (`~/.claude/commands/`) - custom slash commands. Copied to `snapshot/commands/`.
3. **Skills** - discovered from Claude's known skill directories. Copied to `snapshot/skills/`.
4. **Plugins** - plugin configurations and references. Copied to `snapshot/plugins/`.
5. **Project configs** - for each `--project` path, copies the project's `CLAUDE.md` and `.claude/` directory into `snapshot/projects/<dirname>/`.
6. **Shell fragments** - parses `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`, `~/.profile`, and PowerShell profile for lines containing `claude`, `anthropic`, or `CLAUDE`. Writes extracted lines to `snapshot/shell-fragments/`.
7. **Manifest** - generates `snapshot/manifest.json` with: source OS, shell type, Claude install path, list of collected artifacts with their original absolute paths, and a `secrets_needed` array listing tokens/keys the source machine had configured (names only, never values).

### Secrets Handling

Secrets are never collected. The collect script scans for patterns like `ANTHROPIC_API_KEY`, `GITHUB_TOKEN`, entries in `~/.netrc`, and MCP server credentials. It records that these exist and where they're expected, but never copies the values. The propagation agent uses this manifest to guide the user through secret setup on the destination.

## Propagate Script

The propagate script has two phases: a mechanical phase (scripted) and an intelligent phase (Claude agent).

### Phase 1 - Mechanical (no LLM)

Reads `snapshot/manifest.json` and copies artifacts to target locations using platform-appropriate paths:

- `snapshot/global/` → `~/.claude/` (or Windows equivalent `%USERPROFILE%\.claude\`)
- `snapshot/commands/` → `~/.claude/commands/`
- `snapshot/skills/` → appropriate skill directory
- `snapshot/plugins/` → appropriate plugin directory
- `snapshot/projects/<name>/` → user is prompted for the destination path

Before overwriting, it checks for existing files and creates `.bak` backups.

### Phase 2 - Intelligent (Claude agent)

After the mechanical copy, the script invokes Claude Code CLI with `prompts/propagate.md`. The agent:

1. **Detects the environment** - OS, shell, Claude install location, existing shell configs.
2. **Reconciles with the manifest** - compares source machine state vs. destination. Flags missing tools, different paths, version mismatches.
3. **Merges shell fragments** - reads extracted Claude-related lines from `snapshot/shell-fragments/` and merges them into the destination's active shell config, avoiding duplicates.
4. **Walks through secrets setup** - using the `secrets_needed` array, guides the user step-by-step: what each token is for, where to obtain it, and the exact command to set it.
5. **Verifies** - runs a health check (e.g., `claude --version`, MCP server connectivity) and reports what succeeded and what needs attention.

## Cross-Platform Considerations

- **Path translation**: The manifest stores original absolute paths for reference. The mechanical phase maps `snapshot/` subdirectories to the platform's Claude home directory rather than replaying source paths directly.
- **Skill and plugin discovery**: The collect script checks known locations and records provenance. The propagation agent determines the correct destination based on the target environment.
- **Partial collection**: Empty sections (no custom skills, no shell aliases) are skipped gracefully.
- **Idempotency**: Collecting twice overwrites the previous snapshot (git tracks the diff). Propagating twice is safe via backups and duplicate detection.
- **No network required for collect**: The collect step is entirely local. Propagate only needs network for the optional GitHub clone and Claude's environment evaluation.

## Installation

*Coming soon*

## License

*Coming soon*
