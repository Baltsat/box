# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project Overview

**box** is a personal development environment configuration using Nix (nix-darwin + home-manager). One command sets up a fresh macOS or Linux machine with all tools, settings, and secrets.

## Quick Reference

**Entry point:** `./setup.sh`

**Primary files:**
- `shared.nix` - Packages for both platforms
- `macos.nix` - macOS system settings + Homebrew
- `tools/aliases.sh` - Shell aliases and functions
- `tools/secrets.sh` - Secret management

**After any nix file changes:**
```bash
./setup.sh
```

## Critical Rules

1. **NEVER COMMIT SECRETS** - `.env` is gitignored. Only `.env.sops` (encrypted) is committed. Never add API keys, tokens, or passwords to tracked files.

2. **NEVER COMMIT WITHOUT ASKING** - Always ask user for approval before running `git commit`. Never commit automatically.

3. **NEVER PUSH WITHOUT EXPLICIT APPROVAL** - Wait for user's explicit approval before pushing. If user says "don't push" - no push under any circumstances.

4. **TEST ON FRESH ENVIRONMENT** - Major changes should be tested in GitHub Codespace or VM before committing. The setup must work with only `git clone` + `./setup.sh`.

5. **KEEP IT SIMPLE** - This is a personal dotfiles repo, not a framework. Avoid over-engineering. One file is better than three.

6. **MINIMIZE FILE CREATION** - Reuse existing files. Don't create new configs unless absolutely necessary.

7. **PLATFORM AWARENESS** - Code should work on both macOS (nix-darwin) and Linux (home-manager). Use conditionals where needed.

8. **NEVER OVERWRITE CREDENTIALS** - setup.sh must NEVER overwrite existing SSH keys, OAuth tokens, or auth files. Only create if missing/invalid.

## Testing Protocol

**ALWAYS run `./setup.sh` after making changes.**

**CRITICAL: `./setup.sh` MUST be called as a SEPARATE, SINGLE tool call.**
- NEVER batch setup.sh with other parallel tool calls
- Workflow: make changes → run other tools → THEN separately call setup.sh
- Reason: setup.sh depends on git-tracked files. If batched with parallel Edit/Write calls that haven't completed yet, you'll rebuild old config state instead of new changes.

**Linux VM testing via orb cli:**
```bash
orb run -m nix
# orb automatically mounts cwd and cd's into ~/box inside vm
# vm already has nix installed
```

## Code Principles

Write maximally GENERIC code that is platform, user, hostname agnostic:

- Use `$HOME` instead of hardcoded paths like `/Users/username`
- Use platform detection (`uname`, `pkgs.stdenv.isDarwin`) instead of assuming OS
- Configuration should work identically on macOS and Linux wherever possible
- NEVER hardcode usernames or machine-specific paths

## File Structure

```
box/
├── flake.nix           # Nix flake entry (DO NOT edit unless necessary)
├── macos.nix           # macOS: system.defaults + homebrew
├── linux.nix           # Linux: home-manager config
├── shared.nix          # Packages + programs for both platforms
├── setup.sh            # Main entry point
├── tools/
│   ├── aliases.sh      # Shell aliases (sourced in .zshrc)
│   ├── secrets.sh      # Encrypt/decrypt/edit secrets
│   ├── starship.toml   # Prompt config
│   ├── karabiner.json  # Keyboard remapping
│   ├── claude.json     # Claude Code settings
│   └── cursor/         # Cursor editor configs
├── script/
│   └── files.ts        # Symlinks configs to proper locations
├── .env.sops            # Encrypted secrets (committed)
├── .env.template       # Template for secrets (committed)
└── .env                # Decrypted secrets (gitignored, local only)
```

## Common Tasks

### Adding a package

```nix
# In shared.nix (for both platforms):
home.packages = with pkgs; [
  new-package
];

# In macos.nix (Homebrew only):
homebrew.brews = [ "new-package" ];
homebrew.casks = [ "new-app" ];
```

Then run `./setup.sh`.

### Adding an alias

Edit `tools/aliases.sh`:
```bash
alias myalias='my-command'
```

### Adding a secret

1. Add to `.env.template`: `NEW_SECRET=`
2. Add value to `.env`: `NEW_SECRET=actual_value`
3. Encrypt: `./tools/secrets.sh encrypt`
4. Commit `.env.sops` and `.env.template`

### Testing changes

```bash
# Quick test (local):
./setup.sh

# Full test (fresh environment):
# Create GitHub Codespace and run:
git clone https://github.com/Baltsat/box.git ~/box && ~/box/setup.sh
```

## Nix Patterns

### Platform-specific code

```nix
# In flake.nix, platforms are separate:
darwinConfigurations.macos = ...   # macOS
homeConfigurations.linux = ...     # Linux
```

### Adding macOS system setting

```nix
# In macos.nix:
system.defaults.dock.autohide = true;
system.defaults.NSGlobalDomain.KeyRepeat = 2;
```

### Adding Homebrew package

```nix
# In macos.nix:
homebrew.brews = [ "package-name" ];  # CLI tools
homebrew.casks = [ "app-name" ];      # GUI apps
```

## Troubleshooting

### Setup fails on fresh machine

1. Check internet connection
2. Verify Xcode CLI tools: `xcode-select --install`
3. Check for disk space
4. Look at error output - usually a missing dependency

### Nix command not found after install

```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### Home-manager conflicts

```bash
# Remove conflicting package:
nix profile remove <package>
# Then re-run:
./setup.sh
```

### Secrets won't decrypt

- Verify age key exists: `~/.config/sops/age/keys.txt`
- Verify `.env.sops` exists and isn't corrupted
- Try: `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops --decrypt .env.sops`

## Code Style

- **Nix**: 2-space indent, no trailing semicolons in lists
- **Bash**: Use `set -euo pipefail`, quote variables
- **TypeScript**: Use Bun, minimal dependencies

## Git Workflow

1. Make changes locally
2. Test with `./setup.sh`
3. For major changes, test in Codespace
4. Commit with clear message
5. Push only after explicit approval

## Cloudflared Certs

cloudflared stores auth certs at `~/.cloudflared/cert.pem`. Only one cert can be active at a time (overwrites on login).

Saved certs for account switching:
- `~/.cloudflared/cert-yaitso.pem` (yaitso.com account)
- `~/.cloudflared/cert-other.pem` (other account)

To use specific account:
```bash
TUNNEL_ORIGIN_CERT=~/.cloudflared/cert-yaitso.pem cloudflared tunnel list
```
