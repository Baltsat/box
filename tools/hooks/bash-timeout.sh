#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
[[ -z "$cmd" ]] && exit 0

# skip background commands
bg=$(printf '%s' "$INPUT" | jq -r '.tool_input.run_in_background // false')
[[ "$bg" == "true" ]] && exit 0

# skip heredocs
[[ "$cmd" == *'<<'* ]] && exit 0

# skip if already wrapped
[[ "$cmd" =~ ^[[:space:]]*(timeout|gtimeout) ]] && exit 0

# strip tokf prefix for pattern matching (tokf hook runs before us)
match_cmd="$cmd"
[[ "$match_cmd" =~ ^tokf\ run\ (.+) ]] && match_cmd="${BASH_REMATCH[1]}"

first="${match_cmd%% *}"

# skip fast commands
case "$first" in
git)
    case "$match_cmd" in
    git\ status* | git\ log* | git\ diff* | git\ branch* | git\ show* | \
        git\ rev-parse* | git\ remote* | git\ config* | git\ tag* | \
        git\ stash\ list* | git\ ls-files* | git\ blame* | git\ name-rev*)
        exit 0
        ;;
    esac
    ;;
ls | tree | eza | cat | head | tail | wc | file | stat | du | \
    echo | printf | sed | awk | jq | sort | uniq | cut | tr | tee | \
    rg | fd | fzf | ag | \
    which | type | command | uname | hostname | whoami | date | pwd | env | \
    touch | mkdir | cp | mv | ln | chmod | chown | basename | dirname | realpath | readlink | \
    pbcopy | pbpaste | xclip | xsel | \
    cd | pushd | popd | read | source | export | test | true | false | exit | return | sleep | \
    vim | nvim | nano | emacs | less | more | bat | set | unset)
    exit 0
    ;;
esac

# skip dev servers and watchers
case "$match_cmd" in
*npm\ run\ dev* | *npm\ run\ start* | *npm\ start* | \
    *bun\ dev* | *bun\ run\ dev* | *bun\ run\ start* | \
    *yarn\ dev* | *yarn\ start* | \
    *pnpm\ dev* | *pnpm\ start* | \
    *flask\ run* | *uvicorn\ * | *gunicorn\ * | *hypercorn\ * | \
    *python*-m\ http.server* | \
    *next\ dev* | *vite\ * | \
    *--watch* | *--serve*)
    exit 0
    ;;
esac

# find timeout binary
TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout"
[[ -z "$TIMEOUT_BIN" ]] && command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN="gtimeout"
[[ -z "$TIMEOUT_BIN" ]] && exit 0

# tier 3: 600s — docker, nix, cargo install, brew
tier=0
case "$match_cmd" in
docker\ build* | docker\ push* | docker\ pull* | docker\ compose\ build* | \
    podman\ build* | podman\ push* | podman\ pull* | \
    nix\ build* | nix\ flake* | nix-build* | \
    cargo\ install* | \
    brew\ install* | brew\ upgrade* | \
    *setup.sh*)
    tier=600
    ;;
esac

# tier 2: 300s — builds, tests, clones
[[ $tier -eq 0 ]] && case "$match_cmd" in
cargo\ build* | cargo\ test* | cargo\ check* | cargo\ clippy* | \
    go\ build* | go\ test* | \
    pytest* | uv\ run\ pytest* | \
    make | make\ * | \
    tsc | tsc\ * | \
    git\ clone* | git\ pull* | git\ fetch* | \
    npm\ test* | npm\ run\ build* | npm\ run\ test* | \
    npx\ * | bunx\ *)
    tier=300
    ;;
esac

# tier 1: 120s — package installs
[[ $tier -eq 0 ]] && case "$match_cmd" in
npm\ install* | npm\ ci* | \
    bun\ install* | bun\ add* | \
    yarn\ install* | yarn\ add* | \
    pnpm\ install* | pnpm\ add* | \
    pip\ install* | pip3\ install* | uv\ pip\ install* | \
    go\ get* | go\ mod\ *)
    tier=120
    ;;
esac

[[ $tier -eq 0 ]] && exit 0

new_cmd="$TIMEOUT_BIN ${tier}s $cmd"

jq -n --arg cmd "$new_cmd" '{
  "hookSpecificOutput": {
    "permissionDecision": "allow",
    "updatedInput": {"command": $cmd}
  }
}'
