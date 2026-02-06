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

# --- Shell fragment extraction ---

# Extract lines matching Claude/Anthropic patterns from a shell config file.
# Writes matching lines with source annotations to a fragment file.
extract_shell_fragments() {
  local source_file="$1"
  local fragment_name="$2"

  if [[ ! -f "$source_file" ]]; then
    return 0
  fi

  local fragment_file="${OUTPUT_DIR}/shell-fragments/${fragment_name}.fragment"
  local lineno=0
  local found_match=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    if echo "$line" | grep -iq 'claude\|anthropic'; then
      if [[ "$found_match" == false ]]; then
        mkdir -p "${OUTPUT_DIR}/shell-fragments"
        found_match=true
      fi
      echo "# source: ${source_file}:${lineno}" >> "$fragment_file"
      echo "$line" >> "$fragment_file"
    fi
  done < "$source_file"
}

collect_shell_fragments() {
  extract_shell_fragments "${HOME}/.zshrc" "zshrc"
  extract_shell_fragments "${HOME}/.bashrc" "bashrc"
  extract_shell_fragments "${HOME}/.bash_profile" "bash_profile"
  extract_shell_fragments "${HOME}/.profile" "profile"
}

# --- Main ---

collect_global_config
collect_commands
collect_skills
collect_plugins
collect_shell_fragments
