#!/usr/bin/env bash
# wiki/wiki-hash.sh — SHA-256 change detection for wiki auto-sync
#
# Usage:
#   ./wiki/wiki-hash.sh snapshot   — Create/update .source-hashes.json baseline
#   ./wiki/wiki-hash.sh diff       — Compare current files against baseline (JSON)
#   ./wiki/wiki-hash.sh status     — Human-readable summary of changes
#
# Compatible with macOS bash 3.x (no associative arrays).
# SETUP: Edit TRACK_PATTERNS below to match your source layout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HASH_FILE="$REPO_ROOT/wiki/.source-hashes.json"

# ============================================
# EDIT THESE PATTERNS TO MATCH YOUR SOURCE CODE
# ============================================
TRACK_PATTERNS=(
  "{{SOURCE_PATTERNS}}"
  "docs/**/*.md"
)

# Build sorted list of tracked file paths (relative to repo root)
build_file_list() {
  for pattern in "${TRACK_PATTERNS[@]}"; do
    cd "$REPO_ROOT" && git ls-files -- "$pattern" 2>/dev/null || true
  done | grep -v '/.build/' | grep -v '/node_modules/' | grep -v '/dist/' | sort -u
}

# Snapshot: hash all files and write to .source-hashes.json
do_snapshot() {
  echo "Computing SHA-256 hashes for source files..."
  local tmpfile count
  tmpfile=$(mktemp)
  count=0

  echo "{" > "$tmpfile"

  first=true
  while IFS= read -r relpath; do
    [ -z "$relpath" ] && continue
    local hash
    hash=$(shasum -a 256 "$REPO_ROOT/$relpath" | awk '{print $1}')

    if [ "$first" = true ]; then
      first=false
    else
      echo "," >> "$tmpfile"
    fi
    printf '  "%s": "%s"' "$relpath" "$hash" >> "$tmpfile"
    count=$((count + 1))
  done < <(build_file_list)

  echo "" >> "$tmpfile"
  echo "}" >> "$tmpfile"

  mv "$tmpfile" "$HASH_FILE"
  echo "Snapshot saved: $count files hashed -> wiki/.source-hashes.json"
}

# Parse JSON into "path<TAB>hash" format (no associative arrays needed)
json_to_tsv() {
  grep -E '^\s*".+":.*".*"' "$1" | awk -F'"' '{printf "%s\t%s\n", $2, $4}' | sort
}

# Diff: compare current state against stored hashes using join
do_diff() {
  if [ ! -f "$HASH_FILE" ]; then
    echo '{"error": "No snapshot found. Run ./wiki/wiki-hash.sh snapshot first."}' >&2
    exit 1
  fi

  local stored_tsv current_tsv changed_tsv added_tsv removed_tsv
  stored_tsv=$(mktemp)
  current_tsv=$(mktemp)
  changed_tsv=$(mktemp)
  added_tsv=$(mktemp)
  removed_tsv=$(mktemp)

  # Parse stored hashes -> TSV
  json_to_tsv "$HASH_FILE" > "$stored_tsv"

  # Compute current hashes -> TSV
  while IFS= read -r relpath; do
    [ -z "$relpath" ] && continue
    local hash
    hash=$(shasum -a 256 "$REPO_ROOT/$relpath" | awk '{print $1}')
    printf '%s\t%s\n' "$relpath" "$hash"
  done < <(build_file_list) > "$current_tsv"

  # Changed: same path, different hash
  join "$stored_tsv" "$current_tsv" | awk '{if ($2 != $3) print $1}' > "$changed_tsv"

  # Added: in current but not stored
  join -v2 "$stored_tsv" "$current_tsv" | awk '{print $1}' > "$added_tsv"

  # Removed: in stored but not current
  join -v1 "$stored_tsv" "$current_tsv" | awk '{print $1}' > "$removed_tsv"

  local n_changed n_added n_removed total
  n_changed=$(wc -l < "$changed_tsv" | tr -d ' ')
  n_added=$(wc -l < "$added_tsv" | tr -d ' ')
  n_removed=$(wc -l < "$removed_tsv" | tr -d ' ')
  total=$(wc -l < "$current_tsv" | tr -d ' ')

  local has_changes=false
  [ "$n_changed" -gt 0 ] || [ "$n_added" -gt 0 ] || [ "$n_removed" -gt 0 ] && has_changes=true

  # Output JSON
  echo "{"
  echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"total_tracked\": $total,"
  echo "  \"changed_count\": $n_changed,"
  echo "  \"added_count\": $n_added,"
  echo "  \"removed_count\": $n_removed,"
  echo "  \"has_changes\": $has_changes,"

  echo "  \"changed\": ["
  if [ "$n_changed" -gt 0 ]; then
    sed 's/^/    "/; s/$/"/' "$changed_tsv" | sed '$ s/$/,/'
  fi
  echo "  ],"

  echo "  \"added\": ["
  if [ "$n_added" -gt 0 ]; then
    sed 's/^/    "/; s/$/"/' "$added_tsv" | sed '$ s/$/,/'
  fi
  echo "  ],"

  echo "  \"removed\": ["
  if [ "$n_removed" -gt 0 ]; then
    sed 's/^/    "/; s/$/"/' "$removed_tsv" | sed '$ s/$/,/'
  fi
  echo "  ]"

  echo "}"

  rm -f "$stored_tsv" "$current_tsv" "$changed_tsv" "$added_tsv" "$removed_tsv"
}

# Status: human-readable summary
do_status() {
  local diff_output
  diff_output=$(do_diff)

  local has_changes n_changed n_added n_removed
  has_changes=$(echo "$diff_output" | grep '"has_changes"' | grep -o 'true\|false')
  n_changed=$(echo "$diff_output" | grep '"changed_count"' | grep -o '[0-9]*')
  n_added=$(echo "$diff_output" | grep '"added_count"' | grep -o '[0-9]*')
  n_removed=$(echo "$diff_output" | grep '"removed_count"' | grep -o '[0-9]*')

  echo "=== Wiki Change Detection ==="
  echo "Changed:  $n_changed files"
  echo "Added:    $n_added files"
  echo "Removed:  $n_removed files"
  echo "Stale:    $has_changes"

  if [ "$has_changes" = "true" ]; then
    echo ""
    echo "Wiki is STALE. Source files have changed since last snapshot."
    echo "Run './wiki/wiki-hash.sh diff' for the full list."
    echo "After updating wiki pages, run './wiki/wiki-hash.sh snapshot' to refresh."
  else
    echo ""
    echo "Wiki is UP TO DATE with the codebase."
  fi
}

# Main
case "${1:-help}" in
  snapshot)
    do_snapshot
    ;;
  diff)
    do_diff
    ;;
  status)
    do_status
    ;;
  *)
    echo "Usage: $0 {snapshot|diff|status}"
    echo ""
    echo "  snapshot  — Hash all source files, save to .source-hashes.json"
    echo "  diff      — Compare current files vs snapshot (JSON output)"
    echo "  status    — Human-readable change summary"
    ;;
esac
