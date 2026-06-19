#!/bin/bash
# Atomic MR post-merge cleanup: checkout default branch, pull, delete branch, write state.
# Usage: ./fwp-ship-cleanup.sh <issue-number> <branch-name>
set -euo pipefail

for cmd in git gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is required"
    exit 5
  fi
done

ISSUE_NUM="${1:?Usage: $0 <issue-number> <branch-name>}"
BRANCH="${2:?Usage: $0 <issue-number> <branch-name>}"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo master)}"

# Validation
if ! echo "$ISSUE_NUM" | grep -qE '^[0-9]+$'; then
  echo "ERROR: issue-number must be numeric, got: $ISSUE_NUM"; exit 2
fi
EXPECTED="feature/issue-$ISSUE_NUM"
if [ "$BRANCH" != "$EXPECTED" ]; then
  echo "ERROR: branch must be '$EXPECTED', got: $BRANCH"; exit 2
fi

# Safety: dirty working tree
DIRTY=$(git status --porcelain)
if [ -n "$DIRTY" ]; then
  echo "ERROR: working tree dirty — commit or stash first"; exit 1
fi

echo "=== fwp-ship cleanup issue #$ISSUE_NUM ($BRANCH) ==="

# 1. checkout default branch
ORIG=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
echo "[1/5] Switching to $DEFAULT_BRANCH..."
if [ "$ORIG" != "$DEFAULT_BRANCH" ]; then git checkout "$DEFAULT_BRANCH"; fi

# 2. sync
echo "[2/5] Syncing origin/$DEFAULT_BRANCH..."
git fetch origin "$DEFAULT_BRANCH"
git reset --hard "origin/$DEFAULT_BRANCH"

# 3. remove remote residual
echo "[3/5] Removing remote branch 'origin/$BRANCH'..."
git fetch --prune
if git branch -r | grep -q "origin/$BRANCH"; then
  gh api "repos/$REPO/git/refs/heads/$BRANCH" -X DELETE 2>/dev/null || echo "  Already deleted or no permission"
fi

# 4. delete local branch
echo "[4/5] Deleting local branch '$BRANCH'..."
git rev-parse --verify "$BRANCH" >/dev/null 2>&1 && git branch -D "$BRANCH" || echo "  Already deleted"

# 5. write state
echo "[5/5] Writing MERGED state..."
mkdir -p .claude/state
echo "MERGED" > ".claude/state/issue-$ISSUE_NUM.status"
rm -f ".claude/state/issue-$ISSUE_NUM.fix_round"

echo "=== Cleanup complete for issue #$ISSUE_NUM ==="
