#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
TEAMMATE=$(echo "$INPUT" | jq -r '.teammate_name')
TEAM=$(echo "$INPUT" | jq -r '.team_name')

COUNTER_FILE="/tmp/claude-idle-${TEAM}-${TEAMMATE}"
COUNT=0
[[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE")

if [[ $COUNT -lt 1 ]]; then
    echo $((COUNT + 1)) > "$COUNTER_FILE"
    cat >&2 <<'MSG'
before going idle:
1. run TaskList to check for remaining pending/unblocked tasks
2. if pending tasks exist, claim one with TaskUpdate and continue working
3. if all tasks are done or blocked on others, you may stop
MSG
    exit 2
fi

rm -f "$COUNTER_FILE"
exit 0
