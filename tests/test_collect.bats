#!/usr/bin/env bats
# ABOUTME: Tests for the CCSnapshot collect script.
# ABOUTME: Uses bats-core with fake HOME and fixture data.

load test_helper

@test "test helper setup creates isolated environment" {
  [[ -d "$FAKE_HOME" ]]
  [[ -d "$CCSNAPSHOT_OUTPUT_DIR" ]] || [[ -n "$CCSNAPSHOT_OUTPUT_DIR" ]]
}
