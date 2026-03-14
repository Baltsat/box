#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
[[ -z "$FILE_PATH" ]] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""')
[[ -z "$SESSION_ID" ]] && exit 0

dir=$(dirname "$FILE_PATH")
[[ -d "$dir" ]] || exit 0
repo=$(cd "$dir" && git rev-parse --show-toplevel 2>/dev/null) || exit 0

_sha() { shasum -a 256 2>/dev/null || sha256sum; }

repo_hash=$(printf '%s' "$repo" | _sha | cut -d' ' -f1 | cut -c1-12)
snap_dir="/tmp/git-snapshots-${SESSION_ID}-${repo_hash}"
mkdir -p "$snap_dir"

patch="$snap_dir/$(date +%Y%m%d-%H%M%S)-$$.patch"
tool_name=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"')

{
    printf '# snapshot: %s %s %s\n' "$tool_name" "$FILE_PATH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# repo: %s\n\n' "$repo"
    cd "$repo" || exit 0
    git diff HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
        [[ -z "$f" || ! -f "$f" ]] && continue
        enc=$(file --mime-encoding "$f" 2>/dev/null | awk '{print $NF}')
        [[ "$enc" == "binary" ]] && continue
        git diff --no-index /dev/null "$f" 2>/dev/null || true
    done
} >"$patch"

# cap at 50 snapshots per session per repo (filenames are YYYYMMDD-HHMMSS-PID.patch, no spaces)
count=$(find "$snap_dir" -name '*.patch' -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "$count" -gt 50 ]]; then
    ls -1t "$snap_dir"/*.patch 2>/dev/null | tail -n +51 | while IFS= read -r f; do
        rm -f "$f" 2>/dev/null
    done
fi

# cleanup dirs older than 3 days
find /tmp -maxdepth 1 -name 'git-snapshots-*' -type d -mtime +3 -exec rm -rf {} + 2>/dev/null

exit 0
