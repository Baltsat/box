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

# === AGE Setup ===
install_age() {
    has_cmd age && return 0
    log "installing age for secrets decryption"
    if has_cmd brew; then
        brew install age
    elif has_cmd nix; then
        nix-env -iA nixpkgs.age
    else
        die "cannot install age: no package manager available"
    fi
}

# === Secrets Decryption ===
decrypt_secrets() {
    [[ ! -f "$SCRIPT_DIR/.env.age" ]] && return 0
    [[ -f "$SCRIPT_DIR/.env" ]] && {
        log "secrets already decrypted (.env exists)"
        return 0
    }
    log "decrypting secrets..."
    log "enter your password:"
    age -d -o "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.age"
    log "secrets decrypted to .env"
}

# === Apply Nix Configuration ===
apply_config() {
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
        if has_cmd home-manager; then
            home-manager switch --flake .#linux -b backup
        else
            nix --extra-experimental-features 'nix-command flakes' run home-manager -- switch --flake .#linux -b backup
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
        zsh)  shell_rc="$HOME/.zshrc" ;;
        bash) shell_rc="$HOME/.bashrc" ;;
        *)    return 0 ;;
    esac

    # Add alias sourcing if not present
    local alias_line="source \"$SCRIPT_DIR/tools/aliases.sh\""
    if [[ -f "$shell_rc" ]] && ! grep -qF "box/tools/aliases.sh" "$shell_rc"; then
        log "adding aliases to $shell_rc"
        echo "" >> "$shell_rc"
        echo "# Box aliases" >> "$shell_rc"
        echo "[ -f \"$SCRIPT_DIR/tools/aliases.sh\" ] && $alias_line" >> "$shell_rc"
    fi

    # Source .env if exists
    local env_line="source \"$SCRIPT_DIR/.env\""
    if [[ -f "$shell_rc" ]] && ! grep -qF "box/.env" "$shell_rc"; then
        log "adding .env sourcing to $shell_rc"
        echo "[ -f \"$SCRIPT_DIR/.env\" ] && set -a && $env_line && set +a" >> "$shell_rc"
    fi
}

# === Symlink Config Files ===
link_configs() {
    if has_cmd bun && [[ -f "$SCRIPT_DIR/script/files.ts" ]]; then
        log "symlinking config files"
        bun "$SCRIPT_DIR/script/files.ts" || true
    fi
}

# === Main ===
log "starting box setup"

source_nix
install_homebrew
install_nix
source_nix
install_age
decrypt_secrets
apply_config
source_nix
link_configs
set_shell
setup_shell_config

log "============================================"
log "done! restart your terminal to apply changes"
log "============================================"
