#!/usr/bin/env bats
# ABOUTME: Tests for the CCSnapshot collect script.
# ABOUTME: Uses bats-core with fake HOME and fixture data.

load test_helper

COLLECT_SCRIPT="${PROJECT_ROOT}/scripts/collect.sh"

@test "test helper setup creates isolated environment" {
  [[ -d "$FAKE_HOME" ]]
  [[ -n "$CCSNAPSHOT_OUTPUT_DIR" ]]
}

# --- Phase 1: Global config collection ---

@test "collect exits 0 with populated HOME" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ "$status" -eq 0 ]]
}

@test "collect copies global CLAUDE.md" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/global/CLAUDE.md" ]]
  diff "${FAKE_HOME}/.claude/CLAUDE.md" "${CCSNAPSHOT_OUTPUT_DIR}/global/CLAUDE.md"
}

@test "collect copies global settings.json" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/global/settings.json" ]]
  diff "${FAKE_HOME}/.claude/settings.json" "${CCSNAPSHOT_OUTPUT_DIR}/global/settings.json"
}

@test "collect copies claude.json from home directory" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/global/claude.json" ]]
  diff "${FAKE_HOME}/.claude.json" "${CCSNAPSHOT_OUTPUT_DIR}/global/claude.json"
}

@test "collect handles missing global CLAUDE.md gracefully" {
  populate_global_fixtures
  rm "${FAKE_HOME}/.claude/CLAUDE.md"
  run "$COLLECT_SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ ! -f "${CCSNAPSHOT_OUTPUT_DIR}/global/CLAUDE.md" ]]
}

@test "collect handles missing claude.json gracefully" {
  populate_global_fixtures
  rm "${FAKE_HOME}/.claude.json"
  run "$COLLECT_SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ ! -f "${CCSNAPSHOT_OUTPUT_DIR}/global/claude.json" ]]
}

@test "collect handles completely empty HOME" {
  # No fixtures populated — empty HOME
  run "$COLLECT_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# --- Phase 2: Commands and skills collection ---

@test "collect copies command files" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/commands/bootstrap.md" ]]
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/commands/review.md" ]]
  diff "${FAKE_HOME}/.claude/commands/bootstrap.md" "${CCSNAPSHOT_OUTPUT_DIR}/commands/bootstrap.md"
}

@test "collect copies skill directories" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -d "${CCSNAPSHOT_OUTPUT_DIR}/skills/sample-skill" ]]
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/skills/sample-skill/skill.md" ]]
  diff "${FAKE_HOME}/.claude/skills/sample-skill/skill.md" "${CCSNAPSHOT_OUTPUT_DIR}/skills/sample-skill/skill.md"
}

@test "collect skips commands dir when missing" {
  populate_global_fixtures
  rm -rf "${FAKE_HOME}/.claude/commands"
  run "$COLLECT_SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ ! -d "${CCSNAPSHOT_OUTPUT_DIR}/commands" ]]
}

@test "collect skips skills dir when missing" {
  populate_global_fixtures
  rm -rf "${FAKE_HOME}/.claude/skills"
  run "$COLLECT_SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ ! -d "${CCSNAPSHOT_OUTPUT_DIR}/skills" ]]
}

# --- Phase 3: Plugin collection ---

@test "collect copies installed_plugins.json" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/plugins/installed_plugins.json" ]]
  diff "${FAKE_HOME}/.claude/plugins/installed_plugins.json" "${CCSNAPSHOT_OUTPUT_DIR}/plugins/installed_plugins.json"
}

@test "collect copies plugin cache" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -d "${CCSNAPSHOT_OUTPUT_DIR}/plugins/cache/sample-plugin" ]]
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/plugins/cache/sample-plugin/index.js" ]]
}

@test "collect skips plugins dir when missing" {
  populate_global_fixtures
  rm -rf "${FAKE_HOME}/.claude/plugins"
  run "$COLLECT_SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ ! -d "${CCSNAPSHOT_OUTPUT_DIR}/plugins" ]]
}

# --- Phase 4: Shell fragment extraction ---

@test "collect extracts zshrc fragments" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/zshrc.fragment" ]]
  # Should contain Claude-related lines
  grep -q "ANTHROPIC_API_KEY" "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/zshrc.fragment"
  grep -q "claude-update" "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/zshrc.fragment"
  grep -q "CLAUDE_MODEL" "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/zshrc.fragment"
}

@test "collect extracts bashrc fragments" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/bashrc.fragment" ]]
  grep -q "ANTHROPIC_API_KEY" "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/bashrc.fragment"
}

@test "collect excludes non-matching lines from fragments" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  # Lines like "alias ll" and "export EDITOR" should NOT appear
  ! grep -q "alias ll" "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/zshrc.fragment"
  ! grep -q "EDITOR=vim" "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/zshrc.fragment"
  ! grep -q "JAVA_HOME" "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/bashrc.fragment"
}

@test "collect annotates fragment lines with source info" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  # Each matching line should have a source annotation
  grep -q "^# source:.*\.zshrc:" "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/zshrc.fragment"
}

@test "collect handles missing shell configs gracefully" {
  populate_global_fixtures
  rm -f "${FAKE_HOME}/.zshrc" "${FAKE_HOME}/.bashrc"
  run "$COLLECT_SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ ! -f "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/zshrc.fragment" ]]
  [[ ! -f "${CCSNAPSHOT_OUTPUT_DIR}/shell-fragments/bashrc.fragment" ]]
}

# --- Phase 5: Secrets detection and manifest generation ---

@test "collect generates manifest.json" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  [[ -f "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json" ]]
  # Must be valid JSON
  jq . "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json" >/dev/null
}

@test "manifest contains version 1.0" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  local version
  version=$(jq -r '.version' "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json")
  [[ "$version" == "1.0" ]]
}

@test "manifest contains sourceOS" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  local os
  os=$(jq -r '.sourceOS' "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json")
  [[ -n "$os" ]]
  [[ "$os" != "null" ]]
}

@test "manifest contains sourceShell" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  local shell
  shell=$(jq -r '.sourceShell' "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json")
  [[ -n "$shell" ]]
  [[ "$shell" != "null" ]]
}

@test "manifest contains collectedAt timestamp" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  local ts
  ts=$(jq -r '.collectedAt' "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json")
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "manifest lists collected artifacts" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  local artifacts
  artifacts=$(jq '.artifacts' "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json")
  [[ "$artifacts" != "null" ]]
  # Should have global section
  [[ "$(jq -r '.artifacts.global' "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json")" != "null" ]]
}

@test "manifest detects ANTHROPIC_API_KEY from shell fragments" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  local secrets
  secrets=$(jq '.secretsNeeded' "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json")
  echo "$secrets" | grep -q "ANTHROPIC_API_KEY"
}

@test "manifest detects netrc entries" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  local secrets
  secrets=$(jq -r '.secretsNeeded[].name' "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json")
  echo "$secrets" | grep -q "anthropic.com"
}

@test "manifest never contains secret values" {
  populate_global_fixtures
  run "$COLLECT_SCRIPT"
  # The fake API key should NOT appear anywhere in the manifest
  ! grep -q "sk-ant-FAKE" "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json"
  ! grep -q "ghp_FAKE" "${CCSNAPSHOT_OUTPUT_DIR}/manifest.json"
}
