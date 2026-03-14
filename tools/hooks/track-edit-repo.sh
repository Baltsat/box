#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
[[ -z "$SESSION_ID" ]] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
[[ -z "$FILE_PATH" ]] && exit 0

# canonicalize path (resolve symlinks like /tmp → /private/tmp)
_dir=$(dirname "$FILE_PATH")
if [[ -d "$_dir" ]]; then
    FILE_PATH="$(cd "$_dir" && pwd -P)/$(basename "$FILE_PATH")"
fi

# always log edited files for workflow-guard filtering
echo "$FILE_PATH" >>"/tmp/session-edits-${SESSION_ID}" 2>/dev/null

# track per-file baseline hash (pre-edit content, first edit only per file)
_file_baselines="/tmp/session-file-baselines-${SESSION_ID}"
if ! awk -v fp="$FILE_PATH" -F'\t' 'BEGIN{r=1} $1 == fp {r=0; exit} END {exit r}' "$_file_baselines" 2>/dev/null; then
    if [[ -f "$FILE_PATH" ]]; then
        _fh=$(shasum -a 256 < "$FILE_PATH" 2>/dev/null || sha256sum < "$FILE_PATH")
        printf '%s\t%s\n' "$FILE_PATH" "${_fh%% *}" >> "$_file_baselines"
    else
        printf '%s\t__new__\n' "$FILE_PATH" >> "$_file_baselines"
    fi
fi

dir=$(dirname "$FILE_PATH")
[[ -d "$dir" ]] || exit 0
repo=$(cd "$dir" && git rev-parse --show-toplevel 2>/dev/null) || exit 0

_sha() { shasum -a 256 2>/dev/null || sha256sum; }

key="${SESSION_ID}-$(printf '%s' "$repo" | _sha | cut -d' ' -f1)"
baseline="/tmp/session-git-baseline-${key}"

[[ -f "$baseline" ]] && exit 0

fp=$(cd "$repo" && {
    git status --porcelain 2>/dev/null
    git diff HEAD 2>/dev/null
} | _sha | cut -d' ' -f1)

printf 'repo=%s\nfp=%s\n' "$repo" "$fp" >"$baseline"
exit 0
