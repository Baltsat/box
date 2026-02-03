# Coder Setup

## Credentials

Stored in `.env`:
- `CODER_URL` - Coder deployment URL
- `CODER_SESSION` - Session token

## Auto-login

`setup.sh` automatically restores credentials to:
- macOS: `~/Library/Application Support/coderv2/`
- Linux: `~/.config/coderv2/`

## Usage

```bash
coder login         # if manual login needed
coder config-ssh    # regenerate SSH config
```
