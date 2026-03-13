---
name: always delegate to codex
description: user expects heavy codex MCP usage for all implementation work — never write code directly when codex is available
type: feedback
---

always delegate implementation to codex MCP. do NOT write code directly.

**Why:** user pays for codex and expects it used. direct code writing by lead/orchestrator is wrong — lead should plan, decompose, delegate. codex handles boilerplate, tests, CRUD, screens, focused implementations.

**How to apply:** for ANY coding task >10 lines: `codex(prompt="detailed spec", cwd="project-root", sandbox="workspace-write", approval-policy="never")`. iterate with `codex-reply(threadId, "fix X")`. also applies to maestro tests, backend routes, seed scripts — everything that produces code.
