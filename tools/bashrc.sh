#!/usr/bin/env bash
# Linux server bashrc for box
# Symlinked to ~/.bashrc on Linux

# Exit if not interactive
case $- in
*i*) ;;
*) return ;;
esac

# =============================================================================
# SHELL OPTIONS
# =============================================================================
HISTCONTROL=ignoreboth
HISTSIZE=100000
HISTFILESIZE=200000
shopt -s histappend
shopt -s checkwinsize

# Silence macOS bash deprecation warning (if somehow on mac)
export BASH_SILENCE_DEPRECATION_WARNING=1

# =============================================================================
# PATH
# =============================================================================
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.omnara/bin:$PATH"

# =============================================================================
# NIX
# =============================================================================
if [[ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

# =============================================================================
# ONE-TIME AUTO-SETUP (delete ~/.box_setup_done to re-run)
# =============================================================================
_box_first_time_setup() {
    local lock_file="$HOME/.box_setup_done"
    [[ -f "$lock_file" ]] && return 0

    echo "[box] first-time setup detected..."
    local failed=0

    # Helper
    _install_apt() {
        local pkg="$1"
        if ! command -v "$pkg" &>/dev/null && command -v apt &>/dev/null; then
            echo "[box] installing $pkg..."
            sudo apt-get update -qq && sudo apt-get install -y "$pkg" && echo "[box] $pkg installed" || failed=1
        fi
    }

    # Essential tools
    _install_apt git
    _install_apt tmux
    _install_apt curl
    _install_apt jq

    # GitHub CLI
    if ! command -v gh &>/dev/null && command -v apt &>/dev/null; then
        echo "[box] installing github cli..."
        (
            type -p wget >/dev/null || sudo apt-get install wget -y
            sudo mkdir -p -m 755 /etc/apt/keyrings
            wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
            sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
            sudo apt-get update -qq && sudo apt-get install gh -y
        ) && echo "[box] github cli installed" || failed=1
    fi

    # NVM + Node
    if [[ ! -d "$HOME/.nvm" ]]; then
        echo "[box] installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh 2>/dev/null | bash >/dev/null 2>&1
        if [[ -d "$HOME/.nvm" ]]; then
            export NVM_DIR="$HOME/.nvm"
            # shellcheck source=/dev/null
            [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
            echo "[box] installing node lts..."
            nvm install --lts >/dev/null 2>&1 && echo "[box] node installed"
        fi
    fi

    # TPM (Tmux Plugin Manager)
    if command -v tmux &>/dev/null && [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
        echo "[box] installing tpm..."
        git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm 2>/dev/null && echo "[box] tpm installed"
    fi

    # Create ~/.tmux.conf if missing
    if command -v tmux &>/dev/null && [[ ! -f "$HOME/.tmux.conf" ]]; then
        echo "[box] creating tmux.conf..."
        cat >"$HOME/.tmux.conf" <<'TMUX_CONF'
# Box tmux configuration
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 50000
set -sg escape-time 10
set -g default-terminal "screen-256color"

# Status bar
set -g status-style 'bg=#333333 fg=#ffffff'
set -g status-left-length 30
set -g status-right-length 50
set -g status-left '#[fg=#00ff00][#S] '
set -g status-right '#[fg=#888888]%Y-%m-%d %H:%M'
setw -g window-status-current-style 'fg=#00ff00 bold'
setw -g window-status-style 'fg=#888888'

# Splits (| and -)
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Vim-style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# Plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @resurrect-capture-pane-contents 'on'
set -g @continuum-restore 'on'
set -g @continuum-save-interval '5'

run '~/.tmux/plugins/tpm/tpm'
TMUX_CONF
        echo "[box] tmux.conf created! run: tmux, then prefix+I to install plugins"
    fi

    # npm global packages
    if command -v npm &>/dev/null; then
        for pkg in "@anthropic-ai/claude-code:claude" "repomix:repomix" "happy-coder:happy"; do
            local name="${pkg%%:*}"
            local cmd="${pkg##*:}"
            if ! command -v "$cmd" &>/dev/null; then
                echo "[box] installing $name..."
                npm install -g "$name" 2>/dev/null && echo "[box] $name installed"
            fi
        done
    fi

    # Omnara (AI agent control platform)
    if ! command -v omnara &>/dev/null; then
        echo "[box] installing omnara..."
        curl -fsSL https://omnara.com/install/install.sh 2>/dev/null | bash >/dev/null 2>&1
        # Add to PATH if installed
        [[ -d "$HOME/.omnara/bin" ]] && export PATH="$HOME/.omnara/bin:$PATH"
        command -v omnara &>/dev/null && echo "[box] omnara installed"
    fi

    # Auth reminders (prominent banner)
    local need_auth=()
    command -v gh &>/dev/null && ! gh auth status &>/dev/null 2>&1 && need_auth+=("gh auth login")
    command -v happy &>/dev/null && ! happy auth status &>/dev/null 2>&1 && need_auth+=("happy auth")
    command -v omnara &>/dev/null && [[ ! -f "$HOME/.omnara/auth.json" ]] && need_auth+=("omnara auth")

    if [[ ${#need_auth[@]} -gt 0 ]]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  📋 MANUAL AUTH REQUIRED (one-time per machine)              ║"
        echo "╠══════════════════════════════════════════════════════════════╣"
        for cmd in "${need_auth[@]}"; do
            printf "║  → %-58s ║\n" "$cmd"
        done
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
    fi

    # Create lock file
    if [[ $failed -eq 0 ]]; then
        touch "$lock_file"
        echo "[box] setup complete!"
    else
        echo "[box] setup had errors, will retry next time"
    fi
}

_box_first_time_setup

# =============================================================================
# NVM (load after setup)
# =============================================================================
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
# shellcheck source=/dev/null
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"

# =============================================================================
# PROMPT (fallback if starship not available)
# =============================================================================
if ! command -v starship &>/dev/null; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi

# =============================================================================
# BASH COMPLETION
# =============================================================================
if ! shopt -oq posix; then
    if [[ -f /usr/share/bash-completion/bash_completion ]]; then
        . /usr/share/bash-completion/bash_completion
    elif [[ -f /etc/bash_completion ]]; then
        . /etc/bash_completion
    fi
fi

# =============================================================================
# BOX ALIASES & TOOLS
# =============================================================================
BOX_DIR="${BOX_DIR:-$HOME/box}"

# Source shared aliases
if [[ -f "$BOX_DIR/tools/aliases.sh" ]]; then
    # shellcheck source=/dev/null
    . "$BOX_DIR/tools/aliases.sh"
fi

# Initialize tools (zoxide, direnv, starship, fzf)
if command -v init_box_tools &>/dev/null; then
    init_box_tools
fi

# =============================================================================
# ENVIRONMENT
# =============================================================================
# Load .env if exists (from box)
if [[ -f "$BOX_DIR/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    . "$BOX_DIR/.env"
    set +a
fi

# =============================================================================
# AUTO-UPDATE (once per day, background, non-blocking)
# =============================================================================
_box_auto_update() {
    local check_file="$HOME/.cache/box_last_update_check"
    local now
    now=$(date +%s)
    local last_check=0

    mkdir -p "$HOME/.cache"

    # Read last check time
    if [[ -f "$check_file" ]]; then
        last_check=$(cat "$check_file" 2>/dev/null || echo 0)
    fi

    # Check if 24 hours (86400 seconds) have passed
    if [[ $((now - last_check)) -gt 86400 ]]; then
        # Run updates in background
        (
            local log_file="$HOME/.cache/box_update.log"
            echo "[box] auto-update started: $(date)" >"$log_file"

            # === NPM Global Packages ===
            if command -v npm &>/dev/null; then
                echo "[box] updating npm globals..." >>"$log_file"
                npm update -g >>"$log_file" 2>&1 || true
            fi

            # === Homebrew (macOS only) ===
            if [[ "$(uname)" == "Darwin" ]] && command -v brew &>/dev/null; then
                echo "[box] updating homebrew..." >>"$log_file"
                brew update >>"$log_file" 2>&1 || true
                brew upgrade >>"$log_file" 2>&1 || true
                # Cleanup old versions (optional, saves disk)
                brew cleanup -s >>"$log_file" 2>&1 || true
            fi

            # === Nix Flake (if box uses nix) ===
            if command -v nix &>/dev/null && [[ -f "$HOME/box/flake.nix" ]]; then
                echo "[box] updating nix flake..." >>"$log_file"
                cd "$HOME/box" && nix flake update >>"$log_file" 2>&1 || true
                # Apply changes
                if [[ "$(uname)" == "Darwin" ]]; then
                    darwin-rebuild switch --flake "$HOME/box#macos" >>"$log_file" 2>&1 || true
                else
                    home-manager switch --flake "$HOME/box#linux-generic" -b backup >>"$log_file" 2>&1 || true
                fi
            fi

            # === Omnara self-update ===
            if command -v omnara &>/dev/null; then
                echo "[box] updating omnara..." >>"$log_file"
                omnara update >>"$log_file" 2>&1 || true
            fi

            echo "[box] auto-update finished: $(date)" >>"$log_file"
            echo "$now" >"$check_file"
        ) &
    fi
}

# Run auto-update check (non-blocking)
_box_auto_update

# =============================================================================
# HAPPY DAEMON AUTO-START
# =============================================================================
# Start happy daemon for mobile/web access if not running
if command -v happy &>/dev/null; then
    if [[ ! -f "$HOME/.happy/daemon.state.json" ]] || ! pgrep -f "happy.*daemon" >/dev/null 2>&1; then
        happy daemon start >/dev/null 2>&1 &
    fi
fi

# =============================================================================
# HAPPY SESSION - tmux + happy per directory
# =============================================================================
# Usage: hs [session-name]
# Creates tmux session with happy --yolo running in current directory
happy_session() {
    if ! command -v tmux &>/dev/null; then
        echo "tmux not installed"
        return 1
    fi

    local happy_cmd="happy --yolo"
    if ! command -v happy &>/dev/null; then
        echo "happy not found, using bash"
        happy_cmd="bash"
    fi

    local current_path
    current_path="$(realpath "$PWD")"
    local session_name="${1:-$(basename "$PWD" | tr ' .:-' '____')}"

    # Handle name collision with different paths
    if tmux has-session -t "$session_name" 2>/dev/null; then
        local session_path
        session_path=$(tmux display-message -p -t "$session_name" "#{pane_current_path}" 2>/dev/null)
        if [[ "$session_path" != "$current_path" ]]; then
            # Add parent dir to make unique
            local parent
            parent=$(basename "$(dirname "$current_path")" | tr ' .:-' '____')
            session_name="${parent}_${session_name}"
        fi
    fi

    if [[ -n "$TMUX" ]]; then
        # Inside tmux - switch or create
        local current_session
        current_session=$(tmux display-message -p '#S')
        if [[ "$current_session" == "$session_name" ]]; then
            echo "already in session: $session_name"
            return 0
        fi
        if tmux has-session -t "$session_name" 2>/dev/null; then
            tmux switch-client -t "$session_name"
        else
            tmux new-session -d -s "$session_name" -c "$current_path" "$happy_cmd"
            tmux switch-client -t "$session_name"
        fi
    else
        # Outside tmux - attach or create
        if tmux has-session -t "$session_name" 2>/dev/null; then
            tmux attach-session -t "$session_name"
        else
            tmux new-session -s "$session_name" -c "$current_path" "$happy_cmd"
        fi
    fi
}

alias hs='happy_session'

# =============================================================================
# TOOL ALIASES (Linux-specific overrides)
# =============================================================================
alias happy='happy --yolo'
alias claude='claude --dangerously-skip-permissions'
