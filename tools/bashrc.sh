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

    # Create/update ~/.tmux.conf (always overwrite with latest)
    if command -v tmux &>/dev/null; then
        echo "[box] writing tmux.conf..."
        cat >"$HOME/.tmux.conf" <<'TMUX_CONF'
# Box tmux configuration

# === Core Settings ===
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 50000
set -sg escape-time 0
set -g focus-events on

# Terminal & colors
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"

# === Status Bar ===
set -g status-style 'bg=#1a1a2e fg=#eaeaea'
set -g status-left-length 40
set -g status-right-length 60
set -g status-left '#[fg=#00d9ff,bold][#S] '
set -g status-right '#[fg=#888888]#{?client_prefix,#[fg=#ff6b6b]⌨ ,}%H:%M'
setw -g window-status-current-style 'fg=#00d9ff bold'
setw -g window-status-style 'fg=#666666'
setw -g window-status-format ' #I:#W '
setw -g window-status-current-format ' #I:#W '

# === Key Bindings ===
# Splits (| and -)
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Vim-style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Resize panes with vim keys
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Quick window switching
bind -r n next-window
bind -r p previous-window

# Reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# === Copy Mode (vim-style) ===
setw -g mode-keys vi
bind Enter copy-mode
bind -T copy-mode-vi v send-keys -X begin-selection
bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
bind -T copy-mode-vi Escape send-keys -X cancel

# === Plugins ===
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# Plugin settings
set -g @resurrect-capture-pane-contents 'on'
set -g @continuum-restore 'on'
set -g @continuum-save-interval '5'
set -g @yank_selection_mouse 'clipboard'

run '~/.tmux/plugins/tpm/tpm'
TMUX_CONF
        echo "[box] tmux.conf created! run: tmux, then prefix+I to install plugins"
    fi

    # npm global packages
    if command -v npm &>/dev/null; then
        for pkg in "@anthropic-ai/claude-code:claude" "@openai/codex:codex" "repomix:repomix" "happy-coder:happy"; do
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

    # Hawaii CLI (preference-model internal tool)
    if command -v uv &>/dev/null && [[ -n "${PYX_API_KEY:-}" ]]; then
        if ! command -v hawaii &>/dev/null; then
            echo "[box] installing hawaii cli..."
            UV_INDEX="https://api.pyx.dev/simple/preference-model/main" uv tool install pm-hawaii-cli 2>/dev/null && echo "[box] hawaii installed"
        fi
        # Auto-login hawaii (headless, uses PYX_API_KEY)
        if command -v hawaii &>/dev/null && ! hawaii auth status &>/dev/null 2>&1; then
            echo "[box] authenticating hawaii cli..."
            hawaii auth login --no-browser 2>/dev/null && echo "[box] hawaii authenticated!" || true
        fi
    fi

    # Auto-auth GitHub if GH_TOKEN available
    if command -v gh &>/dev/null && ! gh auth status &>/dev/null 2>&1; then
        if [[ -n "${GH_TOKEN:-}" ]]; then
            echo "[box] auto-authenticating github cli..."
            echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null && echo "[box] github authenticated!" || true
        fi
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
# IMPORTANT: only set variables that are NOT already set (preserve existing credentials)
if [[ -f "$BOX_DIR/.env" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        # Remove leading/trailing whitespace from key
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        # Only export if not already set
        if [[ -z "${!key:-}" ]]; then
            export "$key=$value"
        fi
    done <"$BOX_DIR/.env"
fi

# UV index for preference-model packages (hawaii cli, etc.)
export UV_INDEX="https://api.pyx.dev/simple/preference-model/main"

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

# =============================================================================
# HAWAII CLI AUTO-UPDATE
# =============================================================================
_hawaii_auto_update() {
    local check_file="$HOME/.cache/hawaii_last_update_check"
    local now
    now=$(date +%s)
    local last_check=0

    [[ -f "$check_file" ]] && last_check=$(cat "$check_file" 2>/dev/null || echo 0)

    # Check once per day
    if [[ $((now - last_check)) -gt 86400 ]]; then
        (
            if command -v hawaii &>/dev/null; then
                local result
                result=$(hawaii self check 2>&1)
                if echo "$result" | grep -q "Update available"; then
                    echo ""
                    echo "[hawaii] update available - auto-updating..."
                    UV_INDEX="https://api.pyx.dev/simple/preference-model/main" uv tool upgrade pm-hawaii-cli 2>&1 | tail -3
                    echo "[hawaii] updated!"
                fi
            fi
            echo "$now" >"$check_file"
        ) &
    fi
}

# Run hawaii auto-update (non-blocking)
command -v hawaii &>/dev/null && _hawaii_auto_update

# =============================================================================
# CODE - Workspace management with tmux windows
# =============================================================================
CODE_HISTORY_FILE="$HOME/.code_history"

code() {
    local create_new=false
    local show_list=false
    local list_select=""
    local window_select=""
    local window_name=""
    local current_dir
    current_dir="$(pwd)"
    local dir_name
    dir_name="$(basename "$current_dir")"
    local prompt=""

    [[ "$dir_name" == "/" ]] && dir_name="root"
    [[ -z "$dir_name" ]] && dir_name="unknown"

    while [[ $# -gt 0 ]]; do
        case $1 in
        -n | --new)
            create_new=true
            shift
            ;;
        -l | --list)
            show_list=true
            shift
            [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]] && {
                list_select="$1"
                shift
            }
            ;;
        -w | --window)
            shift
            [[ $# -gt 0 ]] && {
                window_select="$1"
                shift
            } || {
                echo "error: -w requires window name"
                return 1
            }
            ;;
        @*)
            window_select="${1:1}"
            shift
            ;;
        -h | --help)
            cat <<'EOF'
CODE - Workspace management

USAGE: code [OPTIONS] [PROMPT]

  code              Open/continue workspace
  code "prompt"     Start with prompt
  code -n           New window
  code -l           List windows for current dir
  code -l N         Open Nth window
  code -w NAME      Open window by name
  code @NAME        Same as -w

ALIASES: c=code, cn=code -n, cl=code_list, ch=code_history
EOF
            return 0
            ;;
        *)
            prompt="$*"
            break
            ;;
        esac
    done

    # Helper: get windows for current directory
    _code_get_windows() {
        local current_dir="$1"
        [[ ! -f "$CODE_HISTORY_FILE" ]] && return 1
        declare -A shown_windows
        while IFS='|' read -r session window dir last_prompt; do
            if [[ "$dir" == "$current_dir" ]]; then
                local key="${session}:${window}"
                if [[ -z "${shown_windows[$key]}" ]]; then
                    shown_windows[$key]=1
                    local status="inactive"
                    if tmux has-session -t "$session" 2>/dev/null; then
                        tmux list-windows -t "$session" -F '#W' 2>/dev/null | grep -q "^${window}$" && status="active"
                    fi
                    echo "${session}|${window}|${status}|${last_prompt}"
                fi
            fi
        done < <(tac "$CODE_HISTORY_FILE" 2>/dev/null)
    }

    # Helper: switch to window
    _code_switch_to_window() {
        local target_session="$1" target_window="$2"
        if ! tmux has-session -t "$target_session" 2>/dev/null; then
            echo "error: session '$target_session' does not exist"
            return 1
        fi
        if ! tmux list-windows -t "$target_session" -F '#W' 2>/dev/null | grep -q "^${target_window}$"; then
            echo "error: window '$target_window' does not exist"
            return 1
        fi
        if [[ -z "$TMUX" ]]; then
            tmux attach-session -t "$target_session" \; select-window -t "$target_window"
        else
            local current_session
            current_session=$(tmux display-message -p '#S')
            if [[ "$current_session" == "$target_session" ]]; then
                tmux select-window -t "$target_window"
            else
                tmux switch-client -t "$target_session" \; select-window -t "$target_window"
            fi
        fi
    }

    # Handle -w/@: open by name
    if [[ -n "$window_select" ]]; then
        local found_session="" found_window=""
        while IFS='|' read -r session window status lprompt; do
            [[ "$window" == "$window_select" ]] && {
                found_session="$session"
                found_window="$window"
                break
            }
        done < <(_code_get_windows "$current_dir")

        if [[ -z "$found_session" ]] && [[ -f "$CODE_HISTORY_FILE" ]]; then
            while IFS='|' read -r session window dir lprompt; do
                if [[ "$window" == "$window_select" ]] && tmux has-session -t "$session" 2>/dev/null; then
                    tmux list-windows -t "$session" -F '#W' 2>/dev/null | grep -q "^${window}$" && {
                        found_session="$session"
                        found_window="$window"
                        break
                    }
                fi
            done < <(tac "$CODE_HISTORY_FILE" 2>/dev/null)
        fi

        [[ -n "$found_session" ]] && {
            _code_switch_to_window "$found_session" "$found_window"
            return $?
        }
        echo "error: window '$window_select' not found"
        return 1
    fi

    # Handle -l: list windows
    if [[ "$show_list" == true ]]; then
        [[ ! -f "$CODE_HISTORY_FILE" ]] && {
            echo "no history"
            return 1
        }
        local -a win_sessions=() win_names=() win_statuses=() win_prompts=()
        while IFS='|' read -r session window status lprompt; do
            win_sessions+=("$session")
            win_names+=("$window")
            win_statuses+=("$status")
            win_prompts+=("$lprompt")
        done < <(_code_get_windows "$current_dir")

        local total=${#win_names[@]}
        [[ $total -eq 0 ]] && {
            echo "no windows for this directory"
            return 1
        }

        if [[ -n "$list_select" ]]; then
            [[ "$list_select" -lt 1 ]] || [[ "$list_select" -gt $total ]] && {
                echo "invalid: 1-$total"
                return 1
            }
            local idx=$((list_select - 1))
            [[ "${win_statuses[$idx]}" != "active" ]] && {
                echo "window not active"
                return 1
            }
            _code_switch_to_window "${win_sessions[$idx]}" "${win_names[$idx]}"
            return $?
        fi

        echo "windows for: $(basename "$current_dir")"
        printf "%-3s | %-15s | %-23s | %-8s | %s\n" "#" "Session" "Window" "Status" "Prompt"
        echo "----|-----------------|-------------------------|----------|--------"
        for ((i = 0; i < total; i++)); do
            local dp="${win_prompts[$i]:-<interactive>}"
            [[ ${#dp} -gt 25 ]] && dp="${dp:0:22}..."
            printf "%-3s | %-15s | %-23s | %-8s | %s\n" "$((i + 1))" "${win_sessions[$i]}" "${win_names[$i]}" "${win_statuses[$i]}" "$dp"
        done
        return 0
    fi

    ! command -v tmux &>/dev/null && {
        echo "error: tmux not installed"
        return 1
    }

    local happy_base_cmd="happy --yolo"
    local happy_continue_cmd="happy --resume --yolo"
    ! command -v happy &>/dev/null && {
        [[ -n "$prompt" ]] && {
            echo "error: happy not found"
            return 1
        }
        happy_base_cmd="bash"
        happy_continue_cmd="bash"
    }

    local session_name
    session_name="$(echo "$dir_name" | tr ' .:-' '____')"

    # Outside tmux
    if [[ -z "$TMUX" ]]; then
        if [[ "$create_new" == true ]]; then
            local new_window="code-${dir_name}-$(date +%H%M%S)"
            if tmux has-session -t "$session_name" 2>/dev/null; then
                [[ -n "$prompt" ]] && tmux new-window -d -t "$session_name:" -n "$new_window" -c "$current_dir" "$happy_base_cmd '$prompt'" ||
                    tmux new-window -d -t "$session_name:" -n "$new_window" -c "$current_dir" "$happy_base_cmd"
                echo "${session_name}|${new_window}|${current_dir}|${prompt}" >>"$CODE_HISTORY_FILE"
                tmux attach-session -t "$session_name" \; select-window -t "$new_window"
            else
                [[ -n "$prompt" ]] && tmux new-session -s "$session_name" -n "$new_window" -c "$current_dir" "$happy_base_cmd '$prompt'" ||
                    tmux new-session -s "$session_name" -n "$new_window" -c "$current_dir" "$happy_base_cmd"
                echo "${session_name}|${new_window}|${current_dir}|${prompt}" >>"$CODE_HISTORY_FILE"
            fi
            return 0
        fi

        if tmux has-session -t "$session_name" 2>/dev/null; then
            local existing=()
            while IFS= read -r window; do
                local wp wc
                wp=$(tmux display-message -p -t "$session_name:$window" "#{pane_current_path}" 2>/dev/null)
                wc=$(tmux display-message -p -t "$session_name:$window" "#{pane_current_command}" 2>/dev/null)
                [[ "$wp" == "$current_dir" ]] && [[ "$wc" == *"happy"* ]] && existing+=("$window")
            done < <(tmux list-windows -t "$session_name" -F '#W' 2>/dev/null | grep '^code')

            if [[ ${#existing[@]} -gt 0 ]]; then
                tmux attach-session -t "$session_name:${existing[-1]}"
                echo "${session_name}|${existing[-1]}|${current_dir}|${prompt}" >>"$CODE_HISTORY_FILE"
            else
                local wn="code-${dir_name}"
                [[ -n "$prompt" ]] && tmux new-window -d -t "$session_name:" -n "$wn" -c "$current_dir" "happy --resume '$prompt'" ||
                    tmux new-window -d -t "$session_name:" -n "$wn" -c "$current_dir" "$happy_continue_cmd"
                echo "${session_name}|${wn}|${current_dir}|${prompt}" >>"$CODE_HISTORY_FILE"
                tmux attach-session -t "$session_name" \; select-window -t "$wn"
            fi
        else
            local wn="code-${dir_name}"
            [[ -n "$prompt" ]] && tmux new-session -s "$session_name" -n "$wn" -c "$current_dir" "$happy_base_cmd '$prompt'" ||
                tmux new-session -s "$session_name" -n "$wn" -c "$current_dir" "$happy_base_cmd"
            echo "${session_name}|${wn}|${current_dir}|${prompt}" >>"$CODE_HISTORY_FILE"
        fi
        return 0
    fi

    # Inside tmux
    local current_session
    current_session=$(tmux display-message -p '#S')

    if [[ "$create_new" == true ]]; then
        window_name="code-${dir_name}-$(date +%H%M%S)"
        tmux list-windows -F '#W' | grep -q "^${window_name}$" && window_name="${window_name}-$(date +%N | cut -c1-3)"
        [[ -n "$prompt" ]] && tmux new-window -n "$window_name" -c "$current_dir" "$happy_base_cmd '$prompt'" ||
            tmux new-window -n "$window_name" -c "$current_dir" "$happy_base_cmd"
        echo "${current_session}|${window_name}|${current_dir}|${prompt}" >>"$CODE_HISTORY_FILE"
    else
        local existing=()
        while IFS= read -r window; do
            local wp wc
            wp=$(tmux display-message -p -t "$window" "#{pane_current_path}" 2>/dev/null)
            wc=$(tmux display-message -p -t "$window" "#{pane_current_command}" 2>/dev/null)
            [[ "$wp" == "$current_dir" ]] && [[ "$wc" == *"happy"* ]] && existing+=("$window")
        done < <(tmux list-windows -F '#W' 2>/dev/null | grep '^code')

        if [[ ${#existing[@]} -gt 0 ]]; then
            tmux select-window -t "${existing[-1]}"
            echo "${current_session}|${existing[-1]}|${current_dir}|${prompt}" >>"$CODE_HISTORY_FILE"
        else
            window_name="code-${dir_name}"
            [[ -n "$prompt" ]] && tmux new-window -n "$window_name" -c "$current_dir" "happy --resume '$prompt'" ||
                tmux new-window -n "$window_name" -c "$current_dir" "$happy_continue_cmd"
            echo "${current_session}|${window_name}|${current_dir}|${prompt}" >>"$CODE_HISTORY_FILE"
        fi
    fi
}

code_list() {
    if ! tmux ls &>/dev/null; then
        echo "no tmux sessions"
        return 1
    fi
    if [[ -z "$TMUX" ]]; then
        echo "code windows (all sessions):"
        for session in $(tmux ls -F '#S' 2>/dev/null); do
            local windows
            windows=$(tmux list-windows -t "$session" -F '#W' 2>/dev/null | grep '^code')
            [[ -n "$windows" ]] && {
                echo "  $session:"
                echo "$windows" | sed 's/^/    /'
            }
        done
    else
        echo "code windows ($(tmux display-message -p '#S')):"
        tmux list-windows -F '#W' | grep '^code' | sed 's/^/  /'
    fi
}

code_clean() {
    if ! tmux ls &>/dev/null; then
        echo "no tmux sessions"
        return 1
    fi
    local count=0
    if [[ -z "$TMUX" ]]; then
        for session in $(tmux ls -F '#S' 2>/dev/null); do
            for window in $(tmux list-windows -t "$session" -F '#W' 2>/dev/null | grep '^code-'); do
                tmux kill-window -t "$session:$window" 2>/dev/null && ((count++))
            done
        done
    else
        for window in $(tmux list-windows -F '#W' | grep '^code-'); do
            tmux kill-window -t "$window" 2>/dev/null && ((count++))
        done
    fi
    echo "closed $count windows"
}

code_history() {
    [[ ! -f "$CODE_HISTORY_FILE" ]] && {
        echo "no history"
        return 1
    }
    echo "recent (newest first):"
    tail -20 "$CODE_HISTORY_FILE" | tac | while IFS='|' read -r session window dir lprompt; do
        local dp="${lprompt:-<interactive>}"
        [[ ${#dp} -gt 20 ]] && dp="${dp:0:17}..."
        printf "%-12s | %-20s | %-12s | %s\n" "$session" "$window" "$(basename "$dir")" "$dp"
    done | head -10
}

# Code aliases
alias c='code'
alias cn='code -n'
alias cl='code_list'
alias ch='code_history'
alias ccc='code_clean'
alias chc='rm -f "$CODE_HISTORY_FILE" && echo "history cleared"'
