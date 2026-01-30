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

source_nix() {
    local daemon_sh="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    local profile_sh="$HOME/.nix-profile/etc/profile.d/nix.sh"
    # shellcheck source=/dev/null
    [[ -f $daemon_sh ]] && . "$daemon_sh" && return 0
    # shellcheck source=/dev/null
    [[ -f $profile_sh ]] && . "$profile_sh" && return 0
    return 0
}

install_nix() {
    has_cmd nix && return 0
    log "installing nix via determinate systems installer"
    curl --proto '=https' --tlsv1.2 -sSf -L \
        https://install.determinate.systems/nix | sh -s -- install --no-confirm
    source_nix
    has_cmd nix || die "nix installation failed"
}

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

source_nix
install_nix
apply_config
source_nix
log "done"
