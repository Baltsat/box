#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0

ext="${FILE##*.}"
case "$ext" in
py)
    command -v ruff &>/dev/null && ruff format --quiet "$FILE" 2>/dev/null
    ;;
js | jsx | ts | tsx | json | yaml | yml | md | mdx | css | scss | html | htm | vue | svelte | graphql)
    command -v prettier &>/dev/null && prettier --write --log-level=error "$FILE" 2>/dev/null
    ;;
nix)
    command -v nixfmt &>/dev/null && nixfmt "$FILE" 2>/dev/null
    ;;
sh | bash | zsh)
    command -v shfmt &>/dev/null && shfmt -w "$FILE" 2>/dev/null
    ;;
toml)
    command -v taplo &>/dev/null && taplo fmt "$FILE" 2>/dev/null
    ;;
go)
    command -v gofmt &>/dev/null && gofmt -w "$FILE" 2>/dev/null
    ;;
rs)
    command -v rustfmt &>/dev/null && rustfmt --edition 2021 "$FILE" 2>/dev/null
    ;;
swift)
    command -v swift-format &>/dev/null && swift-format -i "$FILE" 2>/dev/null
    ;;
esac
exit 0
