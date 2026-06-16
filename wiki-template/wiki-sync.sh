#!/usr/bin/env bash
# wiki/wiki-sync.sh — Auto-sync: detect stale wiki pages and trigger updates
#
# Usage:
#   ./wiki/wiki-sync.sh check       — Run hash detection, output stale page report
#   ./wiki/wiki-sync.sh update      — Refresh snapshot after wiki pages are updated
#   ./wiki/wiki-sync.sh report      — Generate markdown report for wiki/log.md

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAP_FILE="$SCRIPT_DIR/.file-wiki-map.tsv"

# Ensure the mapping file exists
if [ ! -f "$MAP_FILE" ]; then
  echo "Error: $MAP_FILE not found. Create it with source-file to wiki-page mappings." >&2
  exit 1
fi

# Map a single file to its wiki pages using the TSV file
# Outputs one wiki page path per line
map_file_to_pages() {
  local filepath="$1"
  local result=""
  while IFS=$'\t' read -r prefix page; do
    [ -z "$prefix" ] && continue
    case "$filepath" in
      $prefix*)
        result="$result $page"
        ;;
    esac
  done < "$MAP_FILE"

  # Always include overview.md for any source change
  if [ -n "$result" ]; then
    result="$result overview.md"
  fi
  echo "$result" | tr ' ' '\n' | sort -u | grep -v '^$'
}

# Check: run hash diff and map to wiki pages
do_check() {
  local diff_output
  diff_output=$(bash "$SCRIPT_DIR/wiki-hash.sh" diff 2>/dev/null)

  local has_changes
  has_changes=$(echo "$diff_output" | grep '"has_changes"' | grep -o 'true' || echo "false")

  if [ "$has_changes" != "true" ]; then
    echo "# Wiki Sync: No Changes Detected"
    echo ""
    echo "All wiki pages are up to date with the source codebase."
    echo "Last check: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    return 0
  fi

  # Extract changed files from JSON
  local all_files
  all_files=$(
    echo "$diff_output" \
      | awk '/"changed":/,/\]/{print} /"added":/,/\]/{print} /"removed":/,/\]/{print}' \
      | grep '"' \
      | awk -F'"' '{print $2}' \
      | grep -v 'changed\|added\|removed\|count' \
      | grep '/' \
      | sort -u
  )

  if [ -z "$all_files" ]; then
    echo "# Wiki Sync: No Changes Detected"
    return 0
  fi

  # Map files to pages using a temp file to avoid subshell issues
  local pages_tmp
  pages_tmp=$(mktemp)
  while IFS= read -r filepath; do
    [ -z "$filepath" ] && continue
    map_file_to_pages "$filepath" >> "$pages_tmp"
  done <<< "$all_files"

  local affected_pages
  affected_pages=$(sort -u "$pages_tmp")
  rm -f "$pages_tmp"

  # Count
  local n_files n_pages
  n_files=$(echo "$all_files" | grep -c .)
  n_pages=$(echo "$affected_pages" | grep -c .)

  echo "# Wiki Sync: Changes Detected"
  echo ""
  echo "## Summary"
  echo "- Source files changed: $n_files"
  echo "- Wiki pages affected:  $n_pages"
  echo ""
  echo "## Affected Wiki Pages"
  echo "$affected_pages" | while IFS= read -r page; do
    [ -z "$page" ] && continue
    echo "- [ ] \`wiki/$page\`"
  done

  echo ""
  echo "## Changed Source Files"
  echo "$all_files" | while IFS= read -r filepath; do
    [ -z "$filepath" ] && continue
    echo "- \`$filepath\`"
  done

  echo ""
  echo "## Next Steps"
  echo "1. Read each affected wiki page"
  echo "2. Read the changed source files"
  echo "3. Update wiki pages to reflect source changes"
  echo "4. Run \`./wiki/wiki-sync.sh update\` to refresh the hash baseline"
  echo "5. Append to \`wiki/log.md\`"
}

# Update: refresh hash snapshot
do_update() {
  bash "$SCRIPT_DIR/wiki-hash.sh" snapshot
}

# Report: generate a log.md entry
do_report() {
  local diff_output
  diff_output=$(bash "$SCRIPT_DIR/wiki-hash.sh" diff 2>/dev/null)

  local has_changes n_changed n_added n_removed
  has_changes=$(echo "$diff_output" | grep '"has_changes"' | grep -o 'true\|false' || echo "false")
  n_changed=$(echo "$diff_output" | grep '"changed_count"' | grep -o '[0-9]*' || echo "0")
  n_added=$(echo "$diff_output" | grep '"added_count"' | grep -o '[0-9]*' || echo "0")
  n_removed=$(echo "$diff_output" | grep '"removed_count"' | grep -o '[0-9]*' || echo "0")
  local today
  today=$(date +%Y-%m-%d)

  if [ "$has_changes" = "true" ]; then
    echo ""
    echo "## [$today] sync | Stale pages detected"
    echo "- Source changes: $n_changed changed, $n_added added, $n_removed removed"
    echo "- Action: update affected wiki pages, then run \`./wiki/wiki-sync.sh update\`"
  else
    echo ""
    echo "## [$today] sync | All pages current"
    echo "- No changes detected"
  fi
}

# Main
case "${1:-help}" in
  check)  do_check ;;
  update) do_update ;;
  report) do_report ;;
  *)
    echo "Usage: $0 {check|update|report}"
    echo ""
    echo "  check   — Detect stale wiki pages, output affected pages"
    echo "  update  — Refresh hash snapshot after wiki is updated"
    echo "  report  — Generate log.md entry"
    ;;
esac
