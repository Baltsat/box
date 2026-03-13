#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
[[ -z "$CWD" ]] && CWD="$PWD"

[[ "$ACTIVE" == "true" ]] && exit 0

repo=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null) || exit 0

dirty=$(cd "$repo" && git status --porcelain 2>/dev/null || true)
[[ -z "$dirty" ]] && exit 0

_sha() { shasum -a 256 2>/dev/null || sha256sum; }
_repo_hash=$(printf '%s' "$repo" | _sha | cut -d' ' -f1)

# skip if state unchanged since session start (claude didn't edit anything)
_safe_cat() {
	[[ -f "$1" ]] || return 0
	[[ -L "$1" ]] && return 0
	local sz
	sz=$(wc -c <"$1" 2>/dev/null || echo 0)
	[[ "$sz" -gt 1048576 ]] && return 0
	cat "$1" 2>/dev/null
}

baseline_file="/tmp/session-git-baseline-${SESSION_ID}-${_repo_hash}"
if [[ -n "$SESSION_ID" && -f "$baseline_file" ]]; then
	current_fp=$(cd "$repo" && {
		git status --porcelain 2>/dev/null
		git diff HEAD 2>/dev/null
		git ls-files --others --exclude-standard 2>/dev/null | sort | while IFS= read -r f; do
			_safe_cat "$f"
		done
	} | _sha | cut -d' ' -f1)
	baseline_fp=$(cat "$baseline_file" 2>/dev/null || true)
	[[ "$current_fp" == "$baseline_fp" ]] && exit 0
fi

# trivial changes don't need AR
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
marker="/tmp/ar-${_repo_hash}"
if [[ -f "$marker" ]]; then
	marker_age=$(($(date +%s) - $(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0)))
	ar_fp=$(cd "$repo" && {
		git diff HEAD 2>/dev/null
		git ls-files --others --exclude-standard 2>/dev/null | sort | while IFS= read -r f; do
			printf '=== %s ===\n' "$f"
			cat "$f" 2>/dev/null
		done
	} | _sha | cut -d' ' -f1)
	stored_fp=$(cat "$marker" 2>/dev/null || true)
	[[ "$marker_age" -lt 3600 && "$ar_fp" == "$stored_fp" ]] && exit 0
fi

jq -n '{
  "decision": "block",
  "reason": "WORKFLOW GUARD: you have non-trivial uncommitted changes but no adversarial review was detected. per <adversarial-review> section: run ~/box/tools/adversarial-review/review.sh with appropriate lenses before reporting completion. if AR is not applicable here (user explicitly skipped, or this is a non-code task), say so and stop."
}'
