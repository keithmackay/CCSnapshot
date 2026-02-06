#!/usr/bin/env bash
# ABOUTME: Collects Claude Code personalizations into a portable snapshot directory.
# ABOUTME: Deterministic, no LLM — scans known locations and copies artifacts.

set -euo pipefail

OUTPUT_DIR="${CCSNAPSHOT_OUTPUT_DIR:-./snapshot}"

# --- Dependency check ---

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)" >&2
  exit 1
fi

# --- Global config collection ---

collect_global_config() {
  local claude_dir="${HOME}/.claude"
  local claude_json="${HOME}/.claude.json"

  if [[ ! -d "$claude_dir" && ! -f "$claude_json" ]]; then
    return 0
  fi

  mkdir -p "${OUTPUT_DIR}/global"

  if [[ -f "${claude_dir}/CLAUDE.md" ]]; then
    cp "${claude_dir}/CLAUDE.md" "${OUTPUT_DIR}/global/CLAUDE.md"
  fi

  if [[ -f "${claude_dir}/settings.json" ]]; then
    cp "${claude_dir}/settings.json" "${OUTPUT_DIR}/global/settings.json"
  fi

  if [[ -f "$claude_json" ]]; then
    cp "$claude_json" "${OUTPUT_DIR}/global/claude.json"
  fi
}

# --- Commands and skills collection ---

collect_commands() {
  local commands_dir="${HOME}/.claude/commands"

  if [[ -d "$commands_dir" ]] && [[ -n "$(ls -A "$commands_dir" 2>/dev/null)" ]]; then
    rsync -a --exclude '.DS_Store' "${commands_dir}/" "${OUTPUT_DIR}/commands/"
  fi
}

collect_skills() {
  local skills_dir="${HOME}/.claude/skills"

  if [[ -d "$skills_dir" ]] && [[ -n "$(ls -A "$skills_dir" 2>/dev/null)" ]]; then
    rsync -a --exclude '.DS_Store' "${skills_dir}/" "${OUTPUT_DIR}/skills/"
  fi
}

# --- Plugin collection ---

collect_plugins() {
  local plugins_dir="${HOME}/.claude/plugins"

  if [[ -d "$plugins_dir" ]] && [[ -n "$(ls -A "$plugins_dir" 2>/dev/null)" ]]; then
    rsync -a --exclude '.DS_Store' "${plugins_dir}/" "${OUTPUT_DIR}/plugins/"
  fi
}

# --- Main ---

collect_global_config
collect_commands
collect_skills
collect_plugins
