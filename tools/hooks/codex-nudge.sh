#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
[[ -z "$SESSION_ID" ]] && exit 0
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

[[ -z "$FILE_PATH" ]] && exit 0

# skip config/doc files — not codex territory
is_config() {
    case "$1" in
    *.md | *.json | *.toml | *.yaml | *.yml | *.env* | *.lock | Makefile | Dockerfile) return 0 ;;
    *) return 1 ;;
    esac
}
is_config "$FILE_PATH" && exit 0

# measure change size; MultiEdit has array of edits per file
if [[ "$TOOL" == "MultiEdit" ]]; then
    CHANGE_LINES=$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.new_string // ""] | join("\n")' | wc -l)
elif [[ "$TOOL" == "Edit" ]]; then
    CHANGE_LINES=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""' | wc -l)
else
    CHANGE_LINES=$(echo "$INPUT" | jq -r '.tool_input.content // ""' | wc -l)
fi

STATE="/tmp/codex-nudge-${SESSION_ID}"
COOLDOWN="/tmp/codex-nudge-${SESSION_ID}-cooldown"

echo "${FILE_PATH}:${CHANGE_LINES}" >>"$STATE" 2>/dev/null || {
    echo "codex-nudge: cannot write state to $STATE" >&2
    exit 0
}

# check cooldown (1 min)
if [[ -f "$COOLDOWN" ]]; then
    LAST=$(cat "$COOLDOWN" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    [[ $((NOW - LAST)) -lt 60 ]] && exit 0
fi

TOTAL_EDITS=$(wc -l <"$STATE")
UNIQUE_FILES=$(cut -d: -f1 "$STATE" | sort -u | wc -l)

SHOULD_NUDGE=0
[[ "$TOTAL_EDITS" -ge 5 && "$UNIQUE_FILES" -ge 3 ]] && SHOULD_NUDGE=1
[[ "$TOTAL_EDITS" -ge 8 ]] && SHOULD_NUDGE=1
[[ "$CHANGE_LINES" -gt 50 ]] && SHOULD_NUDGE=1

[[ "$SHOULD_NUDGE" -eq 0 ]] && exit 0

date +%s >"$COOLDOWN"

# resolve real project root: git root → file dir (if absolute+exists) → warn
FILE_DIR=$(dirname "$FILE_PATH")
if REAL_CWD=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null); then
    : # git root found
elif [[ "$FILE_DIR" == /* && -d "$FILE_DIR" ]]; then
    REAL_CWD="$FILE_DIR"
else
    echo "codex-nudge: cannot resolve cwd from FILE_PATH=$FILE_PATH" >&2
    REAL_CWD="$FILE_DIR" # best effort
fi

jq -n \
    --arg edits "$TOTAL_EDITS" \
    --arg files "$UNIQUE_FILES" \
    --arg cwd "$REAL_CWD" \
    '{
  "additionalContext": "[CODEX-NUDGE] you have made \($edits) manual edits across \($files) files this session. per <delegation>, concrete implementation work should move to delegate_codex once it is >10 lines.\n\ndelegate now:\n  delegate_codex(task=\"<spec>\", cwd=\"\($cwd)\")\n  delegate_codex(session_id=\"<id>\", task=\"<next fix>\")  ← iterate\n\nfor reasoning, review, or architecture work:\n  delegate_claude(task=\"<analysis>\", cwd=\"\($cwd)\")\n\nspec must include: goal · exact files to modify · behavior to change · constraints · verification to run · do not commit.\n\ncontinue manually ONLY if: architecture/API still undecided · <10 lines left · migration with shared mutable state · post-delegation integration review."
}'
