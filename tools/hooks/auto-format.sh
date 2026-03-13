#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

# skip formatting after Edit — sequential edits to the same file will fail
# because old_string no longer matches the reformatted content.
# only format after Write (full file replacement). precommit handles the rest.
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
[[ "$TOOL" == "Edit" ]] && exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0

ext="${FILE##*.}"
case "$ext" in
py)
    command -v ruff &>/dev/null && ruff format --quiet "$FILE" 2>/dev/null || true
    ;;
js | jsx | ts | tsx | json | yaml | yml | md | mdx | css | scss | html | htm | vue | svelte | graphql)
    command -v prettier &>/dev/null && prettier --write --log-level=error "$FILE" 2>/dev/null || true
    ;;
nix)
    command -v nixfmt &>/dev/null && nixfmt "$FILE" 2>/dev/null || true
    ;;
sh | bash | zsh)
    command -v shfmt &>/dev/null && shfmt -w "$FILE" 2>/dev/null || true
    ;;
toml)
    command -v taplo &>/dev/null && taplo fmt "$FILE" 2>/dev/null || true
    ;;
go)
    command -v gofmt &>/dev/null && gofmt -w "$FILE" 2>/dev/null || true
    ;;
rs)
    command -v rustfmt &>/dev/null && rustfmt --edition 2021 "$FILE" 2>/dev/null || true
    ;;
swift)
    command -v swift-format &>/dev/null && swift-format -i "$FILE" 2>/dev/null || true
    ;;
esac
exit 0
