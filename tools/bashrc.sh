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

    # Auth reminders
    if command -v gh &>/dev/null && ! gh auth status &>/dev/null 2>&1; then
        echo "[box] github cli not authenticated. run: gh auth login"
    fi
    if command -v happy &>/dev/null && ! happy auth status &>/dev/null 2>&1; then
        echo "[box] happy-coder not authenticated. run: happy auth"
    fi
    if command -v omnara &>/dev/null; then
        echo "[box] omnara installed. run: omnara login"
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
