# box

Personal development environment. One command to set up a new machine.

## Setup

```bash
git clone https://github.com/Baltsat/box.git ~/box && ~/box/setup.sh
```

Enter password when prompted. Done.

## What It Does

1. Installs Nix + Homebrew
2. Decrypts secrets (API keys, tokens)
3. Configures macOS system settings
4. Installs all packages and apps
5. Sets up shell (zsh, starship, aliases)
6. Symlinks config files

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
└── .env.age        # Encrypted secrets
```

## Updating

After editing nix files:

```bash
~/box/setup.sh
```

## Secrets

```bash
~/box/tools/secrets.sh decrypt  # Decrypt to .env
~/box/tools/secrets.sh encrypt  # Encrypt .env to .env.age
~/box/tools/secrets.sh edit     # Edit secrets
~/box/tools/secrets.sh rekey    # Change password
```

## Customization

- **Packages**: Edit `shared.nix`
- **macOS settings**: Edit `macos.nix`
- **Homebrew apps**: Edit `homebrew.brews` and `homebrew.casks` in `macos.nix`
- **Aliases**: Edit `tools/aliases.sh`
