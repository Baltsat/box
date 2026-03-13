#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0
command -v uv >/dev/null 2>&1 || exit 0
INPUT=$(cat)
cmd=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
[[ -z "$cmd" ]] && exit 0

# B = command boundary: start of line, && || ; | & ( $(
B='(^|[[:space:]]*[;&|]{1,2}[[:space:]]*|[(][[:space:]]*|[$][(][[:space:]]*)'
# W = word boundary after target: space or end of string
W='([[:space:]]|$)'

new_cmd=$(echo "$cmd" | sed -E \
	-e "s/${B}(python3?)${W}/\1uv run \2\3/g" \
	-e "s/${B}(pip3?)${W}/\1uv pip\3/g" \
	-e "s/${B}(pytest)${W}/\1uv run \2\3/g")

# clean double-wraps (uv run uv run → uv run, uv run uv pip → uv pip)
new_cmd=$(echo "$new_cmd" | sed -E \
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
