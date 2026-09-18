#!/usr/bin/env bash
# PreToolUse guard: protects the Maven baseline and the loop's own instructions.

input=$(cat)

path=$(echo "$input" | jq -r '
  .tool_input.file_path
  // .tool_input.notebook_path
  // .tool_input.path
  // empty')
rel="${path#"$CLAUDE_PROJECT_DIR"/}"

case "$rel" in
  .claude/*|CLAUDE.md|PROMPT.md|ralph.sh|state/TODO.md|backend/pom.xml*|backend/mvnw*|backend/.mvn/*)
    echo "BLOCKED: $rel is read-only. The Maven build is the migration baseline and must not change. If the task cannot be completed without editing it, write the reason to state/BLOCKED.md and stop." >&2
    exit 2 ;;
esac

exit 0
