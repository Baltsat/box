#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
[[ -z "$CWD" ]] && CWD="$PWD"

repo=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null) || exit 0

_sha() { shasum -a 256 2>/dev/null || sha256sum; }

key="${SESSION_ID}-$(printf '%s' "$repo" | _sha | cut -d' ' -f1)"
baseline="/tmp/session-git-baseline-${key}"

# with session_id: write once per session (skip compaction re-fires)
# without session_id: always overwrite (can't distinguish sessions)
[[ -n "$SESSION_ID" && -f "$baseline" ]] && exit 0

fp=$(cd "$repo" && {
    git status --porcelain 2>/dev/null
    git diff HEAD 2>/dev/null
} | _sha | cut -d' ' -f1)

echo "$fp" > "$baseline"

# cleanup old baselines (> 7 days)
find /tmp -maxdepth 1 -name 'session-git-baseline-*' -mtime +7 -delete 2>/dev/null || true
exit 0
