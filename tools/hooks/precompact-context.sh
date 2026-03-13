#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
	SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
	[[ -z "$SESSION_ID" ]] && exit 0
	TRANSCRIPT=$(find ~/.claude/projects -name "${SESSION_ID}.jsonl" -print -quit 2>/dev/null || true)
	[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0
fi

formatted=$(jq -rs '
  [.[] | select(.type == "user") |
  (
    .message.content |
    if type == "string" then .
    elif type == "array" then
      [.[] | select(.type == "text") | .text] | join("\n")
    else null
    end
  ) // null |
  select(. != null and length > 0)] |
  if length == 0 then empty
  else
    to_entries |
    map("### message \(.key + 1)\n\(.value)\n\n---") |
    join("\n") |
    if length > 20000 then .[0:20000] + "\n\n(truncated at 20K chars)" else . end
  end
' "$TRANSCRIPT" 2>/dev/null)

[[ -z "$formatted" ]] && exit 0

cat <<HEADER
## user message history (preserve across compaction)

each ### block = one distinct user message, chronological order.
these contain unique domain context, decisions, and constraints not in the model. preserve them.

HEADER
echo "$formatted"
exit 0
