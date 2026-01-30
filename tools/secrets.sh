#!/usr/bin/env bash
# Secrets management using AGE encryption with password
# Usage:
#   ./tools/secrets.sh encrypt    # Encrypt .env to .env.age
#   ./tools/secrets.sh decrypt    # Decrypt .env.age to .env
#   ./tools/secrets.sh edit       # Decrypt, edit, re-encrypt
#   ./tools/secrets.sh rekey      # Re-encrypt with new password

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$BOX_DIR/.env"
ENCRYPTED_FILE="$BOX_DIR/.env.age"

log() { echo "[secrets] $*"; }
die() { log "error: $*"; exit 1; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }
has_cmd age || die "age not installed. Run: brew install age"

encrypt() {
    [[ -f "$ENV_FILE" ]] || die ".env file not found"
    log "Encrypting .env -> .env.age"
    log "Enter your encryption password:"
    age -p -o "$ENCRYPTED_FILE" "$ENV_FILE"
    log "Done! .env.age created (safe to commit)"
}

decrypt() {
    [[ -f "$ENCRYPTED_FILE" ]] || die ".env.age not found"
    log "Decrypting .env.age -> .env"
    log "Enter your decryption password:"
    age -d -o "$ENV_FILE" "$ENCRYPTED_FILE"
    log "Done! .env created (do not commit)"
}

edit() {
    local tmp_file
    tmp_file=$(mktemp)
    trap "rm -f $tmp_file" EXIT

    if [[ -f "$ENCRYPTED_FILE" ]]; then
        log "Decrypting for editing..."
        age -d -o "$tmp_file" "$ENCRYPTED_FILE"
    elif [[ -f "$ENV_FILE" ]]; then
        cp "$ENV_FILE" "$tmp_file"
    else
        log "Creating new secrets file..."
        cat > "$tmp_file" << 'TEMPLATE'
# Secrets - this file will be encrypted
# Add your API keys and sensitive data here

# OpenAI
OPENAI_API_KEY=

# Anthropic
ANTHROPIC_API_KEY=

# GitHub (for private repos, optional)
# GH_TOKEN=

# Add more secrets as needed...
TEMPLATE
    fi

    ${EDITOR:-vim} "$tmp_file"

    log "Re-encrypting..."
    age -p -o "$ENCRYPTED_FILE" "$tmp_file"
    log "Done! .env.age updated"
}

rekey() {
    [[ -f "$ENCRYPTED_FILE" ]] || die ".env.age not found"
    log "Re-keying secrets with new password"
    log "First, enter your CURRENT password to decrypt:"

    local tmp_file
    tmp_file=$(mktemp)
    trap "rm -f $tmp_file" EXIT

    age -d -o "$tmp_file" "$ENCRYPTED_FILE"

    log "Now enter your NEW password to encrypt:"
    age -p -o "$ENCRYPTED_FILE" "$tmp_file"
    log "Done! .env.age re-encrypted with new password"
}

show_help() {
    cat << EOF
Secrets management for box

Commands:
  encrypt   Encrypt .env to .env.age
  decrypt   Decrypt .env.age to .env
  edit      Decrypt, edit in \$EDITOR, re-encrypt
  rekey     Re-encrypt with a new password

Files:
  .env      Plaintext secrets (gitignored, local only)
  .env.age  Encrypted secrets (safe to commit)

Usage:
  ./tools/secrets.sh encrypt
  ./tools/secrets.sh decrypt
  ./tools/secrets.sh edit
  ./tools/secrets.sh rekey
EOF
}

case "${1:-help}" in
    encrypt) encrypt ;;
    decrypt) decrypt ;;
    edit) edit ;;
    rekey) rekey ;;
    *) show_help ;;
esac
