# Box Project Instructions

Personal development environment configuration repository.

## Structure

```
box/
├── flake.nix          # Nix flake entry point
├── macos.nix          # macOS config (nix-darwin + Homebrew)
├── linux.nix          # Linux config (home-manager)
├── shared.nix         # Shared packages and programs
├── setup.sh           # Main setup script
├── tools/             # Tool configurations
│   ├── starship.toml  # Prompt config
│   ├── karabiner.json # Keyboard mappings
│   ├── aliases.sh     # Shell aliases
│   └── zshrc.template # ZSH template
├── script/            # Utility scripts
└── infra/             # Infrastructure code
```

## Usage

After making changes to nix files:
```bash
./setup.sh
```

## Important Notes

- Always run `./setup.sh` after making changes to nix files
- Keep secrets in separate `.env` files, never commit them
- Tool configs in `tools/` can be symlinked or sourced manually
- Write platform-agnostic code where possible (use `$HOME` not hardcoded paths)

## Homebrew

Homebrew packages are managed declaratively in `macos.nix`. The config uses `cleanup = "none"` to avoid removing packages installed outside of nix-darwin.
