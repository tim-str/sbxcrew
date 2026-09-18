#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
MAX="${MAX_ITER:-3}"
mkdir -p state/logs
for i in $(seq 1 "$MAX"); do
  echo "=== iteration $i $(date -u +%FT%TZ) ===" | tee -a state/journal.md
  claude --dangerously-skip-permissions -p "$(cat PROMPT.md)" \
    2>&1 | tee "state/logs/iter-$i.log"
  if grep -q "<promise>COMPLETE</promise>" "state/logs/iter-$i.log"; then
    echo "complete at iteration $i"; exit 0
  fi
  if [ -f state/BLOCKED.md ]; then
    echo "blocked at iteration $i"; exit 1
  fi
done
echo "exhausted $MAX iterations"; exit 2
