#!/usr/bin/env bash
# PreToolUse guard: protects the Maven baseline and the loop's own instructions.
# Debug logging is on — remove the log lines once path handling is confirmed.

input=$(cat)
LOG=/tmp/hook-debug.jsonl

echo "$input" >> "$LOG"

path=$(echo "$input" | jq -r '
  .tool_input.file_path
  // .tool_input.notebook_path
  // .tool_input.path
  // empty')
rel="${path#"$CLAUDE_PROJECT_DIR"/}"

echo "{\"_derived\":{\"path\":\"$path\",\"rel\":\"$rel\",\"project_dir\":\"${CLAUDE_PROJECT_DIR:-UNSET}\"}}" >> "$LOG"

case "$rel" in
  .claude/*|CLAUDE.md|PROMPT.md|ralph.sh|state/TODO.md|backend/pom.xml|backend/mvnw|backend/.mvn/*)
    echo "{\"_decision\":\"BLOCK\",\"rel\":\"$rel\"}" >> "$LOG"
    echo "BLOCKED: $rel is read-only. The Maven build is the migration baseline and must not change. If the task cannot be completed without editing it, write the reason to state/BLOCKED.md and stop." >&2
    exit 2 ;;
esac

echo "{\"_decision\":\"ALLOW\",\"rel\":\"$rel\"}" >> "$LOG"
exit 0
