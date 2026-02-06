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
