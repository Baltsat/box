#!/usr/bin/env bash
# Pre-commit hook: auto-format code before commits
# Install: ./script/precommit.sh install
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_DIR="$(dirname "$SCRIPT_DIR")"

log() { echo "[precommit] $*"; }
has_cmd() { command -v "$1" &>/dev/null; }

# Format Nix files
fmt_nix() {
    has_cmd nixfmt || return 0
    local files=(flake.nix shared.nix linux.nix macos.nix)
    for f in "${files[@]}"; do
        [[ -f "$BOX_DIR/$f" ]] && nixfmt "$BOX_DIR/$f" 2>/dev/null || true
    done
    log "nix formatted"
}

# Format shell scripts
fmt_shell() {
    has_cmd shfmt || return 0
    find "$BOX_DIR" -name "*.sh" -type f | while read -r f; do
        shfmt -w -i 4 "$f" 2>/dev/null || true
    done
    has_cmd shellcheck && {
        find "$BOX_DIR" -name "*.sh" -type f | xargs shellcheck 2>/dev/null || true
    }
    log "shell formatted"
}

# Format TOML files
fmt_toml() {
    has_cmd taplo || return 0
    find "$BOX_DIR" -name "*.toml" -type f | while read -r f; do
        taplo format "$f" 2>/dev/null || true
    done
    log "toml formatted"
}

# Format JSON files
fmt_json() {
    has_cmd prettier || return 0
    find "$BOX_DIR" -name "*.json" -type f ! -path "*/node_modules/*" | while read -r f; do
        prettier --write "$f" 2>/dev/null || true
    done
    log "json formatted"
}

# Format TypeScript files
fmt_typescript() {
    has_cmd prettier || return 0
    find "$BOX_DIR" -name "*.ts" -type f ! -path "*/node_modules/*" | while read -r f; do
        prettier --write "$f" 2>/dev/null || true
    done
    log "typescript formatted"
}

# Format Python files
fmt_python() {
    has_cmd ruff || return 0
    find "$BOX_DIR" -name "*.py" -type f | while read -r f; do
        ruff format "$f" 2>/dev/null || true
        ruff check --fix "$f" 2>/dev/null || true
    done
    log "python formatted"
}

# Encrypt secrets with SOPS (only if .env changed)
run_sops() {
    [[ -f "$BOX_DIR/.env" ]] || return 0
    [[ -f "$BOX_DIR/tools/secrets.sh" ]] || return 0
    # Skip if .env.sops exists and is newer than .env
    if [[ -f "$BOX_DIR/.env.sops" ]] && [[ ! "$BOX_DIR/.env" -nt "$BOX_DIR/.env.sops" ]]; then
        return 0
    fi
    "$BOX_DIR/tools/secrets.sh" encrypt 2>/dev/null || true
    log "secrets encrypted"
}

# Install as git pre-commit hook
install_hook() {
    local hook_path="$BOX_DIR/.git/hooks/pre-commit"
    mkdir -p "$(dirname "$hook_path")"
    cat >"$hook_path" <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/script/precommit.sh" run
EOF
    chmod +x "$hook_path"
    log "pre-commit hook installed"
}

# Run all formatters
run_all() {
    log "running formatters..."
    fmt_nix
    fmt_shell
    fmt_toml
    fmt_json
    fmt_typescript
    fmt_python
    run_sops
    log "done"
}

show_help() {
    cat <<EOF
Pre-commit hook for box

Commands:
  run       Run all formatters (default)
  install   Install as git pre-commit hook
  nix       Format nix files only
  shell     Format shell scripts only
  toml      Format toml files only
  json      Format json files only
  ts        Format typescript files only
  python    Format python files only
  sops      Encrypt secrets

Usage:
  ./script/precommit.sh run
  ./script/precommit.sh install
EOF
}

case "${1:-run}" in
run) run_all ;;
install) install_hook ;;
nix) fmt_nix ;;
shell) fmt_shell ;;
toml) fmt_toml ;;
json) fmt_json ;;
ts) fmt_typescript ;;
python) fmt_python ;;
sops) run_sops ;;
*) show_help ;;
esac
