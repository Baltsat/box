#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

[[ "$ACTIVE" == "true" ]] && exit 0

_sha() { shasum -a 256 2>/dev/null || sha256sum; }

# find all baselines for this session
baselines=(/tmp/session-git-baseline-${SESSION_ID}-*)
[[ ! -e "${baselines[0]}" ]] && exit 0

changed_repos=()
for bf in "${baselines[@]}"; do
	[[ -f "$bf" ]] || continue
	repo=$(awk '/^repo=/{sub(/^repo=/,""); print; exit}' "$bf")
	stored_fp=$(awk '/^fp=/{sub(/^fp=/,""); print; exit}' "$bf")
	[[ -z "$repo" || ! -d "$repo" ]] && continue

	current_fp=$(cd "$repo" && {
		git status --porcelain 2>/dev/null
		git diff HEAD 2>/dev/null
	} | _sha | cut -d' ' -f1)

	[[ "$current_fp" == "$stored_fp" ]] && continue
	changed_repos+=("$repo")
done

[[ ${#changed_repos[@]} -eq 0 ]] && exit 0

for repo in "${changed_repos[@]}"; do
	tracked=$(cd "$repo" && git diff --numstat HEAD 2>/dev/null | awk '{s+=$1+$2} END {print s+0}')
	untracked_lines=0
	untracked_files=$(cd "$repo" && git ls-files --others --exclude-standard 2>/dev/null || true)
	if [[ -n "$untracked_files" ]]; then
		untracked_lines=$(cd "$repo" && printf '%s\n' "$untracked_files" | while IFS= read -r f; do
			wc -l <"$f" 2>/dev/null || echo 0
		done | awk '{s+=$1} END {print s+0}')
	fi
	lines=$((tracked + untracked_lines))
	[[ "$lines" -lt 10 ]] && continue

	_repo_hash=$(printf '%s' "$repo" | _sha | cut -d' ' -f1)
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
		[[ "$marker_age" -lt 3600 && "$ar_fp" == "$stored_fp" ]] && continue
	fi

	jq -n --arg repo "$repo" --arg lines "$lines" '{
	  "decision": "block",
	  "reason": ("WORKFLOW GUARD: " + $repo + " has " + $lines + " changed lines but no adversarial review was detected. per <adversarial-review> section: run ~/box/tools/adversarial-review/review.sh with appropriate lenses before reporting completion. if AR is not applicable here (user explicitly skipped, or this is a non-code task), say so and stop.")
	}'
	exit 0
done

exit 0
