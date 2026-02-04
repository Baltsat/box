#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log() { echo "[setup] $*"; }
die() {
    log "error: $*"
    exit 1
}
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# === Pre-cleanup (ensure fresh state) ===
# Remove invalid/empty age key so we get a fresh password prompt
AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
if [[ -f "$AGE_KEY_FILE" ]]; then
    if [[ ! -s "$AGE_KEY_FILE" ]] || ! grep -q "AGE-SECRET-KEY-" "$AGE_KEY_FILE" 2>/dev/null; then
        rm -f "$AGE_KEY_FILE"
    fi
fi

# === Nix Setup ===
source_nix() {
    local daemon_sh="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    local profile_sh="$HOME/.nix-profile/etc/profile.d/nix.sh"
    [[ -f $daemon_sh ]] && . "$daemon_sh" && return 0
    [[ -f $profile_sh ]] && . "$profile_sh" && return 0
    return 0
}

install_nix() {
    has_cmd nix && return 0
    log "installing nix via determinate systems installer"
    curl --proto '=https' --tlsv1.2 -sSf -L \
        https://install.determinate.systems/nix | sh -s -- install --no-confirm
    source_nix
    # Start nix daemon if not running (needed in containers)
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        if ! pgrep -x nix-daemon >/dev/null 2>&1; then
            log "starting nix daemon"
            sudo nix-daemon &
            sleep 2
        fi
    fi
    has_cmd nix || die "nix installation failed"
}

# === Homebrew Setup (macOS) ===
install_homebrew() {
    [[ "$(uname -s)" != "Darwin" ]] && return 0
    has_cmd brew && return 0
    log "installing homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
}

# === SOPS + AGE Commands ===
# Use nix run for one-time execution to avoid conflicts with home-manager
# After home-manager runs, age/sops will be in PATH from shared.nix
run_age() {
    if has_cmd age; then
        age "$@"
    elif has_cmd nix; then
        nix --extra-experimental-features 'nix-command flakes' run nixpkgs#age -- "$@"
    elif has_cmd brew; then
        brew install age >/dev/null 2>&1
        age "$@"
    else
        die "cannot run age: no package manager available"
    fi
}

run_sops() {
    if has_cmd sops; then
        sops "$@"
    elif has_cmd nix; then
        nix --extra-experimental-features 'nix-command flakes' run nixpkgs#sops -- "$@"
    elif has_cmd brew; then
        brew install sops >/dev/null 2>&1
        sops "$@"
    else
        die "cannot run sops: no package manager available"
    fi
}

# === Secrets Decryption ===
decrypt_secrets() {
    [[ ! -f "$SCRIPT_DIR/.env.sops" ]] && return 0
    [[ -f "$SCRIPT_DIR/.env" ]] && {
        log "secrets already decrypted (.env exists)"
        return 0
    }
    log "decrypting secrets with SOPS..."
    export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"

    # Check if key file exists AND is valid (non-empty, contains AGE-SECRET-KEY)
    local need_key=false
    if [[ ! -f "$SOPS_AGE_KEY_FILE" ]]; then
        need_key=true
    elif [[ ! -s "$SOPS_AGE_KEY_FILE" ]]; then
        log "age key file is empty, regenerating..."
        rm -f "$SOPS_AGE_KEY_FILE"
        need_key=true
    elif ! grep -q "AGE-SECRET-KEY-" "$SOPS_AGE_KEY_FILE" 2>/dev/null; then
        log "age key file is invalid, regenerating..."
        rm -f "$SOPS_AGE_KEY_FILE"
        need_key=true
    fi

    if [[ "$need_key" == "true" ]]; then
        # Try to decrypt age key from passphrase-protected file
        if [[ -f "$SCRIPT_DIR/tools/sops-key.age" ]]; then
            log "decrypting age key from sops-key.age..."
            log "enter your passphrase:"
            mkdir -p "$(dirname "$SOPS_AGE_KEY_FILE")"
            if ! run_age -d "$SCRIPT_DIR/tools/sops-key.age" >"$SOPS_AGE_KEY_FILE"; then
                rm -f "$SOPS_AGE_KEY_FILE"
                rm -rf "$SCRIPT_DIR" # remove ~/box so git clone works again
                rm -f "$HOME/.box_setup_done"
                echo ""
                echo "wrong passphrase. run again:"
                echo "  git clone https://github.com/Baltsat/box.git ~/box && ~/box/setup.sh"
                echo ""
                exit 1
            fi
            chmod 600 "$SOPS_AGE_KEY_FILE"
            log "age key restored"
        else
            warn "no age key found at $SOPS_AGE_KEY_FILE"
            warn "run: mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt"
            return 1
        fi
    fi
    run_sops --decrypt --input-type dotenv --output-type dotenv "$SCRIPT_DIR/.env.sops" >"$SCRIPT_DIR/.env"
    log "secrets decrypted to .env"
}

# === Clean up conflicting nix profile packages ===
cleanup_nix_profile() {
    # Remove packages that conflict with home-manager's shared.nix
    # These may have been installed by previous setup.sh runs or manually
    local conflicting_pkgs=(age sops)

    for pkg in "${conflicting_pkgs[@]}"; do
        if nix profile list 2>/dev/null | grep -q "$pkg"; then
            log "removing conflicting package from nix profile: $pkg"
            nix profile remove "$pkg" 2>/dev/null || true
        fi
    done
}

# === Apply Nix Configuration ===
apply_config() {
    local arch
    arch=$(uname -m)

    case "$(uname -s)" in
    Darwin)
        log "applying nix-darwin config"
        if has_cmd darwin-rebuild; then
            sudo darwin-rebuild switch --flake .#macos
        else
            sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin -- switch --flake .#macos
        fi
        ;;
    Linux)
        log "applying home-manager config"

        # Clean up any conflicting packages before home-manager
        cleanup_nix_profile

        # Use generic config (auto-detects $USER) or specific arch
        local config
        if [[ "$arch" == "x86_64" ]]; then
            config="linux-generic-x86"
        else
            config="linux-generic"
        fi
        log "using config: $config for user: $USER"

        if has_cmd home-manager; then
            home-manager switch --flake ".#$config" -b backup --impure
        else
            nix --extra-experimental-features 'nix-command flakes' run home-manager -- switch --flake ".#$config" -b backup --impure
        fi
        ;;
    *)
        die "unsupported platform: $(uname -s)"
        ;;
    esac
}

# === Shell Setup ===
set_shell() {
    local target_shell

    # Find nix-installed zsh or bash
    if [[ -x "$HOME/.nix-profile/bin/zsh" ]]; then
        target_shell="$HOME/.nix-profile/bin/zsh"
    elif [[ -x "/etc/profiles/per-user/$USER/bin/zsh" ]]; then
        target_shell="/etc/profiles/per-user/$USER/bin/zsh"
    elif [[ -x "$HOME/.nix-profile/bin/bash" ]]; then
        target_shell="$HOME/.nix-profile/bin/bash"
    elif [[ -x "/etc/profiles/per-user/$USER/bin/bash" ]]; then
        target_shell="/etc/profiles/per-user/$USER/bin/bash"
    else
        log "nix shell not found, keeping current shell"
        return 0
    fi

    local current_shell
    case "$(uname -s)" in
    Darwin)
        current_shell=$(dscl . -read /Users/"$USER" UserShell 2>/dev/null | awk '{print $2}')
        ;;
    Linux)
        current_shell=$(getent passwd "$USER" | cut -d: -f7)
        ;;
    esac

    if [[ "$current_shell" == "$target_shell" ]]; then
        log "shell already set to $target_shell"
        return 0
    fi

    log "changing shell to $target_shell"
    case "$(uname -s)" in
    Darwin)
        grep -qxF "$target_shell" /etc/shells 2>/dev/null || echo "$target_shell" | sudo tee -a /etc/shells >/dev/null
        sudo chsh -s "$target_shell" "$USER"
        ;;
    Linux)
        grep -qxF "$target_shell" /etc/shells 2>/dev/null || echo "$target_shell" | sudo tee -a /etc/shells >/dev/null
        chsh -s "$target_shell"
        ;;
    esac
}

# === Source Shell Config ===
setup_shell_config() {
    local shell_rc
    case "$(basename "$SHELL")" in
    zsh) shell_rc="$HOME/.zshrc" ;;
    bash) shell_rc="$HOME/.bashrc" ;;
    *) return 0 ;;
    esac

    # Linux + bash: use bashrc.sh (includes aliases.sh + one-time setup)
    # macOS + zsh: use aliases.sh directly
    if [[ "$(uname -s)" == "Linux" && "$(basename "$SHELL")" == "bash" ]]; then
        local bashrc_line="source \"$SCRIPT_DIR/tools/bashrc.sh\""
        if ! grep -qF "box/tools/bashrc.sh" "$shell_rc" 2>/dev/null; then
            log "adding box bashrc to $shell_rc"
            # Backup existing bashrc if it exists and isn't empty
            if [[ -f "$shell_rc" && -s "$shell_rc" ]] && ! grep -qF "box/tools" "$shell_rc"; then
                cp "$shell_rc" "$shell_rc.backup"
                log "backed up existing bashrc to $shell_rc.backup"
            fi
            echo "" >>"$shell_rc"
            echo "# Box bashrc (Linux)" >>"$shell_rc"
            echo "[ -f \"$SCRIPT_DIR/tools/bashrc.sh\" ] && $bashrc_line" >>"$shell_rc"
        fi
    else
        # macOS/zsh: source aliases.sh
        local alias_line="source \"$SCRIPT_DIR/tools/aliases.sh\""
        if [[ -f "$shell_rc" ]] && ! grep -qF "box/tools/aliases.sh" "$shell_rc"; then
            log "adding aliases to $shell_rc"
            echo "" >>"$shell_rc"
            echo "# Box aliases" >>"$shell_rc"
            echo "[ -f \"$SCRIPT_DIR/tools/aliases.sh\" ] && $alias_line" >>"$shell_rc"
        fi

        # Source .env if exists (only for zsh, bashrc.sh handles this for bash)
        local env_line="source \"$SCRIPT_DIR/.env\""
        if [[ -f "$shell_rc" ]] && ! grep -qF "box/.env" "$shell_rc"; then
            log "adding .env sourcing to $shell_rc"
            echo "[ -f \"$SCRIPT_DIR/.env\" ] && set -a && $env_line && set +a" >>"$shell_rc"
        fi
    fi
}

# === Node.js CLI Tools ===
install_cli_tools() {
    if ! has_cmd node; then
        log "node not found, will be installed by nix"
        return 0
    fi

    # Claude Code
    if ! has_cmd claude; then
        log "installing claude-code"
        npm install -g @anthropic-ai/claude-code || true
    fi

    # Codex (OpenAI)
    if ! has_cmd codex; then
        log "installing codex"
        npm install -g @openai/codex || true
    fi

    # Gemini CLI
    if ! has_cmd gemini; then
        log "installing gemini-cli"
        npm install -g @google/gemini-cli || true
    fi

    # Qwen Code
    if ! has_cmd qwen; then
        log "installing qwen-code"
        npm install -g @qwen-code/qwen-code@latest || true
    fi

    # Happy Coder (mobile/web access to Claude Code)
    if ! has_cmd happy; then
        log "installing happy-coder"
        npm install -g happy-coder || true
    fi

    # Repomix
    if ! has_cmd repomix; then
        log "installing repomix"
        npm install -g repomix || true
    fi

    # Omnara (AI agent control platform)
    if ! has_cmd omnara; then
        log "installing omnara"
        curl -fsSL https://omnara.com/install/install.sh 2>/dev/null | bash || true
    fi

    # Hawaii CLI (preference-model internal tool)
    if has_cmd uv && [[ -n "${PYX_API_KEY:-}" ]]; then
        if ! has_cmd hawaii; then
            log "installing hawaii cli"
            UV_INDEX="https://api.pyx.dev/simple/preference-model/main" uv tool install pm-hawaii-cli || true
        fi
    fi
}

# === Apply Tool Configs ===
apply_tool_configs() {
    log "applying tool configurations"

    # Load .env for token substitution
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
    fi

    # SSH directory setup (config symlinked by files.ts)
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Restore SSH keys from .env (base64 encoded)
    # IMPORTANT: never overwrite existing keys - they may be server-specific!
    if [[ -n "${SSH_KEY_GITHUB:-}" ]] && [[ ! -f "$HOME/.ssh/github" ]]; then
        echo "$SSH_KEY_GITHUB" | base64 -d >"$HOME/.ssh/github"
        chmod 600 "$HOME/.ssh/github"
        log "restored ~/.ssh/github"
    elif [[ -f "$HOME/.ssh/github" ]]; then
        log "~/.ssh/github exists, skipping (won't overwrite)"
    fi
    if [[ -n "${SSH_KEY_ID_ED25519:-}" ]] && [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
        echo "$SSH_KEY_ID_ED25519" | base64 -d >"$HOME/.ssh/id_ed25519"
        chmod 600 "$HOME/.ssh/id_ed25519"
        log "restored ~/.ssh/id_ed25519"
    elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        log "~/.ssh/id_ed25519 exists, skipping (won't overwrite)"
    fi

    # Gemini settings (needs envsubst for tokens - can't symlink)
    if [[ -f "$SCRIPT_DIR/tools/gemini/settings.json" ]]; then
        mkdir -p "$HOME/.gemini"
        if has_cmd envsubst; then
            envsubst <"$SCRIPT_DIR/tools/gemini/settings.json" >"$HOME/.gemini/settings.json"
        else
            cp "$SCRIPT_DIR/tools/gemini/settings.json" "$HOME/.gemini/settings.json"
        fi
        log "applied gemini settings (with token substitution)"
    fi

    # === Auth/Credentials restoration ===
    # PRINCIPLE: NEVER overwrite existing credentials - they may be server/account-specific!
    # Only restore if file doesn't exist.

    # Gemini OAuth creds
    if [[ -n "${GEMINI_OAUTH_CREDS:-}" ]] && [[ ! -f "$HOME/.gemini/oauth_creds.json" ]]; then
        mkdir -p "$HOME/.gemini"
        echo "$GEMINI_OAUTH_CREDS" | base64 -d >"$HOME/.gemini/oauth_creds.json"
        chmod 600 "$HOME/.gemini/oauth_creds.json"
        log "restored gemini oauth credentials"
    elif [[ -f "$HOME/.gemini/oauth_creds.json" ]]; then
        log "gemini oauth exists, skipping"
    fi

    # Qwen OAuth creds
    if [[ -n "${QWEN_OAUTH_CREDS:-}" ]] && [[ ! -f "$HOME/.qwen/oauth_creds.json" ]]; then
        mkdir -p "$HOME/.qwen"
        echo "$QWEN_OAUTH_CREDS" | base64 -d >"$HOME/.qwen/oauth_creds.json"
        chmod 600 "$HOME/.qwen/oauth_creds.json"
        log "restored qwen oauth credentials"
    elif [[ -f "$HOME/.qwen/oauth_creds.json" ]]; then
        log "qwen oauth exists, skipping"
    fi

    # Codex/OpenAI auth
    if [[ -n "${CODEX_AUTH:-}" ]] && [[ ! -f "$HOME/.codex/auth.json" ]]; then
        mkdir -p "$HOME/.codex"
        echo "$CODEX_AUTH" | base64 -d >"$HOME/.codex/auth.json"
        chmod 600 "$HOME/.codex/auth.json"
        log "restored codex/openai credentials"
    elif [[ -f "$HOME/.codex/auth.json" ]]; then
        log "codex auth exists, skipping"
    fi

    # Happy Coder auth
    if [[ -n "${HAPPY_AUTH:-}" ]] && [[ ! -f "$HOME/.happy/access.key" ]]; then
        mkdir -p "$HOME/.happy"
        echo "$HAPPY_AUTH" | base64 -d >"$HOME/.happy/access.key"
        chmod 600 "$HOME/.happy/access.key"
        log "restored happy-coder credentials"
    elif [[ -f "$HOME/.happy/access.key" ]]; then
        log "happy auth exists, skipping"
    fi

    # Claude Code auth
    if [[ -n "${CLAUDE_AUTH:-}" ]] && [[ ! -f "$HOME/.claude/.claude.json" ]]; then
        mkdir -p "$HOME/.claude"
        echo "$CLAUDE_AUTH" | base64 -d >"$HOME/.claude/.claude.json"
        chmod 600 "$HOME/.claude/.claude.json"
        log "restored claude-code credentials"
    elif [[ -f "$HOME/.claude/.claude.json" ]]; then
        log "claude auth exists, skipping"
    fi

    # GitHub CLI auth (using token)
    if [[ -n "${GH_TOKEN:-}" ]] && has_cmd gh; then
        if ! gh auth status &>/dev/null; then
            log "authenticating github cli"
            echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null || true
            log "github cli authenticated"
        else
            log "github cli already authenticated"
        fi
        # Configure git to use gh for auth (works on Linux without osxkeychain)
        gh auth setup-git 2>/dev/null || true
    fi

    # Coder config (NEVER overwrite on coder workspaces - managed by coder itself)
    if [[ -n "${CODER_URL:-}" ]] && [[ -n "${CODER_SESSION:-}" ]]; then
        local coder_dir
        if [[ "$(uname -s)" == "Darwin" ]]; then
            coder_dir="$HOME/Library/Application Support/coderv2"
        else
            coder_dir="$HOME/.config/coderv2"
        fi
        # Only restore if session file doesn't exist
        if [[ ! -f "$coder_dir/session" ]]; then
            mkdir -p "$coder_dir"
            echo "$CODER_URL" >"$coder_dir/url"
            echo "$CODER_SESSION" >"$coder_dir/session"
            chmod 600 "$coder_dir/session"
            log "restored coder credentials"
        else
            log "coder session exists, skipping"
        fi
    fi

    # Tmux config (always overwrite with latest from box)
    if has_cmd tmux; then
        # Install TPM if missing
        if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
            log "installing tmux plugin manager (tpm)"
            git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm 2>/dev/null || true
        fi

        # Write tmux.conf
        log "writing tmux.conf"
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
    fi
}

# === Symlink Config Files ===
link_configs() {
    # Ensure directories with special permissions exist first
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    mkdir -p "$HOME/.config/gh"
    mkdir -p "$HOME/.config/zed"

    if has_cmd bun && [[ -f "$SCRIPT_DIR/script/files.ts" ]]; then
        log "symlinking config files"
        bun "$SCRIPT_DIR/script/files.ts" || true
    fi
}

# === Main ===
log "============================================"
log "       box setup - full system config      "
log "============================================"

source_nix
install_homebrew
install_nix
source_nix
decrypt_secrets
apply_config
source_nix
install_cli_tools
apply_tool_configs
link_configs
set_shell
setup_shell_config

log "============================================"
log "              DONE! setup complete         "
log "============================================"
log ""
log "installed:"
log "  - nix + home-manager/nix-darwin"
log "  - homebrew packages (macOS)"
log "  - cli tools (claude, codex, gemini, qwen, happy, repomix, omnara)"
log "  - ssh keys restored"
log "  - all tool configs applied"
log ""

# Reload shell with new config (replaces current process)
log "reloading shell..."
exec "$SHELL" -l
