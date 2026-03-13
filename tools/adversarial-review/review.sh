#!/usr/bin/env bash
# review.sh — adversarial cross-model reviewer launcher
# handles: temp dir, spawn, polling, validation, cleanup
# agent provides: intent, lenses, diff. script handles everything else.
#
# usage:
#   review.sh --lenses skeptic[,architect,minimalist] --intent TEXT [--diff-file PATH] [--timeout SECS]
#             [--reviewer-model claude|codex]
#
# exit codes: 0=all ok, 1=reviewer failed, 2=timeout
#
# auto-detects model: CODEX_CI set → Codex → spawn Claude; CLAUDECODE set → Claude → spawn Codex

set -euo pipefail
set -m # job control: each background task gets its own process group (enables kill -- -$pid)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRINCIPLES="$SCRIPT_DIR/principles.md"
LENSES_FILE="$SCRIPT_DIR/reviewer-lenses.md"
TIMEOUT=1800
LENSES="skeptic"
INTENT=""
DIFF_FILE=""
EXPLICIT_REVIEWER_MODEL=""
MAX_DIFF_BYTES=204800

while [[ $# -gt 0 ]]; do
    case "$1" in
    --lenses)
        LENSES="$2"
        shift 2
        ;;
    --intent)
        INTENT="$2"
        shift 2
        ;;
    --diff-file)
        DIFF_FILE="$2"
        shift 2
        ;;
    --timeout)
        TIMEOUT="$2"
        shift 2
        ;;
    --reviewer-model)
        EXPLICIT_REVIEWER_MODEL="$2"
        shift 2
        ;;
    --help | -h)
        sed -n '2,9p' "$0" | sed 's/^# \?//'
        exit 0
        ;;
    *)
        echo "unknown arg: $1" >&2
        exit 1
        ;;
    esac
done

[[ -z "$INTENT" ]] && {
    echo "error: --intent required" >&2
    exit 1
}

# detect current runner: if/elif preserves CODEX_CI precedence over CLAUDECODE
current_runner=""
if [[ -n "${CODEX_CI:-}" ]]; then
    current_runner="codex"
elif [[ -n "${CLAUDECODE:-}" ]]; then
    current_runner="claude"
fi

# set reviewer model: validate explicit override against current runner; else auto-detect
if [[ -n "$EXPLICIT_REVIEWER_MODEL" ]]; then
    [[ "$EXPLICIT_REVIEWER_MODEL" == "claude" || "$EXPLICIT_REVIEWER_MODEL" == "codex" ]] || {
        echo "error: --reviewer-model must be claude or codex" >&2
        exit 1
    }
    if [[ -n "$current_runner" && "$EXPLICIT_REVIEWER_MODEL" == "$current_runner" ]]; then
        echo "error: --reviewer-model '$EXPLICIT_REVIEWER_MODEL' matches current runner — same-model review forbidden" >&2
        exit 1
    fi
    REVIEWER_MODEL="$EXPLICIT_REVIEWER_MODEL"
elif [[ "$current_runner" == "codex" ]]; then
    REVIEWER_MODEL="claude"
elif [[ "$current_runner" == "claude" ]]; then
    REVIEWER_MODEL="codex"
else
    REVIEWER_MODEL="claude" # manual invocation outside either model
fi

REVIEW_DIR=$(mktemp -d /tmp/adversarial-review.XXXXXX)
trap '/bin/rm -rf "$REVIEW_DIR"' EXIT

if [[ -n "$DIFF_FILE" ]]; then
    DIFF_CONTENT=$(cat "$DIFF_FILE")
else
    # single canonical diff: all uncommitted changes vs HEAD
    DIFF_CONTENT=$(git diff HEAD 2>/dev/null || true)
    # include untracked regular files under 100KB (git ls-files --others already filters via gitignore)
    while IFS= read -r -d '' f; do
        [[ -f "$f" ]] || continue # skip symlinks, devices, pipes, fifos
        local_size=$(wc -c <"$f" 2>/dev/null || echo 0)
        if [[ $local_size -gt 102400 ]]; then
            DIFF_CONTENT+=$'\n=== new untracked file: '"$f"' (skipped: '"$local_size"' bytes) ==='$'\n'
        else
            DIFF_CONTENT+=$'\n=== new untracked file: '"$f"' ==='$'\n'
            DIFF_CONTENT+=$(cat "$f" 2>/dev/null || true)
        fi
    done < <(git ls-files --others --exclude-standard -z 2>/dev/null || true)
fi

# enforce 200KB byte cap on total payload (write to temp, measure bytes, truncate by bytes)
diff_raw="$REVIEW_DIR/diff.raw"
printf '%s' "$DIFF_CONTENT" >"$diff_raw"
diff_bytes=$(wc -c <"$diff_raw")
if [[ $diff_bytes -gt $MAX_DIFF_BYTES ]]; then
    DIFF_CONTENT="$(head -c "$MAX_DIFF_BYTES" "$diff_raw")"$'\n... diff truncated at 200KB ...'
fi
rm -f "$diff_raw"

[[ -z "${DIFF_CONTENT// /}" ]] && echo "warning: diff is empty — reviewers will have nothing to review" >&2

# validate and normalize lens list
declare -a LENS_LIST=()
IFS=',' read -ra RAW_LENSES <<<"$LENSES"
for l in "${RAW_LENSES[@]}"; do
    l="${l// /}"
    case "$l" in
    skeptic | architect | minimalist) LENS_LIST+=("$l") ;;
    *)
        echo "error: unknown lens: $l (valid: skeptic, architect, minimalist)" >&2
        exit 1
        ;;
    esac
done
[[ ${#LENS_LIST[@]} -eq 0 ]] && {
    echo "error: no valid lenses specified" >&2
    exit 1
}

spawn_reviewer() {
    local lens="$1"
    local out="$REVIEW_DIR/$lens.md"
    local log="$REVIEW_DIR/$lens.log"
    local status_file="$REVIEW_DIR/$lens.status"

    # extract lens section: from ## Lens through next ## heading (portable awk, no head -n -1)
    local lens_cap
    lens_cap=$(echo "$lens" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
    local lens_text
    lens_text=$(awk "/^## $lens_cap/{found=1; next} found && /^## /{exit} found{print}" "$LENSES_FILE")
    [[ -z "$lens_text" ]] && {
        echo "error: lens '$lens' not found in $LENSES_FILE" >&2
        exit 1
    }

    local prompt
    prompt="INTENT: $INTENT

YOUR LENS — $(echo "$lens" | tr '[:lower:]' '[:upper:]'):
$lens_text

PRINCIPLES:
$(cat "$PRINCIPLES")

CHANGES UNDER REVIEW:
$DIFF_CONTENT

INSTRUCTIONS: you are an adversarial reviewer. your job is to find real problems, not validate the work. be specific — cite files, lines, and concrete failure scenarios. rate each finding: high (blocks ship), medium (should fix), low (worth noting). write findings as a numbered markdown list. do not run any tools or make any changes."

    # subshell with set +e: ensures status file is always written even on reviewer failure.
    # set -m (main script) gives this subshell its own process group = kill -- -$pid kills all children.
    if [[ "$REVIEWER_MODEL" == "codex" ]]; then
        (
            set +e
            command codex exec --skip-git-repo-check --ephemeral -s read-only \
                -o "$out" "$prompt" >"$log" 2>&1
            echo $? >"$status_file"
        ) &
    else
        (
            set +e
            env -u CLAUDECODE command claude --dangerously-skip-permissions \
                --model claude-sonnet-4-6 --permission-mode plan -p "$prompt" \
                >"$out" 2>"$log"
            echo $? >"$status_file"
        ) &
    fi
    echo $!
}

declare -a PIDS=()

echo "=== adversarial review starting ===" >&2
echo "model: $REVIEWER_MODEL | lenses: $LENSES | timeout: ${TIMEOUT}s" >&2

for lens in "${LENS_LIST[@]}"; do
    pid=$(spawn_reviewer "$lens")
    PIDS+=("$pid")
    echo "spawned $lens reviewer (pid $pid)" >&2
done

# poll for completion with deadline (macOS-safe: no tail --pid)
deadline=$((SECONDS + TIMEOUT))
remaining=("${PIDS[@]}")
while [[ ${#remaining[@]} -gt 0 && $SECONDS -lt $deadline ]]; do
    sleep 10
    still_running=()
    for pid in "${remaining[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            still_running+=("$pid")
        fi
    done
    remaining=("${still_running[@]}")
done

# kill any still-running reviewers: signal whole process group (set -m gave each its own pgid)
if [[ ${#remaining[@]} -gt 0 ]]; then
    echo "=== timeout: killing ${#remaining[@]} reviewer(s) ===" >&2
    for pid in "${remaining[@]}"; do
        kill -- -"$pid" 2>/dev/null || true
    done
    sleep 2
    for pid in "${remaining[@]}"; do
        kill -9 -- -"$pid" 2>/dev/null || true
    done
    # print only lenses that fully completed before timeout (status_file present = exit code written)
    for lens in "${LENS_LIST[@]}"; do
        out="$REVIEW_DIR/$lens.md"
        status_file="$REVIEW_DIR/$lens.status"
        if [[ -f "$status_file" && -s "$out" ]]; then
            echo "=== $lens reviewer findings (completed before timeout) ==="
            cat "$out"
        fi
    done
    echo "REVIEWER TIMEOUT after ${TIMEOUT}s"
    exit 2
fi

# wait for subshells to finish writing status files
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

# validate outputs and collect findings
exit_code=0
for lens in "${LENS_LIST[@]}"; do
    out="$REVIEW_DIR/$lens.md"
    log="$REVIEW_DIR/$lens.log"
    status_file="$REVIEW_DIR/$lens.status"
    reviewer_exit=$(cat "$status_file" 2>/dev/null || echo "1")
    if [[ ! -s "$out" ]]; then
        echo "=== REVIEWER FAILED: $lens ==="
        echo "exit code: $reviewer_exit"
        echo "stderr log:"
        cat "$log" 2>/dev/null || echo "(no log)"
        exit_code=1
    else
        if [[ "$reviewer_exit" -ne 0 ]]; then
            echo "=== $lens reviewer findings (exit $reviewer_exit) ==="
            exit_code=1
        else
            echo "=== $lens reviewer findings ==="
        fi
        cat "$out"
    fi
done

echo "=== review complete ===" >&2

# write fingerprinted marker so stop hook knows this exact state was reviewed
if [[ $exit_code -eq 0 ]]; then
    _repo=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    _sha() { shasum -a 256 2>/dev/null || sha256sum; }
    _marker="/tmp/ar-$(printf '%s' "$_repo" | _sha | cut -d' ' -f1)"
    {
        git diff HEAD 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null | sort | while IFS= read -r f; do
            printf '=== %s ===\n' "$f"
            cat "$f" 2>/dev/null
        done
    } | _sha | cut -d' ' -f1 >"$_marker"
fi

exit $exit_code
