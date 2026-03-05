# box

Personal development environment. One command to set up a new machine.

## Quick Recovery (Any Server)

```bash
([ -d "$HOME/box/.git" ] || git clone https://github.com/Baltsat/box.git "$HOME/box") && cd "$HOME/box" && git fetch origin && git reset --hard origin/main && rm -f ~/.box_setup_done && (./setup.sh || (unset NIX_REMOTE NIX_DAEMON_SOCKET_PATH; NIX_REMOTE=local ./setup.sh)) && exec "$SHELL" -l
```

## Setup

**Fresh server:**
```bash
git clone https://github.com/Baltsat/box.git ~/box && ~/box/setup.sh
```

**Update existing box (force reset + reinstall everything):**
```bash
cd ~/box && git fetch origin && git reset --hard origin/main && rm -f ~/.box_setup_done && ./setup.sh && source ~/.bashrc
```

Enter password when prompted. Done.

## What It Does

1. Installs Nix + Homebrew
2. Decrypts secrets (API keys, tokens)
3. Configures macOS system settings
4. Installs all packages and apps
5. Sets up shell (zsh, starship, aliases)
6. Symlinks config files

## Resilient Remote Connect

Use `mssh` to keep sessions stable during Wi-Fi/network switches:

```bash
mssh user@server
mssh my-ssh-alias
```

Behavior:
- If local `mosh` is installed, `mssh` uses `mosh`.
- `mssh` runs `mosh` with quiet SSH bootstrap flags to reduce noisy helper disconnect lines.
- If local `mosh` is missing, `mssh` falls back to `ssh`.
- If `mosh` exits with an error, `mssh` retries with SSH keepalive options.
- If `mosh` exits too quickly (under 3 seconds), `mssh` also retries with SSH keepalive options.
- After a failed/too-quick `mosh` attempt, that host is put on a temporary `ssh` cooldown (default: 30 minutes) to avoid repeated failed `mosh` attempts.
- Override knobs: `MSSH_FORCE_MOSH=1` (bypass cooldown), `MSSH_MOSH_MIN_OK_SECONDS`, `MSSH_MOSH_COOLDOWN_SECONDS`.
- It opens a normal remote shell (no forced tmux attach).

Scope:
- `box` installs `mosh` in Linux/server paths.
- macOS package provisioning is unchanged in `box` (you can still install `mosh` manually on your Mac if desired).
- Linux `mosh` version is pinned through `flake.lock` (Nix), avoiding distro `apt` version drift.

Prerequisites for `mosh` mode:
- Remote host must have `mosh-server` available.
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
