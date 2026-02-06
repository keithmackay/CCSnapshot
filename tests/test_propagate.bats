#!/usr/bin/env bats
# ABOUTME: Tests for the CCSnapshot propagate script.
# ABOUTME: Uses bats-core with fake HOME and fixture data.

load test_helper

PROPAGATE_SCRIPT="${PROJECT_ROOT}/scripts/propagate.sh"

@test "test helper setup creates isolated environment" {
  [[ -d "$FAKE_HOME" ]]
  [[ -n "$CCSNAPSHOT_INPUT_DIR" ]]
}

# --- Phase 8: Mechanical propagation ---

@test "propagate exits 0 with valid snapshot" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ "$status" -eq 0 ]]
}

@test "propagate restores global CLAUDE.md" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ -f "${FAKE_HOME}/.claude/CLAUDE.md" ]]
  diff "${CCSNAPSHOT_INPUT_DIR}/global/CLAUDE.md" "${FAKE_HOME}/.claude/CLAUDE.md"
}

@test "propagate restores global settings.json" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ -f "${FAKE_HOME}/.claude/settings.json" ]]
  diff "${CCSNAPSHOT_INPUT_DIR}/global/settings.json" "${FAKE_HOME}/.claude/settings.json"
}

@test "propagate restores claude.json to home directory" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ -f "${FAKE_HOME}/.claude.json" ]]
  diff "${CCSNAPSHOT_INPUT_DIR}/global/claude.json" "${FAKE_HOME}/.claude.json"
}

@test "propagate restores command files" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ -f "${FAKE_HOME}/.claude/commands/bootstrap.md" ]]
  [[ -f "${FAKE_HOME}/.claude/commands/review.md" ]]
}

@test "propagate restores skill directories" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ -d "${FAKE_HOME}/.claude/skills/sample-skill" ]]
  [[ -f "${FAKE_HOME}/.claude/skills/sample-skill/skill.md" ]]
}

@test "propagate restores plugin files" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ -f "${FAKE_HOME}/.claude/plugins/installed_plugins.json" ]]
}

@test "propagate fails without manifest.json" {
  mkdir -p "${CCSNAPSHOT_INPUT_DIR}"
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ "$status" -ne 0 ]]
  echo "$output" | grep -qi "manifest"
}

@test "propagate --mechanical-only flag is accepted" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ "$status" -eq 0 ]]
}

# --- Phase 8: Backup creation ---

@test "propagate creates backup when target file exists" {
  create_snapshot_from_fixtures
  # Pre-populate with existing content
  mkdir -p "${FAKE_HOME}/.claude"
  echo "existing content" > "${FAKE_HOME}/.claude/CLAUDE.md"
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ -f "${FAKE_HOME}/.claude/CLAUDE.md.bak" ]]
  grep -q "existing content" "${FAKE_HOME}/.claude/CLAUDE.md.bak"
}

@test "propagate overwrites target with snapshot content after backup" {
  create_snapshot_from_fixtures
  mkdir -p "${FAKE_HOME}/.claude"
  echo "old content" > "${FAKE_HOME}/.claude/CLAUDE.md"
  run "$PROPAGATE_SCRIPT" --mechanical-only
  diff "${CCSNAPSHOT_INPUT_DIR}/global/CLAUDE.md" "${FAKE_HOME}/.claude/CLAUDE.md"
}

@test "propagate does not create backup when target does not exist" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  [[ ! -f "${FAKE_HOME}/.claude/CLAUDE.md.bak" ]]
}

# --- Phase 9: Shell fragment display and summary ---

@test "propagate displays shell fragments" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  echo "$output" | grep -qi "shell fragment"
  echo "$output" | grep -q "ANTHROPIC_API_KEY"
}

@test "propagate displays propagation summary" {
  create_snapshot_from_fixtures
  run "$PROPAGATE_SCRIPT" --mechanical-only
  echo "$output" | grep -q "CCSnapshot"
  echo "$output" | grep -qi "restored"
}
