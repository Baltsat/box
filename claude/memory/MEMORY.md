## claude-cron-worker (~/claude-cron-worker)
- cloudflare worker that sends slack messages to claude bot to consume subscription quota
- uses xoxc (browser session) token + d cookie — NOT xoxp (app token), bc app tokens have bot_id and claude ignores bot messages
- xoxc tokens extracted from browser: DevTools → Console → `JSON.parse(localStorage.localConfig_v2).teams[...].token`
- d cookie from DevTools → Application → Cookies → `.slack.com`
- d cookie expires ~1yr, xoxc tied to browser session
- workspace: EMAIT (T0958SJN59Q), channel: D0ADCT2FNJ2
- worker URL: claude-cron-worker.baltsat2002.workers.dev
- deploy: push to main → github actions → wrangler deploy
- secrets in github: SLACK_TOKEN (xoxc), SLACK_COOKIE (d cookie), CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID

## agent teams
- enabled via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in claude.json
- teammateMode: tmux (split panes)
- hooks configured:
  - `TeammateIdle` → `~/box/tools/hooks/teammate-idle.sh` (nudges once to check tasks, then lets go idle)
  - `TaskCompleted` → prompt hook (LLM verifies task genuinely done before marking complete)
- docs: https://code.claude.com/docs/en/agent-teams

## box aliases
- `rm` is aliased to `_box_protected_rm` — use `/bin/rm` for actual removal
- bash env doesn't have aliases loaded, use full paths
