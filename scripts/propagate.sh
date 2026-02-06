#!/usr/bin/env bash
# ABOUTME: Restores Claude Code personalizations from a snapshot directory.
# ABOUTME: Mechanical file copy with backups, optional Claude agent for adaptation.

set -euo pipefail

INPUT_DIR="${CCSNAPSHOT_INPUT_DIR:-./snapshot}"
MECHANICAL_ONLY=false

# --- Argument parsing ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mechanical-only)
      MECHANICAL_ONLY=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# --- Validation ---

if [[ ! -f "${INPUT_DIR}/manifest.json" ]]; then
  echo "Error: manifest.json not found in ${INPUT_DIR}" >&2
  echo "Run collect.sh first to create a snapshot." >&2
  exit 1
fi

# --- Backup helper ---

# Copy source to dest, creating a .bak of dest if it already exists.
safe_copy() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"

  if [[ -f "$dest" ]]; then
    cp "$dest" "${dest}.bak"
  fi

  cp "$src" "$dest"
}

# --- Restore functions ---

restore_global_config() {
  local global_dir="${INPUT_DIR}/global"

  if [[ ! -d "$global_dir" ]]; then
    return 0
  fi

  if [[ -f "${global_dir}/CLAUDE.md" ]]; then
    safe_copy "${global_dir}/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
  fi

  if [[ -f "${global_dir}/settings.json" ]]; then
    safe_copy "${global_dir}/settings.json" "${HOME}/.claude/settings.json"
  fi

  if [[ -f "${global_dir}/claude.json" ]]; then
    safe_copy "${global_dir}/claude.json" "${HOME}/.claude.json"
  fi
}

restore_commands() {
  if [[ -d "${INPUT_DIR}/commands" ]] && [[ -n "$(ls -A "${INPUT_DIR}/commands" 2>/dev/null)" ]]; then
    mkdir -p "${HOME}/.claude/commands"
    rsync -a "${INPUT_DIR}/commands/" "${HOME}/.claude/commands/"
  fi
}

restore_skills() {
  if [[ -d "${INPUT_DIR}/skills" ]] && [[ -n "$(ls -A "${INPUT_DIR}/skills" 2>/dev/null)" ]]; then
    mkdir -p "${HOME}/.claude/skills"
    rsync -a "${INPUT_DIR}/skills/" "${HOME}/.claude/skills/"
  fi
}

restore_plugins() {
  if [[ -d "${INPUT_DIR}/plugins" ]] && [[ -n "$(ls -A "${INPUT_DIR}/plugins" 2>/dev/null)" ]]; then
    mkdir -p "${HOME}/.claude/plugins"
    rsync -a "${INPUT_DIR}/plugins/" "${HOME}/.claude/plugins/"
  fi
}

# --- Main ---

restore_global_config
restore_commands
restore_skills
restore_plugins
