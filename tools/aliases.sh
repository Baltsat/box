#!/usr/bin/env bash
# Shell aliases and functions for box
# Source this file in your .zshrc or .bashrc

# === Box Functions ===
box() { cd ~/box && ./setup.sh "$@"; }
secrets() { ~/box/tools/secrets.sh "$@"; }

# === Directory Navigation ===
alias zshconfig="vim ~/.zshrc"
alias zshsource="source ~/.zshrc"
alias ohmyzsh="cd ~/.oh-my-zsh"
alias sshhome="cd ~/.ssh"
alias sshconfig="vim ~/.ssh/config"
alias gitconfig="vim ~/.gitconfig"

# === Git Shortcuts ===
alias gs="git status"
alias gd="git diff"
alias gl="git log --oneline -20"
alias ga="git add"
alias gaa="git add ."
alias gc="git commit"
alias gp="git push"
alias gpf="git push -f"
alias gpl="git pull"
alias gco="git checkout"
alias gb="git branch"
alias gm="git merge"
alias gr="git restore"
alias grs="git restore --staged"

# Git log with graph
alias gitl="git log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

# Quick commit and push
# usage: gacp "commit message" or just gacp for "update"
gacp() {
    local msg="${*:-update}"
    git add . && git commit -m "$msg" && git push
}

# === File Listing (eza/ls) ===
if command -v eza &>/dev/null; then
    alias ls='eza'
    alias l='eza -la'
    alias ll='eza -laah --git --time-style=relative --sort=modified'
    alias la='eza -a'
    alias lt='eza --tree'
    alias ld='eza -laah --git --time-style=relative --sort=modified --only-dirs'
    alias lf='eza -laah --git --time-style=relative --sort=modified --only-files'
    tree() {
        local path="." depth=2
        for arg in "$@"; do
            [[ "$arg" =~ ^[0-9]+$ ]] && depth="$arg" || path="$arg"
        done
        eza --tree -a -L "$depth" "$path"
    }
else
    alias ls='ls -G'
    alias l='ls -lha'
    alias ll='ls -l'
    alias la='ls -a'
fi

# === Common Operations ===
alias c='clear'
alias t='trash'
alias etrash='empty-trash'
alias py='python3'
alias loc="npx sloc --format cli-table --format-option head --exclude 'build|\\.svg$|\\.xml' ./"
alias thispath='echo "Working Directory:\n$PWD\n\nReal Working Directory:\n$(pwd -P)"'

# === macOS Apps ===
alias safari='open -a "Safari"'
alias xcode='open -a "Xcode"'
alias preview='open -a "Preview"'

# === Claude ===
alias claude='claude --dangerously-skip-permissions'

# Claude-mem memory sync (between machines)
# Usage: mem-push <server> or mem-pull <server>
mem-push() {
    local server="${1:-}"
    [[ -z "$server" ]] && { echo "usage: mem-push <server>"; return 1; }
    echo "[claude-mem] pushing to $server..."
    rsync -avz --progress ~/.claude-mem/ "$server":~/.claude-mem/
}
mem-pull() {
    local server="${1:-}"
    [[ -z "$server" ]] && { echo "usage: mem-pull <server>"; return 1; }
    echo "[claude-mem] pulling from $server..."
    rsync -avz --progress "$server":~/.claude-mem/ ~/.claude-mem/
}
alias mem-status='du -sh ~/.claude-mem/ && ls -lah ~/.claude-mem/*.db'

# === Happy Coder (mobile/web access) ===
alias h='happy'
alias hs='happy status'
alias hd='happy daemon'

# === Omnara (AI agent control) ===
# Add omnara to PATH if installed
[[ -d "$HOME/.omnara/bin" ]] && export PATH="$HOME/.omnara/bin:$PATH"
alias om='omnara'
alias omd='omnara daemon'

# System context for Claude (used by c/cc wrappers)
sys() {
    echo "<repos>"
    repos 2>/dev/null
    echo "</repos>"
    echo ""
    [[ -f "$HOME/box/GLOBAL.md" ]] && cat "$HOME/box/GLOBAL.md"
    [[ -f "./CLAUDE.md" ]] && {
        echo ""
        cat "./CLAUDE.md"
    }
}

# Claude with auto-context (cl = claude, clc = claude continue)
cl() {
    command claude --dangerously-skip-permissions \
        --append-system-prompt "$(sys)" "$@"
}

clc() {
    command claude --dangerously-skip-permissions \
        --append-system-prompt "$(sys)" -c "$@"
}

# === Zoxide (smart cd) ===
if command -v zoxide &>/dev/null; then
    alias z='zoxide query'
    alias zi='zoxide query -i'
fi

# === Direnv ===
alias da='direnv allow .'

# === Git UI ===
alias gr='gitui'

# === Nix ===
# Quick nix shell with packages
ns() {
    local pkgs=()
    for arg in "$@"; do
        pkgs+=("nixpkgs#$arg")
    done
    nix shell --impure "${pkgs[@]}"
}

# === Utility Functions ===

# Copy all files content to clipboard (for sharing with AI)
displayall() {
    (tree -I "node_modules|dist" && echo "\n\nFile content:" && find . -type f ! -path "./dist/*" ! -path "./.git/*" ! -path "./node_modules/*" -exec sh -c 'echo "\n--- {} ---"; cat "{}"' \;) | pbcopy
}

# Find repos in home directory
repos() {
    fd -H -t d '^\.git$' ~ --max-depth 2 2>/dev/null | sed 's/\/\.git\/$//'
}

# === Brew wrapper (reminder to update box) ===
brew() {
    /opt/homebrew/bin/brew "$@"
    local ret=$?

    # remind after install/uninstall
    case "$1" in
    install | uninstall | remove | reinstall)
        echo ""
        echo "⚠️  remember to update ~/box/macos.nix!"
        echo "   run: box-brew (to see drift)"
        ;;
    esac

    return $ret
}

# === Box Protection ===
# Warn before dangerous operations on ~/box
_box_protected_rm() {
    local box_path="$HOME/box"
    for arg in "$@"; do
        local resolved="${arg/#\~/$HOME}"
        if [[ "$resolved" == "$box_path" || "$resolved" == "$box_path/" ]]; then
            echo "⚠️  BLOCKED: refusing to delete ~/box"
            echo "   this would break all your symlinked configs!"
            echo "   if you REALLY need to: /bin/rm -rf ~/box"
            return 1
        fi
    done
    /bin/rm "$@"
}

_box_protected_mv() {
    local box_path="$HOME/box"
    for arg in "$@"; do
        local resolved="${arg/#\~/$HOME}"
        if [[ "$resolved" == "$box_path" || "$resolved" == "$box_path/" ]]; then
            echo "⚠️  WARNING: moving ~/box will break symlinks!"
            echo "   after moving, run: cd <new-location> && bun script/files.ts"
            echo "   if you're sure: /bin/mv $*"
            return 1
        fi
    done
    /bin/mv "$@"
}

alias rm='_box_protected_rm'
alias mv='_box_protected_mv'

# Check brew drift (packages installed but not in macos.nix)
box-brew() {
    echo "=== formulas not in macos.nix ==="
    comm -23 <(brew leaves | sort) <(grep -oE '"[a-z][^"]*"' ~/box/macos.nix | tr -d '"' | sort) 2>/dev/null
    echo ""
    echo "=== casks not in macos.nix ==="
    comm -23 <(brew list --cask | sort) <(grep -oE '"[a-z][^"]*"' ~/box/macos.nix | tr -d '"' | sort) 2>/dev/null
    echo ""
    echo "add missing packages to ~/box/macos.nix"
}

# Check symlink health
box-check() {
    echo "checking ~/box symlinks..."
    local broken=0
    for link in ~/.gitconfig ~/.config/starship.toml ~/.ssh/config ~/.config/gh/config.yml; do
        if [[ -L "$link" ]]; then
            local target
            target=$(readlink "$link")
            if [[ ! -e "$target" ]]; then
                echo "✗ BROKEN: $link → $target"
                ((broken++))
            fi
        fi
    done
    if [[ $broken -eq 0 ]]; then
        echo "✓ all symlinks OK"
    else
        echo "⚠ $broken broken symlinks. run: cd ~/box && bun script/files.ts"
    fi
}

# === Cloudflare Tunnel ===
# Quick tunnel localhost to internet
dev() {
    local port="${1:-3000}"
    if ! command -v cloudflared &>/dev/null; then
        echo "cloudflared not installed. run: brew install cloudflared"
        return 1
    fi
    echo "[dev] tunneling localhost:$port..."
    cloudflared tunnel --url "http://localhost:$port"
}

# === Fancy Quotes ===
# Convert straight quotes to curly quotes in files
fancy() {
    [[ -f ~/box/tools/fancy.py ]] && uv run ~/box/tools/fancy.py "$@"
}

# === Quick Note to Clipboard ===
# Open temp file in editor, copy to clipboard on save
ans() {
    local f
    f=$(mktemp)
    trap "rm -f $f" EXIT
    ${EDITOR:-vim} "$f" && pbcopy <"$f"
}

# === Linux: sudo with nix PATH ===
# Fix sudo not seeing Nix binaries on Linux
if [[ "$(uname)" == "Linux" ]]; then
    sudo() {
        /usr/bin/sudo env "PATH=$PATH" "$@"
    }
fi

# === Tmux Session per Directory ===
# Usage: ts [session-name]
# Creates/attaches to tmux session named after current directory
ts() {
    if ! command -v tmux &>/dev/null; then
        echo "tmux not installed"
        return 1
    fi

    local session_name="${1:-$(basename "$PWD" | tr ' .:-' '____')}"

    if [[ -n "$TMUX" ]]; then
        # Inside tmux - switch or create
        if tmux has-session -t "$session_name" 2>/dev/null; then
            tmux switch-client -t "$session_name"
        else
            tmux new-session -d -s "$session_name" -c "$PWD"
            tmux switch-client -t "$session_name"
        fi
    else
        # Outside tmux - attach or create
        if tmux has-session -t "$session_name" 2>/dev/null; then
            tmux attach-session -t "$session_name"
        else
            tmux new-session -s "$session_name" -c "$PWD"
        fi
    fi
}

# List tmux sessions
alias tl='tmux list-sessions 2>/dev/null || echo "no sessions"'

# Kill tmux session
tk() {
    local session="${1:-$(tmux display-message -p '#S' 2>/dev/null)}"
    [[ -n "$session" ]] && tmux kill-session -t "$session"
}

# === Tool Initialization (call once in shell rc) ===
init_box_tools() {
    command -v zoxide &>/dev/null && eval "$(zoxide init ${SHELL##*/})"
    command -v direnv &>/dev/null && eval "$(direnv hook ${SHELL##*/})"
    # Starship: only on macOS (Warp terminal on Linux has its own prompt)
    if [[ "$(uname)" == "Darwin" ]]; then
        command -v starship &>/dev/null && eval "$(starship init ${SHELL##*/})"
    fi
    command -v fzf &>/dev/null && eval "$(fzf --${SHELL##*/})"

    # Run auto-update check
    _box_auto_update 2>/dev/null &
}

# === Auto-Update (once per day, background, non-blocking) ===
_box_auto_update() {
    local check_file="$HOME/.cache/box_last_update_check"
    local now
    now=$(date +%s)
    local last_check=0

    mkdir -p "$HOME/.cache"

    # Read last check time
    [[ -f "$check_file" ]] && last_check=$(cat "$check_file" 2>/dev/null || echo 0)

    # Check if 24 hours (86400 seconds) have passed
    [[ $((now - last_check)) -le 86400 ]] && return 0

    local log_file="$HOME/.cache/box_update.log"
    echo "[box] auto-update started: $(date)" >"$log_file"

    # Claude Code
    if command -v claude &>/dev/null && command -v npm &>/dev/null; then
        echo "[box] checking claude-code..." >>"$log_file"
        npm update -g @anthropic-ai/claude-code >>"$log_file" 2>&1 || true
    fi

    # Claude Code Plugins (update all installed plugins)
    if command -v claude &>/dev/null; then
        echo "[box] checking claude plugins..." >>"$log_file"
        claude plugin update --all >>"$log_file" 2>&1 || true
    fi

    # Codex (OpenAI)
    if command -v codex &>/dev/null && command -v npm &>/dev/null; then
        echo "[box] checking codex..." >>"$log_file"
        npm update -g @openai/codex >>"$log_file" 2>&1 || true
    fi

    # Happy Coder
    if command -v happy &>/dev/null && command -v npm &>/dev/null; then
        echo "[box] checking happy-coder..." >>"$log_file"
        npm update -g happy-coder >>"$log_file" 2>&1 || true
    fi

    # Omnara
    if command -v omnara &>/dev/null; then
        echo "[box] checking omnara..." >>"$log_file"
        omnara update >>"$log_file" 2>&1 || true
    fi

    # Gemini CLI
    if command -v gemini &>/dev/null && command -v npm &>/dev/null; then
        echo "[box] checking gemini-cli..." >>"$log_file"
        npm update -g @google/gemini-cli >>"$log_file" 2>&1 || true
    fi

    # Qwen Code
    if command -v qwen &>/dev/null && command -v npm &>/dev/null; then
        echo "[box] checking qwen-code..." >>"$log_file"
        npm update -g @qwen-code/qwen-code@latest >>"$log_file" 2>&1 || true
    fi

    # Repomix
    if command -v repomix &>/dev/null && command -v npm &>/dev/null; then
        echo "[box] checking repomix..." >>"$log_file"
        npm update -g repomix >>"$log_file" 2>&1 || true
    fi

    # ccusage (Claude Code usage tracker)
    if command -v ccusage &>/dev/null && command -v bun &>/dev/null; then
        echo "[box] checking ccusage..." >>"$log_file"
        bun update -g ccusage >>"$log_file" 2>&1 || true
    fi

    # Homebrew (macOS)
    if [[ "$(uname)" == "Darwin" ]] && command -v brew &>/dev/null; then
        echo "[box] updating homebrew..." >>"$log_file"
        brew update >>"$log_file" 2>&1 || true
        brew upgrade >>"$log_file" 2>&1 || true
        brew cleanup -s >>"$log_file" 2>&1 || true
    fi

    echo "[box] auto-update finished: $(date)" >>"$log_file"
    echo "$now" >"$check_file"
}
