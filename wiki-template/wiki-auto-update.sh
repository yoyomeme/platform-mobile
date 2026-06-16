#!/usr/bin/env bash
# wiki/wiki-auto-update.sh — Daily automation driver for wiki sync
#
# Usage:
#   ./wiki/wiki-auto-update.sh          — Detect changes, output report
#   ./wiki/wiki-auto-update.sh refresh  — Refresh hash baseline after wiki update
#
# This script bridges the bash detection layer and Claude's wiki-update capability.
# The daily /loop calls this script, then Claude reads the output and updates pages.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect: run hash diff, map to wiki pages, output actionable report
do_detect() {
  local diff_output
  diff_output=$(bash "$SCRIPT_DIR/wiki-hash.sh" diff 2>/dev/null)

  local has_changes
  has_changes=$(echo "$diff_output" | grep '"has_changes"' | grep -o 'true' || echo "false")

  local today
  today=$(date +%Y-%m-%d)

  if [ "$has_changes" != "true" ]; then
    echo "WIKI_STATUS: current"
    echo "DATE: $today"
    echo ""
    echo "All wiki pages are up to date with the source codebase."
    echo "No action needed."
    return 0
  fi

  # Extract changed/added/removed file counts
  local n_changed n_added n_removed
  n_changed=$(echo "$diff_output" | grep '"changed_count"' | grep -o '[0-9]*')
  n_added=$(echo "$diff_output" | grep '"added_count"' | grep -o '[0-9]*')
  n_removed=$(echo "$diff_output" | grep '"removed_count"' | grep -o '[0-9]*')

  # Run sync check to get affected pages
  local sync_output
  sync_output=$(bash "$SCRIPT_DIR/wiki-sync.sh" check 2>/dev/null)

  echo "WIKI_STATUS: stale"
  echo "DATE: $today"
  echo "CHANGED_FILES: $n_changed"
  echo "ADDED_FILES: $n_added"
  echo "REMOVED_FILES: $n_removed"
  echo ""
  echo "$sync_output"
  echo ""
  echo "---"
  echo "ACTION_REQUIRED: true"
  echo "INSTRUCTIONS:"
  echo "  1. Read each affected wiki page listed above"
  echo "  2. Read the changed source files listed above"
  echo "  3. Update wiki pages to reflect source changes"
  echo "  4. Run: bash wiki/wiki-auto-update.sh refresh"
  echo "  5. Append entry to wiki/log.md"
}

# Refresh: update hash baseline after wiki pages are updated
do_refresh() {
  echo "Refreshing hash baseline..."
  bash "$SCRIPT_DIR/wiki-hash.sh" snapshot
  echo ""
  echo "Hash baseline updated. Wiki is now in sync."
}

# Main
case "${1:-detect}" in
  detect)  do_detect ;;
  refresh) do_refresh ;;
  *)
    echo "Usage: $0 {detect|refresh}"
    echo ""
    echo "  detect  — Check for stale wiki pages, output report (default)"
    echo "  refresh — Update hash baseline after wiki pages are updated"
    ;;
esac
