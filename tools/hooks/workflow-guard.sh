#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

[[ "$ACTIVE" == "true" ]] && exit 0

# no edit log = no file edits this session = nothing to guard
edit_log="/tmp/session-edits-${SESSION_ID}"
[[ ! -f "$edit_log" ]] && exit 0

_sha() { shasum -a 256 2>/dev/null || sha256sum; }

baselines=(/tmp/session-git-baseline-${SESSION_ID}-*)
[[ ! -e "${baselines[0]}" ]] && exit 0

edit_log_contents=$(LC_ALL=C sort -u "$edit_log")

for bf in "${baselines[@]}"; do
    [[ -f "$bf" ]] || continue
    repo=$(awk '/^repo=/{sub(/^repo=/,""); print; exit}' "$bf")
    [[ -z "$repo" || ! -d "$repo" ]] && continue

    # collect session-edited relative paths in this repo
    session_files=()
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        case "$f" in "$repo"/*)
            session_files+=("${f#$repo/}")
            ;;
        esac
    done <<<"$edit_log_contents"

    [[ ${#session_files[@]} -eq 0 ]] && continue

    # filter to files with actual net changes vs pre-session state
    _file_baselines="/tmp/session-file-baselines-${SESSION_ID}"
    if [[ -f "$_file_baselines" ]]; then
        _net=()
        for sf in "${session_files[@]}"; do
            _full="$repo/$sf"
            _bl=$(awk -v fp="$_full" -F'\t' '$1 == fp {print $2; exit}' "$_file_baselines" 2>/dev/null)
            if [[ -z "$_bl" ]]; then
                _net+=("$sf")
            elif [[ "$_bl" == "__new__" ]]; then
                [[ -e "$_full" ]] && _net+=("$sf")
            else
                if [[ -f "$_full" ]]; then
                    _cur=$(_sha <"$_full" | cut -d' ' -f1)
                    [[ "$_cur" != "$_bl" ]] && _net+=("$sf")
                else
                    _net+=("$sf")
                fi
            fi
        done
        session_files=("${_net[@]}")
        [[ ${#session_files[@]} -eq 0 ]] && continue
    fi

    # count dirty lines ONLY from session-edited files
    tracked=$(cd "$repo" && git diff --numstat HEAD -- "${session_files[@]}" 2>/dev/null | awk '{s+=$1+$2} END {print s+0}')
    untracked_lines=0
    untracked_files=$(cd "$repo" && git ls-files --others --exclude-standard -- "${session_files[@]}" 2>/dev/null || true)
    if [[ -n "$untracked_files" ]]; then
        untracked_lines=$(cd "$repo" && printf '%s\n' "$untracked_files" | while IFS= read -r f; do
            wc -l <"$f" 2>/dev/null || echo 0
        done | awk '{s+=$1} END {print s+0}')
    fi

    lines=$((tracked + untracked_lines))
    [[ "$lines" -lt 10 ]] && continue

    all_trivial=true
    while IFS=$'\t' read -r _ _ f; do
        case "$f" in *.md | *.txt | *.rst | *.adoc | *.mdx) ;;
        *) case "${f##*/}" in .gitignore | .gitattributes | .editorconfig) ;; *)
            all_trivial=false
            break
            ;;
        esac ;;
        esac
    done < <(cd "$repo" && git diff --numstat HEAD -- "${session_files[@]}" 2>/dev/null)
    if $all_trivial && [[ -n "$untracked_files" ]]; then
        while IFS= read -r f; do
            case "$f" in *.md | *.txt | *.rst | *.adoc | *.mdx) ;;
            *) case "${f##*/}" in .gitignore | .gitattributes | .editorconfig) ;; *)
                all_trivial=false
                break
                ;;
            esac ;;
            esac
        done <<<"$untracked_files"
    fi
    $all_trivial && continue

    _repo_hash=$(printf '%s' "$repo" | _sha | cut -d' ' -f1)
    marker="/tmp/ar-${_repo_hash}"
    if [[ -f "$marker" ]]; then
        marker_age=$(($(date +%s) - $(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null || echo 0)))
        stored_fp=$(sed -n '1p' "$marker" 2>/dev/null || true)
        stored_paths=$(sed -n '2p' "$marker" 2>/dev/null || true)
        # shellcheck disable=SC2086
        read -ra _ar_paths <<<"$stored_paths"

        if [[ ${#_ar_paths[@]} -gt 0 ]]; then
            all_dirty=$(cd "$repo" && {
                git diff --name-only HEAD -- "${session_files[@]}" 2>/dev/null
                git ls-files --others --exclude-standard -- "${session_files[@]}" 2>/dev/null
            } | LC_ALL=C sort -u)
            scoped_dirty=$(cd "$repo" && {
                git diff --name-only HEAD -- "${_ar_paths[@]}" 2>/dev/null
                git ls-files --others --exclude-standard -- "${_ar_paths[@]}" 2>/dev/null
            } | LC_ALL=C sort -u)
            unreviewed=$(LC_ALL=C comm -23 <(echo "$all_dirty") <(echo "$scoped_dirty") | grep -vE '\.(md|txt|rst|adoc|mdx)$' | grep -vcE '(^|/)\.(gitignore|gitattributes|editorconfig)$' || true)
            [[ "$unreviewed" -gt 0 ]] && _ar_ok=false || _ar_ok=true
        else
            _ar_ok=true
        fi

        if [[ "$_ar_ok" == "true" ]]; then
            ar_fp=$(cd "$repo" && {
                git diff HEAD -- "${_ar_paths[@]}" 2>/dev/null
                git ls-files --others --exclude-standard -z -- "${_ar_paths[@]}" 2>/dev/null | while IFS= read -r -d '' f; do
                    [[ -f "$f" ]] || continue
                    if command -v file &>/dev/null && file --mime-encoding "$f" 2>/dev/null | sed 's/.*: //' | grep -qE '^(us-ascii|utf-8|ascii|iso-8859)'; then
                        printf '=== %s ===\n' "$f"
                        cat "$f" 2>/dev/null
                    else
                        printf '=== %s ===\n' "$f"
                        _sha <"$f" 2>/dev/null | cut -d' ' -f1
                    fi
                done
            } | _sha | cut -d' ' -f1)
            [[ "$marker_age" -lt 3600 && "$ar_fp" == "$stored_fp" ]] && continue
        fi
    fi

    jq -n --arg repo "$repo" --arg lines "$lines" '{
	  "decision": "block",
	  "reason": ("WORKFLOW GUARD: " + $repo + " has " + $lines + " changed lines but no adversarial review was detected. per <adversarial-review> section: run ~/box/tools/adversarial-review/review.sh with appropriate lenses before reporting completion. if AR is not applicable here (user explicitly skipped, or this is a non-code task), say so and stop.")
	}'
    exit 0
done

exit 0
