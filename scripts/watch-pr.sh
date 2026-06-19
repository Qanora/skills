#!/bin/bash
# PR status monitor — pure state polling.
# Usage: ./watch-pr.sh <pr_number>
# Exit: 0=CI green/merged, 1=CI failure, 2=timeout, 5=missing tools
set -euo pipefail

for cmd in gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is required but not installed"
    exit 5
  fi
done

PR="${1:?Usage: $0 <pr_number>}"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

# Dynamic timeout: 20 rounds base + 5 per 100 lines over 300, max 60
calculate_timeout() {
  local pr_meta total_lines additions deletions
  if ! pr_meta=$(gh pr view "$PR" --repo "$REPO" --json additions,deletions 2>/dev/null); then
    echo "[INIT] $(date +%H:%M:%S) gh pr view failed, using default timeout"
    TIMEOUT=20; return
  fi
  additions=$(echo "$pr_meta" | jq -r '.additions // 0')
  deletions=$(echo "$pr_meta" | jq -r '.deletions // 0')
  total_lines=$((additions + deletions))
  if [ "$total_lines" -le 300 ]; then TIMEOUT=20
  else
    extra=$(( (total_lines - 300 + 99) / 100 * 5 ))
    TIMEOUT=$((20 + extra))
    [ "$TIMEOUT" -gt 60 ] && TIMEOUT=60
  fi
  echo "[INFO] Dynamic timeout: $TIMEOUT rounds ($additions +, $deletions -)"
}

calculate_timeout
ROUND=0

while true; do
  ROUND=$((ROUND + 1))

  if ! RESULT=$(gh pr view "$PR" --repo "$REPO" \
    --json statusCheckRollup,reviewDecision,mergedAt \
    --jq '{
      failing: [(.statusCheckRollup // [])[] |
        select(.status == "COMPLETED" and
          (.conclusion == "FAILURE" or .conclusion == "TIMED_OUT" or
           .conclusion == "CANCELLED" or .conclusion == "ACTION_REQUIRED" or
           .conclusion == "STARTUP_FAILURE")) |
        "\(.name):\(.conclusion)"
      ],
      pending: [(.statusCheckRollup // [])[] |
        select(.status != "COMPLETED" and .status != null) |
        .name
      ],
      merged: .mergedAt
    }' 2>/dev/null); then
    echo "[$ROUND] $(date +%H:%M:%S) gh pr view failed"
    sleep 30; continue
  fi

  MERGED=$(echo "$RESULT" | jq -r '.merged')
  FAILING=$(echo "$RESULT" | jq -r '.failing | join(",")')
  PENDING=$(echo "$RESULT" | jq -r '.pending | join(",")')

  echo "[$ROUND] $(date +%H:%M:%S) pending=${PENDING:-none} failing=${FAILING:-none}"

  # Terminal: merged
  if [ "$MERGED" != "null" ]; then
    echo "=== MERGED at $MERGED ==="
    exit 0
  fi

  # Terminal: CI failure
  if [ -n "$FAILING" ]; then
    echo "=== CI FAILURES: $FAILING ==="
    exit 1
  fi

  # Ready to merge: no pending + no failing
  if [ -z "$PENDING" ] && [ -z "$FAILING" ]; then
    echo "=== CI green — ready ==="
    exit 0
  fi

  if [ "$ROUND" -ge "$TIMEOUT" ]; then
    echo "=== TIMEOUT after ${ROUND} rounds (max $TIMEOUT) ==="
    if [ -z "$FAILING" ]; then echo "=== CI green despite timeout ===" && exit 0; fi
    exit 2
  fi

  sleep 30
done
