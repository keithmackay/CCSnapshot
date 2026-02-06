#!/usr/bin/env bats
# ABOUTME: Tests for the CCSnapshot propagate script.
# ABOUTME: Uses bats-core with fake HOME and fixture data.

load test_helper

@test "test helper setup creates isolated environment" {
  [[ -d "$FAKE_HOME" ]]
  [[ -d "$CCSNAPSHOT_INPUT_DIR" ]] || [[ -n "$CCSNAPSHOT_INPUT_DIR" ]]
}
