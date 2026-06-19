#!/bin/bash
# Clean up merged but stale feature branches.
# Usage: ./cleanup-merged-branches.sh [--dry-run]
set -euo pipefail

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true && echo "=== DRY RUN ==="

for cmd in git gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is required"; exit 5
  fi
done

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

echo "Fetching merged PR branches..."
MERGED=$(gh pr list --state merged --limit 1000 --json headRefName --jq '.[].headRefName' | sort -u)

LOCAL=$(git branch | grep -E "^[\* ]+feature/" | sed 's/^[\* ]*//' | sort 2>/dev/null || true)

git fetch --prune
REMOTE=$(git branch -r | grep "origin/feature/" | sed 's/.*origin\///' | sort 2>/dev/null || true)

LOCAL_CLEAN=$(comm -12 <(echo "$MERGED") <(echo "$LOCAL") 2>/dev/null || true)
REMOTE_CLEAN=$(comm -12 <(echo "$MERGED") <(echo "$REMOTE") 2>/dev/null || true)

echo ""
echo "=== Local to clean ==="
echo "${LOCAL_CLEAN:-none}"
echo ""
echo "=== Remote to clean ==="
echo "${REMOTE_CLEAN:-none}"

if $DRY_RUN; then
  echo ""
  echo "=== DRY RUN done ==="
  exit 0
fi

[ -n "$LOCAL_CLEAN" ] && echo "$LOCAL_CLEAN" | while read -r b; do
  echo "Deleting local: $b"
  git branch -D "$b" 2>/dev/null || true
done

[ -n "$REMOTE_CLEAN" ] && echo "$REMOTE_CLEAN" | while read -r b; do
  echo "Deleting remote: origin/$b"
  gh api "repos/$REPO/git/refs/heads/$b" -X DELETE 2>/dev/null || true
done

echo ""
echo "=== Cleanup done ==="
