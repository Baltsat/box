#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
[[ -z "$CWD" ]] && CWD="$PWD"

# prevent infinite loop: already nudged once
[[ "$ACTIVE" == "true" ]] && exit 0

# resolve repo root (exit silently if not a git repo)
repo=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null) || exit 0

# no changes = nothing to review (includes untracked files)
dirty=$(cd "$repo" && git status --porcelain 2>/dev/null || true)
[[ -z "$dirty" ]] && exit 0

# count changed lines: tracked diffs + untracked file contents
tracked=$(cd "$repo" && git diff --numstat HEAD 2>/dev/null | awk '{s+=$1+$2} END {print s+0}')
untracked_lines=0
untracked_files=$(cd "$repo" && git ls-files --others --exclude-standard 2>/dev/null || true)
if [[ -n "$untracked_files" ]]; then
    untracked_lines=$(cd "$repo" && printf '%s\n' "$untracked_files" | while IFS= read -r f; do
        wc -l <"$f" 2>/dev/null || echo 0
    done | awk '{s+=$1} END {print s+0}')
fi
lines=$((tracked + untracked_lines))
[[ "$lines" -lt 10 ]] && exit 0

# check AR marker (per-repo, fingerprinted to exact worktree state)
marker="/tmp/ar-$(printf '%s' "$repo" | shasum -a 256 | cut -d' ' -f1)"
if [[ -f "$marker" ]]; then
    marker_age=$(($(date +%s) - $(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0)))
    current_fp=$(cd "$repo" && {
        git diff HEAD 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null | sort | while IFS= read -r f; do
            printf '=== %s ===\n' "$f"
            cat "$f" 2>/dev/null
        done
    } | shasum -a 256 | cut -d' ' -f1)
    stored_fp=$(cat "$marker" 2>/dev/null || true)
    [[ "$marker_age" -lt 3600 && "$current_fp" == "$stored_fp" ]] && exit 0
fi

# block stop — remind about AR
jq -n '{
  "decision": "block",
  "reason": "WORKFLOW GUARD: you have non-trivial uncommitted changes but no adversarial review was detected. per <adversarial-review> section: run ~/box/tools/adversarial-review/review.sh with appropriate lenses before reporting completion. if AR is not applicable here (user explicitly skipped, or this is a non-code task), say so and stop."
}'
