#!/usr/bin/env bash
# ABOUTME: Restores Claude Code personalizations from a snapshot directory.
# ABOUTME: Mechanical file copy with backups, optional Claude agent for adaptation.

set -euo pipefail

INPUT_DIR="${CCSNAPSHOT_INPUT_DIR:-./snapshot}"
MECHANICAL_ONLY=false
ARCHIVE_PATH=""
MD_CONFLICTS=()
SKIPPED_ENTRIES=()
RELINKED_SKILLS=()
MISSING_SKILL_LINKS=()

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

# true if $1 matches one of the remaining args. Written to avoid expanding a
# possibly-empty array with "${arr[@]}", which bash 3.2 (macOS's default)
# treats as an unbound variable under `set -u`.
array_contains() {
  local needle="$1"
  shift
  [[ "$#" -eq 0 ]] && return 1
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Sync src_dir's top-level entries into dest_dir, except entries whose type
# (symlink vs directory/file) differs from what's already at that name in
# dest_dir. A symlink from the source machine (e.g. a skill linked into a
# project directory) usually encodes a host-specific path that won't resolve
# here, so blindly swapping it in for a real, working local directory would
# replace working content with a dangling link. Conflicting entries are left
# untouched and recorded in SKIPPED_ENTRIES for the user to review.
#
# Any extra args name entries the caller already handled itself (e.g.
# restore_skills resolving symlinks individually) — these are excluded from
# the rsync and skipped by the conflict scan so they aren't reported twice.
sync_top_level_skip_conflicts() {
  local label="$1"
  local src_dir="$2"
  local dest_dir="$3"
  shift 3
  local already_handled=("$@")

  mkdir -p "$dest_dir"

  local exclude_args=()
  local h
  if [[ "${#already_handled[@]}" -gt 0 ]]; then
    for h in "${already_handled[@]}"; do
      exclude_args+=(--exclude "/${h}")
    done
  fi

  local entry name dest_path
  for entry in "$src_dir"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name=$(basename "$entry")
    array_contains "$name" "${already_handled[@]-}" && continue
    dest_path="${dest_dir}/${name}"

    if [[ -e "$dest_path" || -L "$dest_path" ]]; then
      if [[ -L "$entry" && ! -L "$dest_path" ]] || [[ ! -L "$entry" && -L "$dest_path" ]]; then
        exclude_args+=(--exclude "/${name}")
        SKIPPED_ENTRIES+=("${label}/${name}")
      fi
    fi
  done

  if [[ "${#exclude_args[@]}" -gt 0 ]]; then
    rsync -a --exclude '.DS_Store' "${exclude_args[@]}" "${src_dir}/" "${dest_dir}/"
  else
    rsync -a --exclude '.DS_Store' "${src_dir}/" "${dest_dir}/"
  fi
}

restore_commands() {
  if [[ -d "${INPUT_DIR}/commands" ]] && [[ -n "$(ls -A "${INPUT_DIR}/commands" 2>/dev/null)" ]]; then
    sync_top_level_skip_conflicts "commands" "${INPUT_DIR}/commands" "${HOME}/.claude/commands"
  fi
}

# Resolve a skill symlink's original (source-machine) target to its
# equivalent path on this machine, and link there instead of copying the raw
# (host-specific, likely broken) symlink through:
#   - an absolute target (e.g. /Users/otheruser/Projects/foo/skill) is
#     rewritten onto this machine's $HOME, assuming the same two-level home
#     directory depth (/Users/<name> or /home/<name>) on both machines
#   - a relative target (e.g. ../../.agents/skills/foo) is resolved relative
#     to this machine's own ~/.claude/skills, same as the symlink would have
# If nothing exists at the resolved path, nothing is written for this skill —
# a dangling symlink would be worse than no skill at all — and it's recorded
# in MISSING_SKILL_LINKS for the user to review.
relink_skill_entry() {
  local name="$1"
  local target="$2"
  local dest_path="$3"

  local candidate link_target
  if [[ "$target" == /* ]]; then
    candidate="${HOME}/$(echo "$target" | cut -d/ -f4-)"
    link_target="$candidate"
  else
    candidate=$(cd "$(dirname "$dest_path")" 2>/dev/null && cd "$(dirname "$target")" 2>/dev/null && pwd || true)
    [[ -n "$candidate" ]] && candidate="${candidate}/$(basename "$target")"
    link_target="$target"
  fi

  if [[ -n "$candidate" && -e "$candidate" ]]; then
    ln -s "$link_target" "$dest_path"
    RELINKED_SKILLS+=("${name} -> ${link_target}")
  else
    MISSING_SKILL_LINKS+=("${name} (was linked to ${target} on the source machine)")
  fi
}

# Skills are often symlinked into a project directory or a shared skills
# farm on the source machine — those targets are host-specific and won't
# resolve here, so they can't be synced like an ordinary file. For each
# symlinked skill entry, try to re-create the equivalent link on this
# machine (see relink_skill_entry) rather than copying the raw symlink.
# A name that already exists locally — real content or a previous link —
# is left untouched and reported in SKIPPED_ENTRIES, same as any other
# type conflict (see sync_top_level_skip_conflicts).
restore_skills() {
  local src_dir="${INPUT_DIR}/skills"
  local dest_dir="${HOME}/.claude/skills"

  if [[ ! -d "$src_dir" ]] || [[ -z "$(ls -A "$src_dir" 2>/dev/null)" ]]; then
    return 0
  fi

  mkdir -p "$dest_dir"

  local handled_names=()
  local entry name dest_path
  for entry in "$src_dir"/*; do
    [[ -L "$entry" ]] || continue
    name=$(basename "$entry")
    dest_path="${dest_dir}/${name}"
    handled_names+=("$name")

    if [[ -e "$dest_path" || -L "$dest_path" ]]; then
      SKIPPED_ENTRIES+=("skills/${name}")
      continue
    fi

    relink_skill_entry "$name" "$(readlink "$entry")" "$dest_path"
  done

  if [[ "${#handled_names[@]}" -gt 0 ]]; then
    sync_top_level_skip_conflicts "skills" "$src_dir" "$dest_dir" "${handled_names[@]}"
  else
    sync_top_level_skip_conflicts "skills" "$src_dir" "$dest_dir"
  fi
}

restore_plugins() {
  if [[ -d "${INPUT_DIR}/plugins" ]] && [[ -n "$(ls -A "${INPUT_DIR}/plugins" 2>/dev/null)" ]]; then
    sync_top_level_skip_conflicts "plugins" "${INPUT_DIR}/plugins" "${HOME}/.claude/plugins"
  fi
}

# Copy an incoming session transcript into place. If a session with the same
# id already has local history that diverges, back up the local file and
# merge in any lines from the incoming transcript that aren't already present,
# so work continued independently on this machine is preserved alongside it.
merge_session_file() {
  local src="$1"
  local dest="$2"

  if [[ ! -f "$dest" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    return 0
  fi

  if cmp -s "$src" "$dest"; then
    return 0
  fi

  cp "$dest" "${dest}.bak"
  awk '!seen[$0]++' "$dest" "$src" > "${dest}.merge-tmp"
  mv "${dest}.merge-tmp" "$dest"
}

# Copy an incoming markdown note (memory, project instructions, etc.) into
# place. If a local version already exists and differs, back it up and let
# the incoming version take over mechanically — semantic reconciliation of
# the two happens later in the Claude agent phase, gated the same as every
# other intelligent-adaptation step (see invoke_claude_agent).
restore_markdown_file() {
  local src="$1"
  local dest="$2"

  if [[ ! -f "$dest" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    return 0
  fi

  if cmp -s "$src" "$dest"; then
    return 0
  fi

  cp "$dest" "${dest}.bak"
  cp "$src" "$dest"
  MD_CONFLICTS+=("$dest")
}

restore_history() {
  local history_dir="${INPUT_DIR}/history"

  if [[ ! -d "$history_dir" ]] || [[ -z "$(ls -A "$history_dir" 2>/dev/null)" ]]; then
    return 0
  fi

  mkdir -p "${HOME}/.claude/projects"

  while IFS= read -r -d '' src_file; do
    local rel_path="${src_file#"$history_dir"/}"
    merge_session_file "$src_file" "${HOME}/.claude/projects/${rel_path}"
  done < <(find "$history_dir" -name '*.jsonl' -type f -print0)

  while IFS= read -r -d '' src_file; do
    local rel_path="${src_file#"$history_dir"/}"
    restore_markdown_file "$src_file" "${HOME}/.claude/projects/${rel_path}"
  done < <(find "$history_dir" -name '*.md' -type f -print0)

  rsync -a --exclude '.DS_Store' --exclude '*.jsonl' --exclude '*.md' "${history_dir}/" "${HOME}/.claude/projects/"
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

# --- Markdown conflict display ---

display_markdown_conflicts() {
  if [[ "${#MD_CONFLICTS[@]}" -eq 0 ]]; then
    return 0
  fi

  echo ""
  if [[ "$MECHANICAL_ONLY" == true ]]; then
    echo "Memory/notes files with local edits (incoming version kept, local backed up to .bak):"
  else
    echo "Memory/notes files with local edits (Claude agent will reconcile these next):"
  fi
  echo "----------------------------------------------------------------------"
  for file in "${MD_CONFLICTS[@]}"; do
    echo "  ${file}"
    echo "    review: diff \"${file}.bak\" \"${file}\""
  done
  echo "----------------------------------------------------------------------"
  echo ""
}

# --- Skill relink display ---

display_skill_links() {
  if [[ "${#RELINKED_SKILLS[@]}" -eq 0 ]] && [[ "${#MISSING_SKILL_LINKS[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ "${#RELINKED_SKILLS[@]}" -gt 0 ]]; then
    echo ""
    echo "Skills re-linked to their equivalent local target:"
    local entry
    for entry in "${RELINKED_SKILLS[@]}"; do
      echo "  ${entry}"
    done
  fi

  if [[ "${#MISSING_SKILL_LINKS[@]}" -gt 0 ]]; then
    echo ""
    echo "Skills that were symlinks on the source machine but have no equivalent here"
    echo "(not restored — a dangling link would be worse than no skill):"
    local entry
    for entry in "${MISSING_SKILL_LINKS[@]}"; do
      echo "  ${entry}"
    done
  fi
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
  if [[ "${#MD_CONFLICTS[@]}" -gt 0 ]]; then
    echo "  Memory/notes:    ${#MD_CONFLICTS[@]} file(s) with local edits (see above)"
  fi
  if [[ "${#SKIPPED_ENTRIES[@]}" -gt 0 ]]; then
    echo "  Skipped:         ${#SKIPPED_ENTRIES[@]} entries (symlink/directory type conflict — local kept)"
    local skipped
    for skipped in "${SKIPPED_ENTRIES[@]}"; do
      echo "                     ${skipped}"
    done
  fi
  if [[ "${#RELINKED_SKILLS[@]}" -gt 0 ]] || [[ "${#MISSING_SKILL_LINKS[@]}" -gt 0 ]]; then
    echo "  Skill links:     ${#RELINKED_SKILLS[@]} re-linked, ${#MISSING_SKILL_LINKS[@]} unresolved (see above)"
  fi
  if [[ "$backup_count" -gt 0 ]]; then
    echo "  Backups:         ${backup_count} files backed up (.bak)"
  fi
  if [[ -d "${INPUT_DIR}/shell-fragments" ]]; then
    echo "  Shell fragments: displayed above (manual merge needed)"
  fi
}

# --- Review file ---

# Write everything that needs a human look (skipped entries, unresolved
# skill links, markdown conflicts) to a plain-text file, since the terminal
# output otherwise only exists for the length of this run.
write_review_file() {
  local out="$1"

  {
    echo "CCSnapshot: Propagation review — $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""

    if [[ "${#MD_CONFLICTS[@]}" -gt 0 ]]; then
      echo "Memory/notes files with local edits:"
      local file
      for file in "${MD_CONFLICTS[@]}"; do
        echo "  ${file}"
        echo "    review: diff \"${file}.bak\" \"${file}\""
      done
      echo ""
    fi

    if [[ "${#SKIPPED_ENTRIES[@]}" -gt 0 ]]; then
      echo "Skipped entries (symlink/directory type conflict — local kept):"
      local entry
      for entry in "${SKIPPED_ENTRIES[@]}"; do
        echo "  ${entry}"
      done
      echo ""
    fi

    if [[ "${#RELINKED_SKILLS[@]}" -gt 0 ]]; then
      echo "Skills re-linked to their equivalent local target:"
      for entry in "${RELINKED_SKILLS[@]}"; do
        echo "  ${entry}"
      done
      echo ""
    fi

    if [[ "${#MISSING_SKILL_LINKS[@]}" -gt 0 ]]; then
      echo "Skills that were symlinks on the source machine but have no equivalent here:"
      for entry in "${MISSING_SKILL_LINKS[@]}"; do
        echo "  ${entry}"
      done
      echo ""
    fi
  } > "$out"

  echo "Review written to: ${out}"
}

# Ask before writing anything — but only when there's something worth
# reviewing, and only when a human is actually at the terminal to answer.
prompt_write_review() {
  if [[ "${#MD_CONFLICTS[@]}" -eq 0 ]] && [[ "${#SKIPPED_ENTRIES[@]}" -eq 0 ]] && [[ "${#MISSING_SKILL_LINKS[@]}" -eq 0 ]]; then
    return 0
  fi

  [[ -t 0 ]] || return 0

  local answer
  read -r -p "Write the items above to a file for later review? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || return 0

  local host
  host=$(hostname -s 2>/dev/null || echo "machine")
  write_review_file "./ccsnapshot-review-${host}-$(date -u +"%Y%m%d-%H%M%S").txt"
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
display_markdown_conflicts
display_skill_links
print_summary
prompt_write_review
invoke_claude_agent
