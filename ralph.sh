#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
MAX="${MAX_ITER:-3}"
EFFORT="${EFFORT:-medium}"
mkdir -p state/logs
for i in $(seq 1 "$MAX"); do
  echo "=== iteration $i $(date -u +%FT%TZ) effort=$EFFORT ===" | tee -a state/journal.md
  claude --dangerously-skip-permissions --effort "$EFFORT" -p "$(cat PROMPT.md)" </dev/null \
    2>&1 | tee "state/logs/iter-$i.log"
  if tail -5 "state/logs/iter-$i.log" | grep -qx "<promise>COMPLETE</promise>"; then
    echo "complete at iteration $i"; exit 0
  fi
  if [ -f state/BLOCKED.md ]; then
    echo "blocked at iteration $i"; exit 1
  fi
done
echo "exhausted $MAX iterations"; exit 2
