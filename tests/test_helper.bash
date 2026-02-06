# ABOUTME: Shared setup/teardown for bats tests. Creates isolated fake HOME
# ABOUTME: with Claude Code fixtures for testing collect and propagate scripts.

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  FAKE_HOME="${TEST_TEMP_DIR}/home"
  mkdir -p "$FAKE_HOME"

  export HOME="$FAKE_HOME"
  export CCSNAPSHOT_OUTPUT_DIR="${TEST_TEMP_DIR}/snapshot-output"
  export CCSNAPSHOT_INPUT_DIR="${TEST_TEMP_DIR}/snapshot-input"
}

teardown() {
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# Copy fixture files into the fake HOME to simulate a real Claude Code installation.
# Translates fixture naming conventions to real paths:
#   fixtures/dot-claude/  →  ~/.claude/
#   fixtures/dot-claude-json  →  ~/.claude.json
#   fixtures/zshrc  →  ~/.zshrc
#   fixtures/bashrc  →  ~/.bashrc
#   fixtures/netrc  →  ~/.netrc
populate_global_fixtures() {
  if [[ -d "${FIXTURES_DIR}/dot-claude" ]]; then
    cp -R "${FIXTURES_DIR}/dot-claude" "${FAKE_HOME}/.claude"
  fi
  if [[ -f "${FIXTURES_DIR}/dot-claude-json" ]]; then
    cp "${FIXTURES_DIR}/dot-claude-json" "${FAKE_HOME}/.claude.json"
  fi
  if [[ -f "${FIXTURES_DIR}/zshrc" ]]; then
    cp "${FIXTURES_DIR}/zshrc" "${FAKE_HOME}/.zshrc"
  fi
  if [[ -f "${FIXTURES_DIR}/bashrc" ]]; then
    cp "${FIXTURES_DIR}/bashrc" "${FAKE_HOME}/.bashrc"
  fi
  if [[ -f "${FIXTURES_DIR}/netrc" ]]; then
    cp "${FIXTURES_DIR}/netrc" "${FAKE_HOME}/.netrc"
  fi
}

# Run collect against fixtures to produce a snapshot for propagate tests.
# Populates CCSNAPSHOT_INPUT_DIR with a valid snapshot.
create_snapshot_from_fixtures() {
  populate_global_fixtures
  local saved_output="${CCSNAPSHOT_OUTPUT_DIR}"
  export CCSNAPSHOT_OUTPUT_DIR="${CCSNAPSHOT_INPUT_DIR}"
  "${PROJECT_ROOT}/scripts/collect.sh" "$@" >/dev/null 2>&1
  export CCSNAPSHOT_OUTPUT_DIR="${saved_output}"
  # Reset HOME to a clean state for propagation
  rm -rf "${FAKE_HOME}"
  mkdir -p "${FAKE_HOME}"
}

# Copy a fixture project directory into the test temp area.
# Returns the path to the copied project.
populate_project_fixture() {
  local project_name="$1"
  local dest="${TEST_TEMP_DIR}/projects/${project_name}"
  mkdir -p "$dest"
  cp -R "${FIXTURES_DIR}/${project_name}/." "$dest/"
  echo "$dest"
}
