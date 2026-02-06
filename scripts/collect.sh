#!/usr/bin/env bash
# ABOUTME: Collects Claude Code personalizations into a portable snapshot directory.
# ABOUTME: Deterministic, no LLM — scans known locations and copies artifacts.

set -euo pipefail

OUTPUT_DIR="${CCSNAPSHOT_OUTPUT_DIR:-./snapshot}"

# --- Argument parsing ---

PROJECT_PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      if [[ -n "${2:-}" ]]; then
        PROJECT_PATHS+=("$2")
        shift 2
      else
        echo "Error: --project requires a path argument" >&2
        exit 1
      fi
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

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

# --- Project collection ---

COLLECTED_PROJECTS="[]"

collect_projects() {
  if [[ ${#PROJECT_PATHS[@]} -eq 0 ]]; then
    return 0
  fi

  for project_path in "${PROJECT_PATHS[@]}"; do
    if [[ ! -d "$project_path" ]]; then
      echo "Warning: project path does not exist, skipping: $project_path" >&2
      continue
    fi

    local project_name
    project_name=$(basename "$project_path")
    local dest="${OUTPUT_DIR}/projects/${project_name}"
    mkdir -p "$dest"

    if [[ -f "${project_path}/CLAUDE.md" ]]; then
      cp "${project_path}/CLAUDE.md" "${dest}/CLAUDE.md"
    fi

    if [[ -d "${project_path}/.claude" ]]; then
      rsync -a --exclude '.DS_Store' "${project_path}/.claude/" "${dest}/.claude/"
    fi

    COLLECTED_PROJECTS=$(echo "$COLLECTED_PROJECTS" | jq \
      --arg name "$project_name" \
      --arg path "$project_path" \
      '. + [{"name": $name, "sourcePath": $path}]')
  done
}

# --- Secrets detection ---

# Scan shell fragments and netrc for secret references.
# Records names and locations only — never values.
# Outputs a JSON array of {name, location} objects.
detect_secrets() {
  local secrets_json="[]"

  # Scan shell fragment files for secret-like exports
  if [[ -d "${OUTPUT_DIR}/shell-fragments" ]]; then
    for fragment in "${OUTPUT_DIR}/shell-fragments"/*.fragment; do
      [[ -f "$fragment" ]] || continue
      while IFS= read -r line; do
        # Skip annotation lines
        [[ "$line" =~ ^#\ source: ]] && continue
        # Look for export VAR_NAME patterns with KEY/TOKEN/SECRET in the name
        if echo "$line" | grep -qE 'export\s+\w*(API_KEY|TOKEN|SECRET)\w*='; then
          local var_name
          var_name=$(echo "$line" | grep -oE '\w*(API_KEY|TOKEN|SECRET)\w*' | head -1)
          secrets_json=$(echo "$secrets_json" | jq --arg name "$var_name" --arg loc "shell_config" \
            '. + [{"name": $name, "location": $loc}]')
        fi
      done < "$fragment"
    done
  fi

  # Scan netrc for anthropic/github entries
  if [[ -f "${HOME}/.netrc" ]]; then
    while IFS= read -r line; do
      if echo "$line" | grep -q 'machine'; then
        local machine
        machine=$(echo "$line" | awk '{print $2}')
        if [[ -n "$machine" ]]; then
          secrets_json=$(echo "$secrets_json" | jq --arg name "netrc:${machine}" --arg loc "netrc" \
            '. + [{"name": $name, "location": $loc}]')
        fi
      fi
    done < "${HOME}/.netrc"
  fi

  # Deduplicate by name
  echo "$secrets_json" | jq 'unique_by(.name)'
}

# --- Manifest generation ---

generate_manifest() {
  mkdir -p "${OUTPUT_DIR}"

  local secrets_json
  secrets_json=$(detect_secrets)

  # Build artifacts object based on what was actually collected
  local artifacts="{}"

  if [[ -d "${OUTPUT_DIR}/global" ]]; then
    local global_files
    global_files=$(ls "${OUTPUT_DIR}/global/" 2>/dev/null | jq -R . | jq -s .)
    artifacts=$(echo "$artifacts" | jq --argjson files "$global_files" '.global = $files')
  fi

  if [[ -d "${OUTPUT_DIR}/commands" ]]; then
    local cmd_files
    cmd_files=$(ls "${OUTPUT_DIR}/commands/" 2>/dev/null | jq -R . | jq -s .)
    artifacts=$(echo "$artifacts" | jq --argjson files "$cmd_files" '.commands = $files')
  fi

  if [[ -d "${OUTPUT_DIR}/skills" ]]; then
    local skill_dirs
    skill_dirs=$(ls "${OUTPUT_DIR}/skills/" 2>/dev/null | jq -R . | jq -s .)
    artifacts=$(echo "$artifacts" | jq --argjson files "$skill_dirs" '.skills = $files')
  fi

  if [[ -d "${OUTPUT_DIR}/plugins" ]]; then
    artifacts=$(echo "$artifacts" | jq '.plugins = true')
  fi

  if [[ -d "${OUTPUT_DIR}/shell-fragments" ]]; then
    local frag_files
    frag_files=$(ls "${OUTPUT_DIR}/shell-fragments/" 2>/dev/null | jq -R . | jq -s .)
    artifacts=$(echo "$artifacts" | jq --argjson files "$frag_files" '.shellFragments = $files')
  fi

  if [[ "$(echo "$COLLECTED_PROJECTS" | jq 'length')" -gt 0 ]]; then
    artifacts=$(echo "$artifacts" | jq --argjson projects "$COLLECTED_PROJECTS" '.projects = $projects')
  fi

  local source_os
  source_os=$(uname -s | tr '[:upper:]' '[:lower:]')

  local source_shell
  source_shell=$(basename "${SHELL:-unknown}")

  local claude_path
  claude_path=$(command -v claude 2>/dev/null || echo "not found")

  local collected_at
  collected_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq -n \
    --arg version "1.0" \
    --arg sourceOS "$source_os" \
    --arg sourceShell "$source_shell" \
    --arg claudeInstallPath "$claude_path" \
    --arg collectedAt "$collected_at" \
    --argjson artifacts "$artifacts" \
    --argjson secretsNeeded "$secrets_json" \
    '{
      version: $version,
      sourceOS: $sourceOS,
      sourceShell: $sourceShell,
      claudeInstallPath: $claudeInstallPath,
      collectedAt: $collectedAt,
      artifacts: $artifacts,
      secretsNeeded: $secretsNeeded
    }' > "${OUTPUT_DIR}/manifest.json"
}

# --- Summary output ---

print_summary() {
  local global_count=0
  local cmd_count=0
  local skill_count=0
  local plugin_status="-"
  local fragment_count=0
  local project_count=0
  local secret_count=0

  if [[ -d "${OUTPUT_DIR}/global" ]]; then
    global_count=$(ls "${OUTPUT_DIR}/global/" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ -d "${OUTPUT_DIR}/commands" ]]; then
    cmd_count=$(ls "${OUTPUT_DIR}/commands/" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ -d "${OUTPUT_DIR}/skills" ]]; then
    skill_count=$(ls "${OUTPUT_DIR}/skills/" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ -d "${OUTPUT_DIR}/plugins" ]]; then
    plugin_status="collected"
  fi
  if [[ -d "${OUTPUT_DIR}/shell-fragments" ]]; then
    fragment_count=$(ls "${OUTPUT_DIR}/shell-fragments/" 2>/dev/null | wc -l | tr -d ' ')
  fi
  project_count=$(echo "$COLLECTED_PROJECTS" | jq 'length')
  if [[ -f "${OUTPUT_DIR}/manifest.json" ]]; then
    secret_count=$(jq '.secretsNeeded | length' "${OUTPUT_DIR}/manifest.json")
  fi

  echo ""
  echo "CCSnapshot: Collection complete"
  echo "  Global config:   ${global_count} files"
  echo "  Commands:        ${cmd_count} files"
  echo "  Skills:          ${skill_count} directories"
  echo "  Plugins:         ${plugin_status}"
  echo "  Shell fragments: ${fragment_count} files"
  echo "  Projects:        ${project_count}"
  if [[ "$secret_count" -gt 0 ]]; then
    echo "  Secrets found:   ${secret_count} (recorded in manifest, values NOT collected)"
  fi
  echo "  Manifest:        ${OUTPUT_DIR}/manifest.json"
}

# --- Main ---

# Clean previous snapshot for idempotency
if [[ -d "$OUTPUT_DIR" ]]; then
  rm -rf "$OUTPUT_DIR"
fi

collect_global_config
collect_commands
collect_skills
collect_plugins
collect_shell_fragments
collect_projects
generate_manifest
print_summary
