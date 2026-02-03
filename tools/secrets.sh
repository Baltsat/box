#!/usr/bin/env bash
# Secrets management using SOPS with age encryption
# Usage:
#   ./tools/secrets.sh encrypt    # Encrypt .env to .env.sops
#   ./tools/secrets.sh decrypt    # Decrypt .env.sops to .env
#   ./tools/secrets.sh edit       # Edit encrypted file in-place
#   ./tools/secrets.sh view       # View decrypted contents
#   ./tools/secrets.sh rotate     # Re-encrypt with new key
#   ./tools/secrets.sh keygen     # Generate new age key + passphrase backup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$BOX_DIR/.env"
ENCRYPTED_FILE="$BOX_DIR/.env.sops"
MEM_DIR="$HOME/.claude-mem"
MEM_BACKUP="$BOX_DIR/claude-mem.tar.gz.sops"
AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
export SOPS_AGE_KEY_FILE="$AGE_KEY_FILE"

log() { echo "[secrets] $*"; }
die() { log "error: $*"; exit 1; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }
has_cmd sops || die "sops not installed. Run: brew install sops"
has_cmd age || die "age not installed. Run: brew install age"

# Get public key from age key file
get_age_pubkey() {
    [[ -f "$AGE_KEY_FILE" ]] || die "age key not found at $AGE_KEY_FILE. Run: mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt"
    grep "^# public key:" "$AGE_KEY_FILE" | cut -d: -f2 | tr -d ' '
}

encrypt() {
    [[ -f "$ENV_FILE" ]] || die ".env file not found"
    local pubkey
    pubkey=$(get_age_pubkey)
    log "encrypting .env -> .env.sops (age key: ${pubkey:0:20}...)"
    sops --encrypt --age "$pubkey" --input-type dotenv --output-type dotenv --output "$ENCRYPTED_FILE" "$ENV_FILE"
    log "done! .env.sops created (safe to commit)"
}

decrypt() {
    [[ -f "$ENCRYPTED_FILE" ]] || die ".env.sops not found"
    log "decrypting .env.sops -> .env"
    sops --decrypt --input-type dotenv --output-type dotenv "$ENCRYPTED_FILE" > "$ENV_FILE"
    log "done! .env created (do not commit)"
}

edit() {
    if [[ ! -f "$ENCRYPTED_FILE" ]]; then
        if [[ -f "$ENV_FILE" ]]; then
            log "no .env.sops found, encrypting existing .env first..."
            encrypt
        else
            log "creating new secrets file..."
            cat > "$ENV_FILE" << 'TEMPLATE'
# Secrets - this file will be encrypted with SOPS
# Add your API keys and sensitive data here

# OpenAI
OPENAI_API_KEY=

# Anthropic
ANTHROPIC_API_KEY=

# GitHub (for private repos, optional)
# GH_TOKEN=

# Add more secrets as needed...
TEMPLATE
            encrypt
        fi
    fi
    log "editing .env.sops (decrypts in memory, re-encrypts on save)"
    sops --input-type dotenv --output-type dotenv "$ENCRYPTED_FILE"
    log "done!"
}

view() {
    [[ -f "$ENCRYPTED_FILE" ]] || die ".env.sops not found"
    sops --decrypt --input-type dotenv --output-type dotenv "$ENCRYPTED_FILE"
}

rotate() {
    [[ -f "$ENCRYPTED_FILE" ]] || die ".env.sops not found"
    log "rotating keys (re-encrypting)..."
    sops updatekeys "$ENCRYPTED_FILE"
    log "done!"
}

keygen() {
    local key_backup="$BOX_DIR/tools/sops-key.age"

    if [[ -f "$AGE_KEY_FILE" ]]; then
        log "WARNING: age key already exists at $AGE_KEY_FILE"
        read -p "overwrite and generate new key? [y/N] " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || die "aborted"
    fi

    log "generating new age key..."
    mkdir -p "$(dirname "$AGE_KEY_FILE")"
    age-keygen -o "$AGE_KEY_FILE"
    chmod 600 "$AGE_KEY_FILE"

    local pubkey
    pubkey=$(get_age_pubkey)
    log "public key: $pubkey"

    log "creating passphrase-protected backup..."
    log "enter a memorable passphrase:"
    age -p -o "$key_backup" "$AGE_KEY_FILE"
    chmod 644 "$key_backup"

    log "done!"
    log "  age key: $AGE_KEY_FILE"
    log "  backup:  $key_backup"
    log ""
    log "IMPORTANT: update .sops.yaml with new public key:"
    log "  age: $pubkey"
    log ""
    log "then re-encrypt secrets:"
    log "  ./tools/secrets.sh decrypt && ./tools/secrets.sh encrypt"
}

backup_mem() {
    [[ -d "$MEM_DIR" ]] || die "claude-mem directory not found at $MEM_DIR"
    log "backing up claude-mem (~$(du -sh "$MEM_DIR" | cut -f1))"

    local tmp_file pubkey
    tmp_file=$(mktemp)
    trap "rm -f $tmp_file" EXIT
    pubkey=$(get_age_pubkey)

    # Compress
    tar -czf "$tmp_file" -C "$HOME" .claude-mem

    # Encrypt with SOPS (treats as binary)
    sops --encrypt --age "$pubkey" --output "$MEM_BACKUP" "$tmp_file"

    log "done! claude-mem.tar.gz.sops created ($(du -sh "$MEM_BACKUP" | cut -f1))"
}

restore_mem() {
    [[ -f "$MEM_BACKUP" ]] || die "claude-mem.tar.gz.sops not found"

    if [[ -d "$MEM_DIR" ]]; then
        log "WARNING: $MEM_DIR already exists"
        read -p "overwrite? [y/N] " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || die "aborted"
        rm -rf "$MEM_DIR"
    fi

    local tmp_file
    tmp_file=$(mktemp)
    trap "rm -f $tmp_file" EXIT

    sops --decrypt "$MEM_BACKUP" > "$tmp_file"

    # Extract
    tar -xzf "$tmp_file" -C "$HOME"

    log "done! claude-mem restored to $MEM_DIR"
}

migrate_from_age() {
    [[ -f "$BOX_DIR/.env.age" ]] || die ".env.age not found"
    log "migrating from age to SOPS..."
    log "first, decrypt your .env.age manually:"
    echo "  age -d -o .env .env.age"
    echo "then run:"
    echo "  ./tools/secrets.sh encrypt"
    echo "after verifying .env.sops works, delete .env.age"
}

show_help() {
    cat << EOF
Secrets management for box (SOPS + age)

Commands:
  encrypt      Encrypt .env to .env.sops
  decrypt      Decrypt .env.sops to .env
  edit         Edit encrypted file in-place (recommended)
  view         View decrypted contents (stdout)
  rotate       Re-encrypt with updated keys
  keygen       Generate new age key + passphrase backup
  backup-mem   Backup ~/.claude-mem (encrypted)
  restore-mem  Restore ~/.claude-mem from backup
  migrate      Help migrate from old .env.age format

Files:
  .env                       Plaintext secrets (gitignored)
  .env.sops                  Encrypted secrets (committed)
  claude-mem.tar.gz.sops     Encrypted claude-mem backup (committed)
  ~/.config/sops/age/keys.txt  Your age private key (NEVER commit)

Key management:
  Your age key: $AGE_KEY_FILE
  Public key configured in: .sops.yaml

Usage:
  ./tools/secrets.sh edit           # recommended: edit in-place
  ./tools/secrets.sh encrypt        # after editing .env manually
  ./tools/secrets.sh decrypt        # get plaintext .env
  ./tools/secrets.sh view           # view without creating file
EOF
}

case "${1:-help}" in
    encrypt) encrypt ;;
    decrypt) decrypt ;;
    edit) edit ;;
    view) view ;;
    rotate) rotate ;;
    keygen) keygen ;;
    backup-mem) backup_mem ;;
    restore-mem) restore_mem ;;
    migrate) migrate_from_age ;;
    *) show_help ;;
esac
