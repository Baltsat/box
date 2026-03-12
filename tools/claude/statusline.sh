#!/bin/bash

# Custom statusline for Claude Code
# Shows: directory | model | context (used/left/tokens) | optional 5h window | git status

input=$(cat)

# Extract from JSON
model_name=$(echo "$input" | jq -r '.model.display_name // "claude"')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // "~"')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
current_usage=$(echo "$input" | jq '.context_window.current_usage')

# Calculate context usage/left
current_tokens=0
if [ "$current_usage" != "null" ]; then
    current_tokens=$(echo "$current_usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    context_percent=$((current_tokens * 100 / context_size))
else
    context_percent=0
fi
[ "$context_percent" -lt 0 ] && context_percent=0
[ "$context_percent" -gt 100 ] && context_percent=100
context_left=$((100 - context_percent))
tokens_left=$((context_size - current_tokens))
[ "$tokens_left" -lt 0 ] && tokens_left=0

fmt_tokens() {
    local n="${1:-0}"
    if [ "$n" -ge 1000000 ]; then
        awk -v n="$n" 'BEGIN { printf "%.1fM", n / 1000000 }'
    elif [ "$n" -ge 1000 ]; then
        awk -v n="$n" 'BEGIN { printf "%.1fk", n / 1000 }'
    else
        printf "%s" "$n"
    fi
}

# Best-effort 5h remaining lookup across known payload shapes
five_hour_left=$(echo "$input" | jq -r '
[
  .rate_limit.five_hour.remaining_percent?,
  .rate_limit.five_hour.percent_remaining?,
  .rate_limits.five_hour.remaining_percent?,
  .rate_limits.five_hour.percent_remaining?,
  .rate_limits.window_5h.remaining_percent?,
  .rate_limits.window_5h.percent_remaining?,
  .limits.five_hour.remaining_percent?,
  .limits.five_hour.percent_remaining?
] | map(select(type=="number")) | first // empty
')

# Build context progress bar (15 chars)
bar_width=15
filled=$((context_percent * bar_width / 100))
empty=$((bar_width - filled))
bar=""
for ((i = 0; i < filled; i++)); do bar+="█"; done
for ((i = 0; i < empty; i++)); do bar+="░"; done

# Directory name
dir_name=$(basename "$current_dir")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# Context color
if [ "$context_percent" -ge 90 ]; then
    CTX_COLOR="$RED"
elif [ "$context_percent" -ge 75 ]; then
    CTX_COLOR="$YELLOW"
else
    CTX_COLOR="$GRAY"
fi

# Git info
cd "$current_dir" 2>/dev/null || cd /

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    status_output=$(git status --porcelain 2>/dev/null)

    if [ -n "$status_output" ]; then
        total_files=$(echo "$status_output" | wc -l | xargs)
        line_stats=$(git diff --numstat HEAD 2>/dev/null | awk '{added+=$1; removed+=$2} END {print added+0, removed+0}')
        added=$(echo "$line_stats" | cut -d' ' -f1)
        removed=$(echo "$line_stats" | cut -d' ' -f2)

        git_info=" ${YELLOW}($branch${NC} ${YELLOW}|${NC} ${GRAY}${total_files}f${NC}"
        [ "$added" -gt 0 ] && git_info="${git_info} ${GREEN}+${added}${NC}"
        [ "$removed" -gt 0 ] && git_info="${git_info} ${RED}-${removed}${NC}"
        git_info="${git_info} ${YELLOW})${NC}"
    else
        git_info=" ${YELLOW}($branch)${NC}"
    fi
else
    git_info=""
fi

quota_info=""
if [ -n "$five_hour_left" ]; then
    quota_info=" ${GRAY}|${NC} ${CYAN}5h${NC} ${five_hour_left}% left"
fi

# Output
echo -e "${BLUE}${dir_name}${NC} ${GRAY}|${NC} ${CYAN}${model_name}${NC} ${GRAY}|${NC} ${CTX_COLOR}${bar}${NC}${quota_info}${git_info:+ ${GRAY}|${NC}}${git_info}"
