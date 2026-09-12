#!/usr/bin/env bash
# ABOUTME: Packages a full snapshot (including conversation history) into a local archive.
# ABOUTME: No git, no network — the resulting file is meant for direct machine-to-machine transfer.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH=""

# --- Argument parsing ---

ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ -n "${2:-}" ]]; then
        OUTPUT_PATH="$2"
        shift 2
      else
        echo "Error: --output requires a path argument" >&2
        exit 1
      fi
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$OUTPUT_PATH" ]]; then
  timestamp=$(date +%Y%m%d-%H%M%S)
  host=$(hostname -s 2>/dev/null || echo "machine")
  OUTPUT_PATH="./ccsnapshot-${host}-${timestamp}.tar.gz"
fi

if [[ ${#ARGS[@]} -gt 0 ]]; then
  "${SCRIPT_DIR}/collect.sh" --include-history "${ARGS[@]}"
else
  "${SCRIPT_DIR}/collect.sh" --include-history
fi

tar -czf "$OUTPUT_PATH" -C snapshot .

echo ""
echo "CCSnapshot: Archive created"
echo "  Path: $(cd "$(dirname "$OUTPUT_PATH")" && pwd)/$(basename "$OUTPUT_PATH")"
echo ""
echo "This archive contains full Claude Code conversation history and config."
echo "Transfer it directly to the destination machine (AirDrop, USB, scp) —"
echo "do NOT commit it to git or upload it to cloud storage."
echo "On the destination machine, run: ./scripts/propagate.sh --archive <path>"
echo "Delete the archive from both machines once the restore is confirmed."
