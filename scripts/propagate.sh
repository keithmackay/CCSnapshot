#!/usr/bin/env bash
# ABOUTME: Restores Claude Code personalizations from a snapshot directory.
# ABOUTME: Mechanical file copy with backups, optional Claude agent for adaptation.

set -euo pipefail

INPUT_DIR="${CCSNAPSHOT_INPUT_DIR:-./snapshot}"
MECHANICAL_ONLY=false
ARCHIVE_PATH=""

# --- Argument parsing ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mechanical-only)
      MECHANICAL_ONLY=true
      shift
      ;;
    --archive)
      if [[ -n "${2:-}" ]]; then
        ARCHIVE_PATH="$2"
        shift 2
      else
        echo "Error: --archive requires a path argument" >&2
        exit 1
      fi
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# --- Archive extraction ---

if [[ -n "$ARCHIVE_PATH" ]]; then
  if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "Error: archive not found: $ARCHIVE_PATH" >&2
    exit 1
  fi

  rm -rf "$INPUT_DIR"
  mkdir -p "$INPUT_DIR"
  tar -xzf "$ARCHIVE_PATH" -C "$INPUT_DIR"
fi

# --- Validation ---

if [[ ! -f "${INPUT_DIR}/manifest.json" ]]; then
  echo "Error: manifest.json not found in ${INPUT_DIR}" >&2
  echo "Run collect.sh first to create a snapshot, or pass --archive <path>." >&2
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

restore_history() {
  local history_dir="${INPUT_DIR}/history"

  if [[ ! -d "$history_dir" ]] || [[ -z "$(ls -A "$history_dir" 2>/dev/null)" ]]; then
    return 0
  fi

  mkdir -p "${HOME}/.claude/projects"
  rsync -a --exclude '.DS_Store' "${history_dir}/" "${HOME}/.claude/projects/"
}

# --- Shell fragment display ---

display_shell_fragments() {
  local fragments_dir="${INPUT_DIR}/shell-fragments"

  if [[ ! -d "$fragments_dir" ]] || [[ -z "$(ls -A "$fragments_dir" 2>/dev/null)" ]]; then
    return 0
  fi

  echo ""
  echo "Shell fragments to merge (review before adding to your shell config):"
  echo "----------------------------------------------------------------------"

  for fragment in "$fragments_dir"/*.fragment; do
    [[ -f "$fragment" ]] || continue
    local name
    name=$(basename "$fragment")
    echo ""
    echo "  From: ${name%.fragment}"
    while IFS= read -r line; do
      echo "    $line"
    done < "$fragment"
  done

  echo "----------------------------------------------------------------------"
  echo ""
}

# --- Propagation summary ---

print_summary() {
  local global_count=0
  local cmd_count=0
  local skill_count=0
  local plugin_status="-"
  local history_status="-"
  local backup_count=0

  if [[ -d "${HOME}/.claude" ]]; then
    backup_count=$(find "${HOME}/.claude" -name "*.bak" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ -f "${HOME}/.claude.json.bak" ]]; then
    backup_count=$((backup_count + 1))
  fi
  if [[ -d "${INPUT_DIR}/global" ]]; then
    global_count=$(ls "${INPUT_DIR}/global/" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ -d "${INPUT_DIR}/commands" ]]; then
    cmd_count=$(ls "${INPUT_DIR}/commands/" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ -d "${INPUT_DIR}/skills" ]]; then
    skill_count=$(ls "${INPUT_DIR}/skills/" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ -d "${INPUT_DIR}/plugins" ]]; then
    plugin_status="restored"
  fi
  if [[ -d "${INPUT_DIR}/history" ]] && [[ -n "$(ls -A "${INPUT_DIR}/history" 2>/dev/null)" ]]; then
    history_status="restored"
  fi

  echo ""
  echo "CCSnapshot: Propagation complete (mechanical)"
  echo "  Global config:   ${global_count} files restored"
  echo "  Commands:        ${cmd_count} files restored"
  echo "  Skills:          ${skill_count} directories restored"
  echo "  Plugins:         ${plugin_status}"
  echo "  History:         ${history_status}"
  if [[ "$backup_count" -gt 0 ]]; then
    echo "  Backups:         ${backup_count} files backed up (.bak)"
  fi
  if [[ -d "${INPUT_DIR}/shell-fragments" ]]; then
    echo "  Shell fragments: displayed above (manual merge needed)"
  fi
}

# --- Claude agent invocation ---

invoke_claude_agent() {
  if [[ "$MECHANICAL_ONLY" == true ]]; then
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local prompt_file="${script_dir}/../prompts/propagate.md"

  if [[ ! -f "$prompt_file" ]]; then
    echo "Warning: Claude agent prompt not found at ${prompt_file}" >&2
    echo "Skipping intelligent adaptation phase." >&2
    return 0
  fi

  if ! command -v claude &>/dev/null; then
    echo ""
    echo "Claude Code is not available on this machine."
    echo "Install it to run the intelligent adaptation phase:"
    echo "  npm install -g @anthropic-ai/claude-code"
    echo ""
    echo "Then re-run without --mechanical-only:"
    echo "  ./scripts/propagate.sh"
    return 0
  fi

  echo ""
  echo "Launching Claude agent for intelligent adaptation..."
  claude --print "$(cat "$prompt_file")"
}

# --- Main ---

restore_global_config
restore_commands
restore_skills
restore_plugins
restore_history
display_shell_fragments
print_summary
invoke_claude_agent
