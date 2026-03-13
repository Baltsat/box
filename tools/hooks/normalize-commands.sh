#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0
command -v uv >/dev/null 2>&1 || exit 0
INPUT=$(cat)
cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
[[ -z "$cmd" ]] && exit 0

# skip heredocs — can't safely rewrite inside document bodies
[[ "$cmd" == *'<<'* ]] && exit 0

B='(^|[[:space:]]*[;&|]{1,2}[[:space:]]*|[(][[:space:]]*|[$][(][[:space:]]*)'
W='([[:space:]]|$)'

new_cmd=$(printf '%s\n' "$cmd" | sed -E \
    -e "s/${B}(python3?)${W}/\1uv run \2\3/g" \
    -e "s/${B}(pip3?)${W}/\1uv pip\3/g" \
    -e "s/${B}(pytest)${W}/\1uv run \2\3/g")

new_cmd=$(printf '%s\n' "$new_cmd" | sed -E \
    -e 's/uv run uv run/uv run/g' \
    -e 's/uv run uv pip/uv pip/g' \
    -e 's/uv uv pip/uv pip/g')

[[ "$new_cmd" == "$cmd" ]] && exit 0

jq -n --arg cmd "$new_cmd" '{
  "hookSpecificOutput": {
    "permissionDecision": "allow",
    "updatedInput": {"command": $cmd}
  }
}'
