# box

Personal development environment configuration using Nix.

## Quick Start

```bash
./setup.sh
```

This will install Nix (if needed) and apply the configuration.

## What's Included

### System Configuration
- **nix-darwin** for macOS system settings (dock, finder, trackpad, Touch ID sudo)
- **home-manager** for user environment on both macOS and Linux
- **Homebrew** declarative management (brews and casks)

### CLI Tools
ripgrep, fd, fzf, jq, yq, bat, htop, neovim, tmux, git, gh, tldr, tree, zoxide, lsd, starship, thefuck, ffmpeg, imagemagick, yt-dlp

### macOS Apps (via Homebrew)
- **Productivity**: Raycast, Rectangle, Alt-Tab, Bartender, Karabiner
- **Development**: iTerm2, Warp, Cursor, Postman, DBeaver, TablePlus
- **Browsers**: Chrome, Firefox Developer Edition
- **Media**: IINA, VLC, OBS
- **Utilities**: AppCleaner, Keka, CleanShot, Shottr, Maccy, Stats

### Shell Setup
- Oh My Zsh with plugins (git, completions, autosuggestions, syntax-highlighting)
- Starship prompt
- Zoxide (smart cd)
- Custom aliases

## Structure

| Path | Description |
|------|-------------|
| `flake.nix` | Nix flake definition |
| `macos.nix` | macOS system settings + Homebrew |
| `linux.nix` | Linux-specific config |
| `shared.nix` | Packages and programs for both platforms |
| `setup.sh` | Installation script |
| `tools/` | Tool configurations |
| `script/` | Utility scripts |
| `infra/` | Infrastructure as code |

## Tools Directory

| File | Description |
|------|-------------|
| `starship.toml` | Starship prompt config |
| `karabiner.json` | Keyboard customization |
| `aliases.sh` | Shell aliases |
| `zshrc.template` | ZSH configuration template |
| `gitconfig` | Git configuration reference |

## Customization

1. Edit `shared.nix` to add/remove packages
2. Edit `macos.nix` for macOS settings and Homebrew packages
3. Run `./setup.sh` to apply changes

## First Time Setup

1. Clone this repo to `~/box`
2. Run `./setup.sh`
3. Copy relevant parts from `tools/zshrc.template` to `~/.zshrc`
4. Source aliases: add `source ~/box/tools/aliases.sh` to your shell config
5. Decrypt secrets: `./tools/secrets.sh decrypt`

## Secrets Management

Secrets are encrypted using [AGE](https://github.com/FiloSottile/age) with password protection.

| File | Description |
|------|-------------|
| `.env` | Plaintext secrets (gitignored, local only) |
| `.env.age` | Encrypted secrets (safe to commit) |
| `.env.template` | Template for new secrets |

**Commands:**
```bash
./tools/secrets.sh decrypt   # Decrypt .env.age -> .env
./tools/secrets.sh encrypt   # Encrypt .env -> .env.age
./tools/secrets.sh edit      # Decrypt, edit, re-encrypt
./tools/secrets.sh rekey     # Change password
```
