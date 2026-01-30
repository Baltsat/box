# Global Claude Instructions

These instructions apply to all projects via ~/.claude/CLAUDE.md

## Identity

- Name: Konstantin Baltsat
- Email: baltsat2002@mail.ru
- GitHub: Baltsat

## Preferences

- Language: English for code, comments, commits. Russian is fine for conversation.
- Style: Concise, direct, no fluff. Skip obvious explanations.
- Code: Prefer simplicity over cleverness. Minimal dependencies.

## Critical Rules

1. **NEVER COMMIT WITHOUT ASKING** - Always ask before `git commit`. Never commit automatically.
2. **NEVER PUSH WITHOUT APPROVAL** - Wait for explicit "push" or "go ahead" before pushing.
3. **NEVER CREATE UNNECESSARY FILES** - Reuse existing files. One file > three files.
4. **SECRETS ARE SACRED** - Never commit .env, API keys, tokens, passwords to git.
5. **TEST BEFORE COMMIT** - Run tests/linters before suggesting commits.

## Git

- Commit messages: concise, imperative mood ("Add feature" not "Added feature")
- Format: `type(scope): description` when appropriate
- Always check `git status` and `git diff` before committing
- Never force push to main/master

## Code Style

- TypeScript/JavaScript: Bun preferred, minimal deps
- Python: uv or poetry, type hints
- Nix: 2-space indent
- Bash: `set -euo pipefail`, quote variables

## Tools I Use

- Editor: Cursor
- Terminal: Warp, iTerm2
- Shell: zsh + starship + zoxide
- Package managers: Homebrew (macOS), Nix, pnpm, uv
- Version control: git + gh CLI

## Project Locations

- Dotfiles/configs: ~/box
- Main projects: ~/
- Secrets: ~/box/.env (encrypted as .env.age)

## When Uncertain

- Ask clarifying questions rather than assume
- Show options with trade-offs
- Prefer reversible actions
