# box

Personal development environment. One command to set up a new machine.

## Quick Recovery (Any Server)

If the image is bare and `git` is missing, install `git` first.

```bash
([ -d "$HOME/box/.git" ] || git clone https://github.com/Baltsat/box.git "$HOME/box") && cd "$HOME/box" && git fetch origin && git reset --hard origin/main && rm -f ~/.box_setup_done && (./setup.sh || (unset NIX_REMOTE NIX_DAEMON_SOCKET_PATH; NIX_REMOTE=local ./setup.sh)) && exec "$SHELL" -l
```

## Setup

**Fresh server:**
```bash
git clone https://github.com/Baltsat/box.git ~/box && ~/box/setup.sh
```

If the image is bare and `git` is missing, install `git` first.

**Update existing box (force reset + reinstall everything):**
```bash
cd ~/box && git fetch origin && git reset --hard origin/main && rm -f ~/.box_setup_done && ./setup.sh
```

Enter password when prompted. Done.

## What It Does

1. Installs Nix + Homebrew
2. Decrypts secrets (API keys, tokens)
3. Configures macOS system settings
4. Installs all packages and apps
5. Sets up shell (zsh, starship, aliases)
6. Symlinks config files
7. Syncs `GLOBAL.md` as global AI instructions (including Codex `AGENTS.md`)

## Resilient Remote Connect

Use `mssh` to keep sessions stable during Wi-Fi/network switches:

```bash
mssh user@server
mssh my-ssh-alias
```

Behavior:
- If local `mosh` is installed, `mssh` uses `mosh`.
- `mssh` runs `mosh` with quiet SSH bootstrap flags to reduce noisy helper disconnect lines.
- `mssh` also prepends common Nix profile paths before launching remote `mosh-server`, so fresh Home Manager boxes work without manual PATH surgery.
- If local `mosh` is missing, `mssh` falls back to `ssh`.
- If `mosh` exits with an error, `mssh` retries with SSH keepalive options.
- If `mosh` exits too quickly (under 3 seconds), `mssh` also retries with SSH keepalive options.
- After a failed/too-quick `mosh` attempt, that host is put on a temporary `ssh` cooldown (default: 30 minutes) to avoid repeated failed `mosh` attempts.
- If you fix the server and want to retry `mosh` immediately, use `MSSH_FORCE_MOSH=1 mssh host` or clear `~/.cache/mssh_unhealthy_hosts`.
- Override knobs: `MSSH_FORCE_MOSH=1` (bypass cooldown), `MSSH_MOSH_MIN_OK_SECONDS`, `MSSH_MOSH_COOLDOWN_SECONDS`.
- It opens a normal remote shell (no forced tmux attach).

Scope:
- `box` provisions the `mosh` client for both macOS and Linux through the shared Home Manager package set.
- `setup.sh` passes the active macOS user through `BOX_USER`, so nix-darwin/home-manager land on the right account on fresh Macs.
- `mosh` versions stay pinned through `flake.lock` (Nix), avoiding brew/apt drift across fresh installs.

Prerequisites for `mosh` mode:
- Remote host must have `mosh-server` available on the non-interactive SSH path.
- UDP traffic for mosh must be allowed (default range `60000-61000`).

## Structure

```
~/box/
├── flake.nix       # Nix entry point
├── macos.nix       # macOS settings + Homebrew
├── linux.nix       # Linux config
├── shared.nix      # Shared packages
├── setup.sh        # One-command setup
├── tools/          # Configs (starship, karabiner, aliases, etc.)
├── script/         # Utility scripts
└── .env.sops        # Encrypted secrets
```

## Updating

After editing nix files:

```bash
~/box/setup.sh
```

## Secrets

```bash
~/box/tools/secrets.sh decrypt  # Decrypt to .env
~/box/tools/secrets.sh encrypt  # Encrypt .env to .env.sops
~/box/tools/secrets.sh edit     # Edit secrets
~/box/tools/secrets.sh rekey    # Change password
```

## Customization

- **Packages**: Edit `shared.nix`
- **Linux-only packages**: Edit `linux.nix`
- **macOS settings**: Edit `macos.nix`
- **Homebrew apps**: Edit `homebrew.brews` and `homebrew.casks` in `macos.nix`
- **Aliases**: Edit `tools/aliases.sh`
