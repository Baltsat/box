# Gemini CLI Instructions

## Setup

1. Install: `npm install -g @google/gemini-cli`
2. Auth: `gemini` (will prompt for Google OAuth)
3. Apply settings: run `~/box/script/apply-gemini.sh`

## MCP Servers Configured

- **sequential-thinking**: Chain-of-thought reasoning
- **shadcn**: UI component library
- **playwright**: Browser automation (requires Docker)
- **Bright Data**: Web scraping API (requires BRIGHT_DATA_API_TOKEN)
- **github**: GitHub Copilot MCP (requires GITHUB_PAT)

## Settings

Settings file: `~/.gemini/settings.json`
Template in box: `tools/gemini/settings.json`

Key settings:
- `security.enablePermanentToolApproval`: true
- `ui.hideTips/Banner/ContextSummary`: true (cleaner UI)
- `tools.autoAccept`: true
- `experimental.plan`: true

## Usage

```bash
gemini              # start interactive session
gemini "query"      # one-shot query
```
